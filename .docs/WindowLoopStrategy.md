# US-011 — Estratégia cooperativa do loop de janela

> **Atualização da US-012:** o usuário autorizou especificamente
> `makeKeyAndOrderFrontAsync(_:) async throws`. A decisão e as limitações da
> implementação estão em [WindowLoopCooperative.md](WindowLoopCooperative.md).
> O bloqueio descrito abaixo registra o estado anterior à autorização.

**Estado:** bloqueio documentado; nenhuma estratégia é implementável dentro das
restrições públicas atuais.

**Escopo:** decisão para a US-012; não implementa nem aprova mudança de API.

## Decisão

Não adotar loop integrado à plataforma, atualização incremental ou API aditiva
como implementação da US-012 neste momento. O código e a medição da US-010
mostram que atualização incremental isolada não torna o loop cooperativo; as
duas outras opções requerem coordenação e comportamento que não podem ser
garantidos apenas alterando corpos de implementação sob as regras atuais.

A direção técnica preferida, **sujeita à autorização explícita de uma nova
declaração pública**, é uma API assíncrona aditiva com um único coordenador de
eventos para todas as janelas. A API síncrona existente permaneceria intacta e
continuaria bloqueante. Essa preferência não é uma aprovação para a US-012 e
não deve ser tratada como implementação concluída.

Para desbloquear a US-012, o mantenedor precisa decidir se autoriza uma nova
API pública assíncrona e seu contrato de cancelamento. Até lá, não se deve
alterar assinaturas existentes nem prometer progresso cooperativo, baixo uso
de CPU em repouso ou operação simultânea de várias janelas.

## Evidência do código e baseline

`CGWindow` é isolada ao `MainActor`. A assinatura pública atual é
`open func makeKeyAndOrderFront(_ sender: Any? = nil)`: ela mostra a janela e
permanece num `while` síncrono chamando `pollEvents`, `clear`,
`displayIfNeeded` e `swapBuffers` até o pedido de fechamento. Não há ponto de
suspensão Swift nesse ciclo. `displayIfNeeded()` só condiciona a closure de
desenho e o `flush` a `viewsNeedDisplay`; o loop ainda limpa e troca buffers
em todas as iterações. Existe um helper interno `waitEvents()`, mas o loop
atual não o usa. O helper, por si só, também não fornece cooperação com o
executor Swift nem acorda quando uma propriedade comum muda.

A [baseline da US-010](WindowLoopBaseline.md), medida em macOS 26.6.2 num
Apple M3 Pro, registrou durante aproximadamente 2 s de repouso:

| Medida | Observação |
|---|---:|
| CPU do processo | 0,090804 s; 4,5412% de um núcleo |
| Iterações do loop | 121 |
| Eventos sintéticos | 20/20 recebidos; latência mediana de 16,515 ms |
| Chamadas de desenho durante repouso | 0 |
| Fechamento AppKit até retorno do método | 102,704 ms |
| Outra janela | 0 chamadas automáticas de `display`; 1 chamada após `displayIfNeeded()` explícito |
| Tarefa agendada no `MainActor` | Executou antes do retorno nesta amostra |

É uma observação de uma máquina, não uma meta nem uma garantia. A tarefa
executada durante o loop não prova que o método síncrono cede o ator de forma
geral. A ausência de chamadas de desenho tampouco significa repouso eficiente:
o loop continuou a fazer polling, clear e swap, e não preservou necessariamente
a imagem apresentada. A medição não comprova FPS apresentado, operação de dois
loops simultâneos, nem comportamento em Linux ou Windows.

## Comparação das alternativas

| Alternativa | Isolamento e progresso | Compatibilidade | Cancelamento e despertar | Múltiplas janelas |
|---|---|---|---|---|
| **Loop integrado à plataforma** | Um loop de plataforma pode encaminhar eventos e evitar polling contínuo. Porém, substituir o `while` por espera síncrona dentro do método `@MainActor` continua sem um ponto de suspensão Swift garantido. Integração com o executor depende do event loop e da plataforma. | A assinatura poderia permanecer, mas mudar de um loop privado por janela para um loop global altera o ciclo de vida, a ordem de retorno e a integração do host. O código atual usa GLFW; uma integração específica a AppKit não cobre Linux/Windows. | Eventos nativos podem acordar o loop. Redraw externo, cancelamento e animações precisam de fonte/timer e caminho explícito de wake-up; não há contrato público existente para isso. | Exige um loop global, não um loop por chamada. Não está implementado um proprietário/dispatcher compartilhado; chamar o método para uma segunda janela enquanto a primeira está no loop não inicia um segundo loop cooperativo. |
| **Atualização incremental** | Desenhar somente quando `viewsNeedDisplay` for verdadeiro reduz trabalho de renderização, mas não libera o `MainActor` enquanto o loop síncrono continua a consultar eventos. | Pode preservar as assinaturas se restrita ao corpo do loop e a `displayIfNeeded`; portanto, é a alternativa de menor impacto de API, mas não satisfaz o objetivo de cooperação. | Para reduzir o custo em repouso, seria necessário esperar por eventos; animação requer prazo de frame e redraw/cancelamento precisam acordar a espera. `viewsNeedDisplay` é uma propriedade pública comum sem notificação de mudança; não há hoje um mecanismo explícito de invalidação que acorde `waitEvents()`. Polling temporizado é apenas um compromisso de latência/CPU. | Pular desenho de uma janela não cria coordenação entre janelas. O loop atual é iniciado por instância e a baseline não observou desenho automático da segunda janela. |
| **API aditiva assíncrona** | Uma operação `async` isolada ao `MainActor` pode suspender entre processamento de eventos e frames, permitindo progresso de outras tarefas do ator. Cada operação de janela ainda deve selecionar seu contexto GL antes de desenho, readback e teardown. | Preserva a chamada antiga e seu comportamento, mas requer uma **nova declaração pública**. Isso é proibido pelas regras atuais sem decisão específica; não é possível implementar uma entrada assíncrona pública criando apenas funções privadas. | Cancelamento precisa ser observado em pontos seguros e acordar qualquer espera bloqueada. A tarefa cancelada pode terminar com `CancellationError`; cancelar o processamento não deve fechar implicitamente a janela. Eventos de fechamento encerram a participação daquela janela. Animações precisam de deadline/timer; redraw e cancelamento precisam postar wake-up para o loop compartilhado. | É a melhor base para um coordenador único que bombeia eventos uma vez, mantém participantes por janela e escolhe o contexto próprio antes de cada operação. Requer desenho e testes adicionais; não está implementado nem comprovado nesta história. |

### Despertar e trabalho quando a janela está ociosa

O loop atual é polling contínuo: consulta eventos, limpa, verifica redraw e faz
swap. `viewsNeedDisplay == false` desativa a closure e o flush, não o loop.
Uma implementação cooperativa futura precisa definir os seguintes sinais e
transições, em vez de aguardar indefinidamente sem um caminho de wake-up:

1. **Eventos:** aguardar eventos GLFW no loop compartilhado e processá-los no
   ator/contexto apropriado; eventos de teclado, mouse, resize e fechamento
   devem ser encaminhados à janela proprietária.
2. **Animação:** acordar no próximo deadline de frame enquanto existir uma
   animação ativa. Uma janela estática não deve manter um timer de animação.
   Espera temporizada pode limitar latência, mas seu intervalo é uma escolha
   observável de CPU versus responsividade.
3. **Redraw:** quando uma janela for invalidada, registrar que ela precisa de
   desenho e acordar o loop. A propriedade `viewsNeedDisplay` atual não oferece
   esse aviso. Sem novo mecanismo de invalidação ou wake-up, a alternativa é
   polling temporizado, não despertar imediato garantido.
4. **Encerramento:** o evento de fechamento acorda o loop, encerra somente a
   participação da janela correspondente e libera seus recursos com o contexto
   GL proprietário atual. Quando não houver mais janelas participantes, o
   coordenador termina.
5. **Cancelamento:** o cancelamento da tarefa acorda a espera e é verificado
   antes/depois de operações e frames. Deve encerrar a tarefa chamadora, não
   fechar a janela automaticamente. Uma janela ainda aberta precisa continuar
   recebendo eventos por outro participante/loop ou ter seu encerramento
   solicitado explicitamente; não pode ficar silenciosamente sem bombeamento.
6. **Repouso total:** sem animações ou redraws pendentes, aguardar eventos em
   vez de limpar e trocar buffers repetidamente. Redraw e cancelamento ainda
   precisam de wake-up; a medição da US-010 mostra que zero chamadas de desenho
   não basta para obter esse repouso no loop existente.

Esses itens são requisitos para projeto e validação da US-012, não afirmações
de que `glfwWaitEvents()` sozinho implementa esse contrato. A aplicação concreta
do wake-up a alterações de estado exige uma API ou mecanismo de notificação que
não existe hoje.

## Assinaturas e comportamento preservado

| Declaração | Estado nesta decisão |
|---|---|
| `open func makeKeyAndOrderFront(_ sender: Any? = nil)` | Sem alteração. Continua mostrando a janela e bloqueando sincronicamente até o fechamento; não há garantia de que tarefas do `MainActor` progridam enquanto a chamada está ativa. |
| `open func displayIfNeeded()` e `open var viewsNeedDisplay: Bool` | Sem alteração. O primeiro só desenha/flush quando a flag está ativa; mudar a flag não acorda uma espera. |
| `public func makeKeyAndOrderFrontAsync(_ sender: Any? = nil) async throws` | Exemplo de assinatura **proposta, não adicionada**. Exigiria autorização para nova API pública. Uma implementação teria de especificar `CancellationError`, wake-up, reuso após cancelamento e coordenação de janelas antes de estabilizar o contrato. |

Não se converte a função síncrona em `async`: isso mudaria uma declaração
existente e o comportamento de chamadas que hoje esperam o retorno após o
fechamento. Não se promete que manter a assinatura e apenas introduzir espera
de eventos permita outras tarefas Swift executarem; uma espera síncrona continua
ocupando a chamada isolada ao ator. Também não se promete que uma chamada
assíncrona aditiva substitua automaticamente os usos legados.

## Consequência para US-012

US-011 registra a decisão e o bloqueio; não conclui a implementação. A US-012
deve aguardar decisão explícita sobre a API pública (ou uma proposta alternativa
que demonstre cooperação, wake-up, cancelamento e múltiplas janelas sem violar
as regras). Depois da decisão, verificar com testes determinísticos de ator,
animação, evento, invalidação/redraw, cancelamento, fechamento e duas janelas;
medir novamente repouso e latência em ambiente gráfico e comparar com a
baseline. A baseline de uma única máquina não deve ser tratada como critério
universal de desempenho.

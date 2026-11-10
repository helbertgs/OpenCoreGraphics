# US-012 — Loop cooperativo de janela

## Decisão e contrato

O usuário autorizou **somente** a nova declaração pública aditiva
`makeKeyAndOrderFrontAsync(_:) async throws`. A API síncrona anterior não foi
alterada e continua bloqueante. A nova operação é isolada ao `MainActor`, mostra
a janela e suspende até o pedido de fechamento, erro ou cancelamento. Não
destrói nem fecha a janela ao cancelar; se nenhuma outra janela permanecer
participando, o chamador deve reiniciar o processamento ou fechar a janela por
seu mecanismo de plataforma. O fechamento retorna normalmente; a destruição
dos recursos continua vinculada ao ciclo de vida existente de `CGWindow`.

Um coordenador compartilhado faz `glfwPollEvents()` uma vez por rodada, visita
os participantes em ordem de inscrição, seleciona o contexto de cada janela e
cede entre participantes. Somente janelas com `viewsNeedDisplay == true` são
limpas, desenhadas e apresentadas. Mantenha a flag verdadeira para animação
contínua; para desenho estático, desligue-a após o frame e ligue-a para
invalidar. A flag não é apagada automaticamente, preservando sua semântica.

Como a propriedade existente não notifica alterações e uma espera GLFW
bloqueante ocuparia o ator, o coordenador suspende por 16 ms entre rodadas,
inclusive em repouso. Isso é polling temporizado cooperativo, **não** wake-up
imediato nem espera nativa por evento. A latência real também depende de
callbacks, agendamento, número de janelas e `glfwSwapBuffers`, que pode bloquear
no driver. O yield entre janelas oferece oportunidades de execução a outras
tarefas, mas não garante prazo ou ausência absoluta de starvation quando o
código do usuário, GLFW ou o driver bloqueiam.

Participação duplicada, janela indisponível, resize pendente com falha,
seleção de contexto e execução fora da thread principal geram erro; o
cancelamento gera `CancellationError`. Por não haver autorização para outra
declaração pública, os erros específicos do coordenador não são um enum
público que o cliente possa usar em um `switch` exaustivo. Erros silenciosos
internos de APIs legadas/driver GL não são todos convertidos em exceções.
Cancelamento e fechamento concorrentes podem ganhar a corrida em qualquer
ordem. A chamada síncrona ou outro loop GLFW simultâneo não é coordenado pela
nova API; não os misture.

GLFW exige chamadas na thread principal do sistema. O coordenador verifica
essa condição antes do processamento e depois de suspensões, falhando em vez de
executar GLFW em outra thread. Isso **não** torna `MainActor` equivalente à
thread principal em todos os runtimes: Linux e Windows ainda precisam de um host
que forneça o executor correto, e não foram executados nesta validação.

## Pré-requisito do host macOS

Para a integração standalone verificada, o host chama
`NSApplication.shared.run()` a partir de `main` síncrono, mantendo o loop
AppKit ativo; uma `Task { @MainActor in ... }` cria as janelas **depois** de o
loop estar ativo e chama a API assíncrona. O host decide quando parar o loop,
acordando-o se necessário. O framework não instala bootstrap nem altera o ciclo
de vida global. O exemplo executável completo é
[`WindowCooperativeProbe.swift`](../tools/WindowCooperative/WindowCooperativeProbe.swift);
o supervisor exige o marcador `host_running` antes de aceitar o relatório.

Em 10/11/2026, dez processos separados desta versão do exemplo completaram
com timeout externo, todos com duas janelas, eventos, animação, redraw,
cancelamento e fechamento. Uma investigação independente registrou 30/30
nesse modelo, mas essa contagem não foi reproduzida por esta execução.
O resultado aqui valida apenas esse host, máquina e sessão;
aplicações com outro ciclo de vida AppKit ou inicialização GLFW externa não
foram validadas.

## Limitação: primeira janela em `async main` puro no macOS

**Não corrigido.** O executável diagnóstico
`OpenCoreGraphicsWindowAsyncMain` cria duas `CGWindow` diretamente em
`@MainActor static func main() async throws`, sem bootstrap ou `NSApp.run`
fornecido pelo teste. Ele testa quadros, cancelamento sem fechar, continuidade da
outra janela, reinício e fechamento; o supervisor exige o resumo final. Esta
execução é diagnóstica e não compõe a validação do host suportado:

```sh
swift build --product OpenCoreGraphicsWindowAsyncMain
ruby scripts/run-window-cooperative.rb --async-main --timeout 15 -- .build/debug/OpenCoreGraphicsWindowAsyncMain
```

Em uma série de dez execuções, **8 saíram com código 0 sem resumo e 2
completaram**; em outra execução supervisionada ambos os primeiros frames
ocorreram antes da saída incompleta. O teste opt-in falhou corretamente por
ausência do resumo. Uma execução bem-sucedida não demonstra correção.

A investigação isolou o comportamento além do coordenador: com o mesmo
executável, `--initialization-only` cria uma janela pública e só aguarda um
timer, sem iniciar o coordenador; cinco execuções saíram antes do resumo. A
variante `--glfw-only --glfw-window` chama diretamente as dependências GLFW
existentes, sem `CGWindow` ou coordenador: cinco execuções também saíram antes
do resumo. Por contraste, cinco execuções de `--glfw-only` sem janela
terminaram o timer. Isso localiza o bloqueio na interação entre a inicialização
Cocoa/GLFW, criação da janela e o runtime de `async main`, não prova uma causa
única interna.

No LLDB, um breakpoint em `CFRunLoopStop` mostrou
`_glfwPostEmptyEventCocoa` → `NSEvent._postAtStart` → `CFRunLoopStop`, dentro de
`GLFWApplicationDelegate.applicationDidFinishLaunching`, chamado por
`NSApplication.run` durante `_glfwInitCocoa` (`cocoa_init.m:635`). Um breakpoint
em `libsystem_c.dylib` `exit` mostrou
`swift_task_asyncMainDrainQueue` → `_swift_exit` → `exit`, antes do resumo.
Essas observações identificam uma interação de run loop relevante; ainda não
demonstram precisamente por que criar uma janela ativa o encerramento. Chamar
`NSApplication.finishLaunching()` ou executar o run loop por 200 ms antes de
criar a janela não garantiu o estado `isFinishedLaunching` nem corrigiu a
reprodução. Não foi aplicada uma inicialização oculta, swizzle ou alteração da
dependência para mascarar a falha. Uma correção segura requer investigar uma
integração Cocoa/GLFW com o ciclo de vida do host e validar seus efeitos sobre
a API síncrona e outras plataformas.

Para reproduzir as observações de LLDB, com o executável já compilado:

```sh
lldb -b -o 'breakpoint set --name CFRunLoopStop' -o run -o 'thread backtrace' -- .build/debug/OpenCoreGraphicsWindowAsyncMain --glfw-only --glfw-window
lldb -b -o 'breakpoint set -s libsystem_c.dylib -n exit' -o run -o 'thread backtrace all' -- .build/debug/OpenCoreGraphicsWindowAsyncMain --glfw-only --glfw-window
```

O depurador altera o agendamento; é possível que uma execução alcance o resumo.
Os modos GLFW diretos são apenas controles diagnósticos; o modo padrão exercita
a API pública no host `async main` puro não suportado.

O caso público `--initialization-failure` passa uma largura zero, exige
`CGWindowError.windowCreationFailed` e aguarda antes do resumo. Cinco
execuções diretas e o teste opt-in completaram. Uma falha de inicialização não
prova que a janela válida funcione. Os dois casos de falha parcial de shader e
buffer também passaram com GL real e verificaram a restauração do contexto de
outra janela.

### Avaliação de hints e integração com o host

Em 10/11/2026, na mesma máquina e sessão gráfica, foram executados 12 processos
isolados por configuração do executável público. Todos usaram `async main`,
criaram duas janelas e exigiram o marcador `WINDOW_ASYNC_MAIN COMPLETE`,
incluindo cancelamento e fechamento. O processo foi encerrado pelo supervisor
após 10 s caso não retornasse. Os hints foram configurados na própria sonda
antes de qualquer inicialização GLFW, **não** no código de produção:

| Configuração | Com resumo | Saída zero sem resumo | Timeout |
|---|---:|---:|---:|
| Valores padrão | 0/12 | 12 | 0 |
| `GLFW_COCOA_MENUBAR = GLFW_FALSE` | 0/12 | 12 | 0 |
| `GLFW_COCOA_CHDIR_RESOURCES = GLFW_FALSE` | 0/12 | 12 | 0 |
| Ambos desativados | 1/12 | 11 | 0 |

Esses hints são documentados respectivamente para criação da barra de menu/ícone
e alteração do diretório de trabalho, não para controle do loop de eventos
([guia GLFW](https://www.glfw.org/docs/latest/intro_guide.html#init_hints)).
Na versão GLFW usada pelo pacote, `_glfwInitCocoa` ainda pode chamar
`[NSApp run]` independentemente deles. O resultado não justifica alterar os
defaults do host nem adotar qualquer uma dessas combinações.

Para repetir, compilado o produto acima, rode cada linha diversas vezes:

```sh
ruby scripts/run-window-cooperative.rb --async-main --timeout 15 -- .build/debug/OpenCoreGraphicsWindowAsyncMain
ruby scripts/run-window-cooperative.rb --async-main --timeout 15 -- .build/debug/OpenCoreGraphicsWindowAsyncMain --disable-menubar
ruby scripts/run-window-cooperative.rb --async-main --timeout 15 -- .build/debug/OpenCoreGraphicsWindowAsyncMain --disable-chdir
ruby scripts/run-window-cooperative.rb --async-main --timeout 15 -- .build/debug/OpenCoreGraphicsWindowAsyncMain --disable-menubar --disable-chdir
```

Como controle de empacotamento, o executável e seu bundle de recursos SwiftPM
foram copiados para um `.app` temporário com `Info.plist`, executado diretamente
como subprocesso: 4/10 chegaram ao resumo e 6/10 saíram zero sem ele. Isso
**não** testa lançamento pelo Launch Services nem representa todos os hosts
AppKit; somente mostra que esse empacotamento direto não resolve o caso. O
controle já existente de `main` síncrono, criação de janelas seguida por
`NSApp.run`, completou 5/5 processos supervisionados. Esse controle é uma
versão anterior da sonda; a versão atual cria as janelas numa tarefa após
o loop estar ativo. Nenhuma delas corrige o uso de `async main` puro ou
garante integração com outro host.

Não foi encontrada uma opção de inicialização GLFW que corrija este uso com a
evidência disponível. Continuam sem validação: hosts com ciclo de vida AppKit
pré-existente, execução via Launch Services, Linux e Windows. Sem demonstrar
compatibilidade com esses hosts e com o método síncrono existente, o framework
não deve instalar ou parar um loop AppKit global por conta própria. Não houve
alteração na dependência, init hints de produção ou bootstrap oculto.

## Reprodução e testes

Em macOS com sessão gráfica ativa:

```sh
swift test -Xswiftc -strict-concurrency=complete --filter WindowLoopCoordinatorTests
swift test -Xswiftc -strict-concurrency=complete --filter WindowCooperativeRunnerTests
ruby scripts/run-window-cooperative.rb --timeout 60
OPENCOREGRAPHICS_RUN_WINDOW_COOPERATIVE=1 swift test --filter WindowCooperativeRunnerTests.graphicalProbeCompletes
ruby scripts/run-window-cooperative.rb --async-main --initialization-failure --timeout 15 -- .build/debug/OpenCoreGraphicsWindowAsyncMain --initialization-failure
```

O supervisor usa timeout de processo externo e exige métricas, eventos e
marcador final. Timeout ou saída zero sem relatório são falhas/incompletos.
Os testes do coordenador injetam eventos e suspensão controlados: verificam
duas janelas, ordenação, duplicidade, cancelamento idempotente, fechamento e
isolamento de falha. Os testes do supervisor verificam timeout, saída
incompleta, erro e evento ausente. A sonda gráfica verifica tarefa `MainActor`,
animação, repouso, redraw, 20 eventos, rejeição de duplicidade, cancelamento sem
fechamento, cancelamento anterior ao registro, reinício e operação/fechamento
independente de duas janelas.

## Medição observada

Em 10/11/2026, macOS 26.6.2 (25G83), Apple M3 Pro, Swift 6.4.2,
debug, duas janelas 240 × 180, sessão gráfica ativa. CPU é usuário+sistema
do processo inteiro. A referência publicada na US-010 usa uma janela no
loop síncrono e outra mostrada sem loop; a nova sonda registra as duas.

| Medida | Baseline US-010 | Cooperativo |
|---|---:|---:|
| Repouso | 1,999560 s | 2,010762 s |
| CPU do processo / % de um núcleo | 0,090804 s / 4,5412% | 0,046090 s / 2,2922% |
| Desenhos em repouso | 0 | 0 em cada janela |
| Eventos sintéticos recebidos | 20/20 | 20/20 |
| Pedido de fechamento até retorno | 102,704 ms | 104,411 ms |
| Desenho da segunda janela | 0 automático | 5 frames no experimento, incluindo após fechar a primeira |

Na versão atual do host suportado, dez processos supervisionados produziram
mediana de CPU de **2,4232% de um núcleo** durante aproximadamente 2 s de
repouso. As medianas de latência por execução variaram de 0,0551 a 0,0841 ms,
com mediana das medianas de 0,0658 ms; o fechamento teve mediana de 104,272 ms.
Uma nova execução da baseline síncrona, na mesma máquina e em outro processo,
registrou CPU de 4,2280%, latência mediana de 16,5232 ms e fechamento de
104,244 ms. Estes valores coexistem com a baseline original acima; nenhuma
diferença é prova de ganho ou regressão.

O fechamento observado foi cerca de 1,7 ms maior; uma amostra não estabelece
regressão estatística. A redução aparente de CPU também não é uma comparação
controlada: há número diferente de loops/janelas, diferenças de execução e
carga não controlada. **Não há comparação válida de latência de eventos nem conclusão de regressão ou
melhoria.** As medições isoladas foram mediana de 16,515 ms na baseline e
0,0631 ms na sonda cooperativa, mas a nova sonda mantém `NSApp.run()` ativo,
que pode despachar o evento antes de `glfwPollEvents`; a baseline usou o loop
GLFW síncrono. Não foi estabelecido um caminho equivalente de eventos.
Nenhuma das duas mede
teclado físico, apresentação de pixels ou FPS. A sonda prova a sequência de
callbacks observada, não correção visual nem ausência de congelamento sob
carga arbitrária. Não há dados de CPU, latência ou thread GLFW para Linux e
Windows.

## Estado dos critérios

No host macOS descrito, a sonda externa observou progresso de uma tarefa do
`MainActor` com as janelas abertas, animação, evento, redraw, fechamento,
cancelamento e duas janelas; o supervisor e testes determinísticos passaram.
O caminho síncrono existente também retornou com relatório completo.
O comparativo numérico foi registrado, mas **latência não é comparável** e CPU
não é um experimento controlado. A aceitação do pré-requisito do host não
comprova operação no `async main` puro, em hosts AppKit diferentes, Linux ou
Windows, nem estabelece limite de latência ou ausência absoluta de starvation
em callbacks e operações de driver bloqueantes. A integração suporta os
cenários observados no host explícito; não se declara uma garantia
multiplataforma ou desempenho equivalente ainda não testados. Não alteramos o
PRD nem marcamos a história automaticamente.

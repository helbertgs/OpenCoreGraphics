# Baseline do loop síncrono de janela — US-010

## Reprodução

Em uma sessão gráfica macOS desbloqueada, na raiz do repositório:

```sh
ruby scripts/run-window-baseline.rb --timeout 60
```

O supervisor compila e executa `OpenCoreGraphicsWindowBaseline` em um processo
separado. O prazo inclui a compilação. Se expirar, o grupo de processos é
terminado e o resultado é **incompleto**, não uma aprovação. A execução deve
terminar com `WINDOW_BASELINE COMPLETE` e `WINDOW_BASELINE RUNNER: PASSED`.
Ela não integra `swift test` e não altera o loop da biblioteca. O executável
específico usa AppKit; outras plataformas não têm medição implementada.

Para verificar o timeout sobre o executável já compilado:

```sh
ruby scripts/run-window-baseline.rb --timeout 1 -- .build/debug/OpenCoreGraphicsWindowBaseline
```

Nesta máquina o processo entrou no loop e foi encerrado pelo supervisor,
com `TIMEOUT` e código 1. O prazo de um segundo não é uma medição completa.
`swift test --filter WindowBaselineRunnerTests` testa isoladamente o
supervisor, sem abrir janelas.

## Ambiente e resultado observado

Execução de 10/11/2026, macOS 26.6.2 (25G83), Apple M3 Pro,
11 CPUs lógicas, GPU integrada M3 Pro, tela interna ativa 3024 × 1964 Retina,
Swift 6.4.2, build debug. Dois `CGWindow` de 240 × 180 foram criados.
O primeiro executou `makeKeyAndOrderFront`; o segundo foi mostrado via
`NSWindow.orderFront` para observação, sem iniciar um segundo loop.
Não houve controle das demais aplicações, energia, composição ou frequência
de atualização do monitor.

| Métrica | Valor da execução completa |
|---|---:|
| Repouso: duração medida | 1,999560 s |
| CPU do processo: usuário + sistema durante repouso | 0,090804 s |
| CPU média: tempo de CPU / tempo decorrido × 100 | 4,5412% de um núcleo |
| Iterações do loop durante repouso | 121 |
| Eventos de teclado AppKit postados / recebidos pelo `sendEvent` | 20 / 20 |
| Latência evento: mínimo / mediana / média / máximo | 4,897 / 16,515 / 16,030 / 17,998 ms |
| Chamadas de desenho animado, total | 146 |
| Chamadas de desenho no intervalo de repouso | 0 |
| Chamadas automáticas de `display` da segunda janela | 0 |
| Chamadas da segunda janela após `displayIfNeeded()` explícito | 1 |
| Tarefa agendada no `MainActor` após a primeira iteração | executou antes do retorno |
| Pedido de fechamento AppKit até retorno do método | 102,704 ms |

As amostras de latência em ms, na ordem: 16,882584; 4,897125;
17,998083; 16,710583; 16,406625; 16,576166; 16,253083; 16,831334;
16,361541; 16,699333; 16,471125; 16,405958; 16,590625; 16,451084;
16,606708; 16,585334; 16,484125; 16,376750; 16,475000; 16,546500.

Uma execução anterior completa, na mesma sessão, registrou 4,8255% de um
núcleo, 120 iterações de repouso, 20/20 eventos, progresso da tarefa durante
o loop e 102,664 ms entre pedido de fechamento e retorno. Ela não substitui
uma amostra representativa entre máquinas.

## O que foi medido

Após aquecimento de 0,5 s, `viewsNeedDisplay` é desativado por cerca de 2 s.
`getrusage(RUSAGE_SELF)` fornece CPU de **todo o processo**, não apenas da
thread de janela; o relógio monotônico fornece a duração. Mesmo sem `display`,
o loop continua chamando polling, clear e swap. O percentual pode exceder
100% se várias threads consumirem mais de um núcleo.

Depois, `viewsNeedDisplay` volta a `true` e a closure alterna a cor de um
retângulo a cada chamada. Os contadores mostram que o desenho foi solicitado,
não comprovam FPS apresentado, aparência, ausência de flicker ou pixels na
tela. No repouso o loop ainda limpa e troca buffers; zero chamadas de `display`
não equivale a preservar a imagem.

O teste posta eventos `NSEvent.keyDown` sintéticos na fila do AppKit para a
janela A. A latência mede o relógio monotônico imediatamente antes de
`postEvent` até a entrada em `CGWindow.sendEvent`, passando pelo polling
GLFW e seu callback. Não mede teclado físico, latência fim a fim percebida,
apresentação do quadro nem outros tipos de evento. Os 20 eventos são enviados
sequencialmente, somente após receber o anterior. Filas, composição, carga e
agendamento afetam o resultado.

A tarefa do `MainActor` é criada dentro da primeira chamada de
`displayIfNeeded`, portanto já no loop, e registra se executou antes do
retorno. Nesta execução progrediu; isso não prova cooperação geral nem
frequência de progresso. O processamento de eventos AppKit pode reentrar o
executor principal. Em uma tentativa preliminar com Swift Testing e seu
bootstrap AppKit, o helper terminou sem resumo final após o loop; essa tentativa
é inconclusiva e não foi contada como teste aprovado.

O fechamento usa `NSWindow.performClose`, e o tempo começa antes dessa chamada
e termina quando `makeKeyAndOrderFront` retorna. Não é latência de clique
físico, e o custo da própria chamada está incluído. A segunda janela permanece
sem `display` automático enquanto o primeiro loop roda; a chamada manual
posterior confirma apenas que sua closure pode ser invocada. Isso não
comprova operação simultânea de dois loops públicos, interação visual ou
fechamento independente.

Estes valores são uma única observação nesta máquina, não metas ou garantias
para outros Macs, Linux ou Windows. Repetir em máquinas e cargas distintas
antes de comparar uma futura implementação cooperativa.

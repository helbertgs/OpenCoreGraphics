# Progress Log — Evolução da renderização, concorrência e qualidade

## Codebase Patterns

- O executor `ruby scripts/run-gl-tests.rb` exige os resultados individuais e o resumo final das duas suítes GL; código zero sem resumo ou teste ignorado não é sucesso.
- Execuções GL nesta sessão iniciaram ambas as suítes, mas o processo terminou sem resumo Swift Testing. Reproduzir com o executor antes de atribuir a causa ao renderer.
- Os testes do executor usam processos Ruby controlados e não precisam de GPU; a suíte roda em macOS/Linux.
- Em macOS, o target de bootstrap exclusivo dos testes inicializa AppKit antes do async main apenas no modo GL opt-in; deixar o GLFW iniciar o loop dentro do Swift Testing pode encerrar o executor sem resumo.
- O resumo de falha do Swift Testing pode terminar em `with N issues`; isso é uma execução concluída com falha, não uma saída incompleta.
- A comparação GL/software usa bitmap sRGB opaco: converta RGB linear do framebuffer GL para sRGB somente quando os bytes armazenados ainda forem lineares; rejeite alpha não opaco até existir conversão pré-multiplicada adequada.

---

## 2026-11-10 - US-001
- Implementado executor GL local com timeout configurável, encerramento do grupo de processos, classificação de falha/saída incompleta e diagnóstico distinto para contexto gráfico indisponível.
- As duas suítes GL registram falhas de inicialização de janela sem ocultar o erro; documentação no README descreve execução, requisitos e códigos de saída.
- Testes: `swift test --filter GLTestRunnerTests` (8 testes), `swift test -Xswiftc -strict-concurrency=complete` (175 testes), `swift build -Xswiftc -strict-concurrency=complete` e `ruby -c scripts/run-gl-tests.rb` passaram. SwiftLint não estava disponível.
- Execução real `ruby scripts/run-gl-tests.rb --timeout 20` retornou 1 e `INCOMPLETE`: ambas as suítes iniciaram, mas não produziram resultado final.
- Files changed: `scripts/run-gl-tests.rb`, `Tests/OpenCoreGraphicsTests/Rendering/GLTestRunnerTests.swift`, `Tests/OpenCoreGraphicsTests/Rendering/GLSoftwareComparisonTests.swift`, `Tests/OpenCoreGraphicsTests/Rendering/GLGlyphComparisonTests.swift`, `README.md`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`.
- **Learnings for future iterations:**
  - O resumo XCTest de zero testes não comprova conclusão das suítes Swift Testing. Exigir os nomes dos testes e o resumo do Swift Testing.
  - A classificação de contexto indisponível exige falhas identificadas de inicialização; não transformar falha visual ou saída incompleta em indisponibilidade.
---

## 2026-11-10 - US-002 (bloqueada; não concluída)
- O executor da US-001 iniciou ambas as suítes GL com `--timeout 40`, mas retornou `INCOMPLETE`: o processo terminou sem resultados individuais nem resumo final.
- Executando a comparação de cenas separadamente, cinco cenas registraram diferenças acima da tolerância; o processo novamente terminou sem resumo e `swift test` retornou zero. A comparação de glifos também terminou sem resumo e com código zero.
- No LLDB, um breakpoint em `libsystem_c.dylib` `exit` mostrou `_swift_exit` chamado de `swift_task_asyncMainDrainQueue` no processo `swiftpm-testing-helper`, sem conclusão registrada do Swift Testing. Isso identifica o encerramento, mas não demonstra sua causa.
- Uma tentativa de inicializar `NSApplication` com `finishLaunching()` antes de criar a janela não resolveu; foi removida. Em uma verificação separada, `NSRunningApplication.current.isFinishedLaunching` permaneceu `false` após essa chamada.
- Ainda falta produzir metadados e artefatos por cenário e conseguir uma execução GL com resultado final inequívoco; não marcar US-002 como concluída nem avançar suas dependentes sem essa validação.
---

## 2026-11-10 - US-002 (continuação; em andamento)
- Adicionados relatórios JSON por cenário e buffers RGBA brutos nas divergências, em diretório único por execução; testes de escrita e validação de dados não exigem GPU.
- A execução real gerou sete relatórios e dez buffers de cinco cenas divergentes, mas continuou sem resumo final; o executor classificou `INCOMPLETE` e retornou falha.
- O framebuffer da sessão foi registrado como linear, 128×128, MSAA 4, Apple M3 Pro. A análise dos buffers sugere diferença de espaço de cor: converter matematicamente RGB linear GL para sRGB reduziu a diferença média das cinco cenas abaixo das tolerâncias existentes. Ainda é necessário verificar e corrigir a comparação na US-003, sem assumir que toda divergência tem a mesma causa.
- `swift test -Xswiftc -strict-concurrency=complete` passou com 179 testes; os testes específicos do relatório e executor passaram. A US-002 permanece pendente até haver encerramento real conclusivo.
---

## 2026-11-10 - US-002
- Relatórios por cenário registram sistema, driver GL, framebuffer, viewport, estado de cor e MSAA, tolerância e diferença; cenas com falha salvam ambos os buffers RGBA em diretórios únicos. Falhas de metadados e escrita são explícitas.
- Um bootstrap AppKit exclusivo do target de testes inicializa o aplicativo antes do async main, somente com GL opt-in. Corrigido o reconhecimento de resumos Swift Testing com contagem de issues e adicionada classificação explícita de testes ignorados.
- `ruby scripts/run-gl-tests.rb --timeout 40` concluiu com resumo verificável de duas suítes: uma passou e outra falhou com cinco issues; o executor retornou 1 e classificou `FAILED`, sem apresentar a falha como sucesso.
- `swift test -Xswiftc -strict-concurrency=complete` passou com 180 testes; 13 testes direcionados ao relatório e executor passaram; `swift build -Xswiftc -strict-concurrency=complete`, `ruby -c` e `git diff --check` passaram. SwiftLint não estava disponível.
- Files changed: `Package.swift`, `Tests/OpenCoreGraphicsGLTestBootstrap/`, `Tests/OpenCoreGraphicsTests/Rendering/GLComparisonReport.swift`, `GLComparisonReportTests.swift`, `GLTestRunnerTests.swift`, `GLSoftwareComparisonTests.swift`, `GLGlyphComparisonTests.swift`, `scripts/run-gl-tests.rb`, `README.md`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`.
- **Learnings for future iterations:**
  - O loop AppKit iniciado por GLFW dentro do async main interrompia o executor; inicializar AppKit antes de o helper entrar no async main permitiu a emissão do resumo.
  - Framebuffer linear e bitmap sRGB explicam uma parte observada das diferenças; US-003 deve validar a normalização, o readback e a cobertura visual sem elevar tolerâncias.
---

## 2026-11-10 - US-003
- Diagnosticada a comparação de cinco cenas: o framebuffer GL era linear enquanto o bitmap usava sRGB. As comparações agora normalizam os pixels opacos para sRGB usando `CGColor.converted(to:)`, sem mudar tolerâncias.
- Verificado o contexto atual antes de desenhar e ler, tamanho e viewport reais, presença de pixels coloridos e estabilidade do readback antes/depois de `glFinish`. Registrados ambiente, métricas e limitações em `.docs/GLComparisonDiagnostics.md`.
- `ruby scripts/run-gl-tests.rb --timeout 40`: duas suítes GL passaram com resumo conclusivo e todas as sete cenas dentro dos limites; `swift test -Xswiftc -strict-concurrency=complete`: 183 testes passaram; `swift build -Xswiftc -strict-concurrency=complete` e `git diff --check` passaram.
- Files changed: `.docs/GLComparisonDiagnostics.md`, `README.md`, `Tests/OpenCoreGraphicsTests/Rendering/GLComparisonPixels.swift`, `GLComparisonPixelsTests.swift`, `GLComparisonReport.swift`, `GLGlyphComparisonTests.swift`, `GLSoftwareComparisonTests.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`.
- **Learnings for future iterations:**
  - Nesta máquina a comparação usa framebuffer 128×128 linear com MSAA 4; corrija a comparação de espaço de cor, não o limite de erro.
  - Não extrapolar o resultado para múltiplas janelas, alpha parcial ou outros drivers; essas situações exigem testes próprios.
---

## 2026-11-10 - US-004
- Seletor de contexto GLFW por janela com driver injetável, seleção verificada e erros registrados; a seleção normal mantém o contexto selecionado atual.
- Destinos retidos recusam operações após encerramento. O teardown remove callbacks, seleciona o contexto proprietário antes de liberar recursos e restaura o contexto anterior; falhas retêm recursos para tentativa posterior em eventos de ciclo de vida.
- Testes cobrem alternância, falhas, fechamento, inicialização malsucedida e ordem de liberação, incluindo GLFW real e contexto B atual. Seleção para desenho e callbacks de janelas abertas permanece para US-005 e US-006; falha permanente de seleção conserva recursos pendentes.
- Validação: 192 testes na suíte padrão; build e testes com concorrência estrita; testes de ciclo de vida com GL real; `ruby scripts/run-gl-tests.rb --timeout 90` passou com resumo conclusivo e sete cenas dentro das tolerâncias; `git diff --check` passou. SwiftLint não estava disponível.
- Files changed: `Sources/OpenCoreGraphics/Services/Window Services/CGWindow.swift`, `GLFWContextSelector.swift`, `GLFWWindowTeardown.swift`, `Sources/OpenCoreGraphics/Rendering/GL/WindowRenderTarget.swift`, testes correspondentes, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`.
- **Learnings for future iterations:**
  - O teardown deve transferir todas as referências fortes ao renderer antes de liberar recursos; verificar a desalocação efetiva antes de destruir o contexto.
  - Teardowns adiados precisam remover callbacks e user pointer antes de desalocar a janela Swift e manter a plataforma retida até a liberação.
---

## 2026-11-10 - US-005
- Seleção verificada do contexto proprietário precede clear, desenho, apresentação de superfície, readback e troca de buffers; erros impedem a operação.
- Fila preserva comandos e mudanças de clip na ordem após falhas temporárias de seleção; resize reaplica regiões ativas.
- Testes com drivers falsos cobrem alternância, ordem e falhas; duas janelas reais conservam cores distintas ao desenhar e alternar readbacks.
- Validação: 198 testes na suíte padrão com concorrência estrita; testes GL reais direcionados; build estrito; `ruby scripts/run-gl-tests.rb --timeout 90` com duas suítes concluídas e sete cenas aprovadas; `git diff --check` passou. Suítes GL são opt-in na execução padrão.
- Files changed: `Sources/OpenCoreGraphics/Rendering/GL/WindowRenderTarget.swift`, `Sources/OpenCoreGraphics/Services/Window Services/CGWindow.swift`, `Tests/OpenCoreGraphicsTests/Rendering/WindowRenderTargetTests.swift`, `GLFWWindowLifecycleTests.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`.
- **Learnings for future iterations:**
  - Quando a seleção falha, alterações de clip precisam permanecer ordenadas junto aos desenhos pendentes; aplicar apenas o último clip reordena operações.
---

## 2026-11-10 - US-006
- Resize usa o contexto da janela proprietária, mantém barreiras ordenadas para comandos anteriores e posteriores e tenta novamente operações pendentes após falha de seleção.
- Dimensões e cobertura do clip do CGContext são reconstruídas, inclusive ao restaurar estados salvos; falhas detectáveis de cobertura são registradas e impedem desenho fora do clip.
- Driver falso verifica ordem, contexto e recuperação; GL real valida resize de A com B atual, viewport, clip e pixels de B preservados.
- Validação: 207 testes na suíte padrão com concorrência estrita; 3 testes de ciclo de vida GL reais; build estrito; executor GL com duas suítes concluídas e sete cenas aprovadas; `git diff --check` passou. A suíte padrão ignora casos gráficos opt-in.
- Files changed: `Sources/OpenCoreGraphics/2D Drawing/CGContext.swift`, `Sources/OpenCoreGraphics/Rendering/GL/WindowRenderTarget.swift`, `Sources/OpenCoreGraphics/Rendering/SoftwareRenderer.swift`, `CGClipCoverageError.swift`, `Sources/OpenCoreGraphics/Services/Window Services/CGWindow.swift`, `GLFWFramebufferResize.swift`, testes correspondentes e arquivos de progresso.
- **Learnings for future iterations:**
  - Após um resize físico, guardar dimensões e barreiras pendentes permite retomar no próximo desenho ou readback sem esperar outro callback.
---

## 2026-11-10 - US-007
- O teardown desassocia o programa ativo, libera recursos no contexto proprietário antes de destruir a janela e retoma restaurações falhas sem repetir liberações.
- Testes falsos e GL real cobrem ambas as ordens A/B, recursos, desalocação e inicialização parcial em `CGWindow`, inclusive contexto anterior e retentativas pendentes.
- Uma exceção AppKit intermitente foi reproduzida; após separar chamada GLFW da macro de teste, 40 execuções combinadas passaram. Essa evidência é limitada ao ambiente observado.
- Validação: 216 testes na suíte padrão com concorrência estrita; 9 testes direcionados de teardown e falha de inicialização com GL real; build estrito; executor GL concluiu duas suítes com sete cenas aprovadas; `git diff --check` passou. Casos gráficos são opt-in na suíte padrão.
- Files changed: `Sources/OpenCoreGraphics/Services/Window Services/CGWindow.swift`, `GLFWWindowTeardown.swift`, testes de inicialização e teardown em `Tests/OpenCoreGraphicsTests/`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`.
- **Learnings for future iterations:**
  - Retentativas de teardown não devem restaurar um contexto anterior obsoleto ou destruir um contexto aguardando restauração.
---

## 2026-11-10 - US-008
- Separado contrato interno de backend de janela, isolado ao MainActor, do backend síncrono de bitmap. A ponte pública síncrona preexistente continua exigindo execução no MainActor em runtime, sem simular troca de executor; limitação documentada.
- Snapshots de imagens copiam também armazenamento externo; testes verificam isolamento dos dados, Sendable e backend de bitmap fora do MainActor.
- Validação: 219 testes na suíte padrão com concorrência estrita; build estrito; testes direcionados e verificação de isolamento em typecheck; executor GL com duas suítes concluídas e sete cenas aprovadas; `git diff --check` passou. A suíte padrão ignora casos gráficos opt-in.
- Files changed: `.docs/RenderingConcurrency.md`, `Sources/OpenCoreGraphics/2D Drawing/CGImage.swift`, `Sources/OpenCoreGraphics/Rendering/CGRenderTarget.swift`, `Sources/OpenCoreGraphics/Rendering/GL/GLRenderer.swift`, `WindowRenderTarget.swift`, testes correspondentes e arquivos de progresso.
- **Learnings for future iterations:**
  - `Data` construído sem cópia pode apontar para memória externa mutável; snapshots transferíveis precisam adquirir bytes próprios.
---

## 2026-11-10 - US-009
- Duas tarefas estruturadas criam bitmaps independentes fora do MainActor e verificam pixels determinísticos sem compartilhar contextos mutáveis.
- Testes exercitam janela no MainActor e precondições da ponte legada em subprocessos; documentada a distinção entre verificação em runtime e isolamento estático.
- Validação: 223 testes na suíte padrão com concorrência estrita; testes direcionados, build estrito e comparações GL opt-in concluídas; `git diff --check` passou. Testes de saída são desabilitados na execução GL opt-in e não foram validados em Windows/Linux.
- Files changed: `.docs/RenderingConcurrency.md`, `Tests/OpenCoreGraphicsTests/Rendering/RenderingConcurrencyTests.swift`, `WindowRenderTargetTests.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`.
- **Learnings for future iterations:**
  - Testes de saída isolam precondições fatais da ponte legada; não são evidência de garantia estática.
---

## 2026-11-10 - US-010
- Criado experimento gráfico macOS supervisionado por timeout, com procedimento, ambiente e limitações em `.docs/WindowLoopBaseline.md`.
- Na reprodução adicional: 4,5401% de um núcleo em repouso, 20/20 eventos sintéticos, tarefa MainActor progrediu durante o loop, 0 desenhos em repouso e 102,940 ms entre pedido de fechamento e retorno. Outra janela exigiu redraw explícito.
- Validação: experimento concluiu com resumo; testes do supervisor; 227 testes na suíte padrão com concorrência estrita; build estrito; `git diff --check` passou. A medição não comprova comportamento em Linux/Windows nem latência de entrada física.
- Files changed: `Package.swift`, `tools/WindowBaseline/`, `scripts/run-window-baseline.rb`, `Tests/OpenCoreGraphicsTests/Rendering/WindowBaselineRunnerTests.swift`, `.docs/WindowLoopBaseline.md`, arquivos de progresso.
- **Learnings for future iterations:**
  - O loop observado permite progresso de tarefa MainActor no macOS, mas não prova cooperação geral nem operação automática de múltiplas janelas.
---

## 2026-11-10 - US-011
- Comparadas alternativas de loop integrado, atualização incremental e API assíncrona aditiva, com isolamento, compatibilidade, cancelamento, despertar e múltiplas janelas.
- `.docs/WindowLoopStrategy.md` registra a API assíncrona aditiva como direção preferida, sujeita à decisão específica exigida para uma nova declaração pública. A API síncrona existente permanece inalterada.
- US-012 não está implementada: a cooperação garantida não foi demonstrada sob as restrições atuais de API. É necessária decisão antes de prosseguir.
- Validação: 227 testes na suíte padrão com concorrência estrita; build estrito e `git diff --check` passaram. Casos GL opt-in foram ignorados na execução padrão.
- Files changed: `.docs/WindowLoopStrategy.md`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`.
- **Learnings for future iterations:**
  - Polling ou espera síncrona no MainActor não constitui ponto de suspensão Swift; preservar a API legada não garante cooperação.
---

## 2026-11-10 - US-012
- Implementada API assíncrona aditiva autorizada e coordenador compartilhado para eventos, redraw, animação, cancelamento e múltiplas janelas, sem alterar a API síncrona.
- Testes determinísticos e execução gráfica supervisionada comprovam progresso de tarefa MainActor e comportamento de duas janelas no host AppKit documentado. O caminho `async main` puro apresenta encerramento prematuro intermitente no macOS e continua não suportado; não há alegação de validação em Linux/Windows.
- Comparadas medições de CPU e latência com a baseline em `.docs/WindowLoopCooperative.md`; as cargas e caminhos de eventos diferem, impossibilitando concluir ganho ou regressão. Nova reprodução: 2,193% de um núcleo, 20/20 eventos e conclusão das duas janelas.
- Validação: 239 testes na suíte padrão com concorrência estrita; build estrito; sonda cooperativa supervisionada; testes GL reais separados; `git diff --check` passou. Testes gráficos são opt-in na suíte padrão.
- Files changed: `.docs/WindowLoopCooperative.md`, `.docs/WindowLoopStrategy.md`, `README.md`, `Package.swift`, `Sources/OpenCoreGraphics/Services/Window Services/CGWindow.swift`, `WindowLoopTestHandle.swift`, testes, scripts, ferramentas e arquivos de progresso.
- **Learnings for future iterations:**
  - No macOS testado, o host síncrono deve manter `NSApplication.run()` ativo antes de criar janelas em tarefas; `async main` puro não é equivalente e pode terminar sem resumo.
---

## 2026-11-10 - US-013
- Especificada orientação stb, atlas, baseline, quad e UV, com máscara assimétrica 2×3 e posições exatas acima e abaixo da baseline; definidos casos de transformação e espaçamento.
- Comparação GL real existente passou com diferença zero, mas o fixture rasteriza máscaras uniformes e não permite decidir orientação; nenhuma correção de backend foi presumida.
- Validação: build e suíte padrão com 239 testes; comparação de glifos em GL real; `git diff --check` passou. A comprovação com máscara assimétrica permanece nas US-014/015.
- Files changed: `.docs/GlyphOrientation.md`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`.
- **Learnings for future iterations:**
  - Média global e glifos uniformes não detectam inversão vertical; conferir coordenadas e valores localizados de máscara assimétrica.
---

## 2026-11-10 - US-014
- Corrigidas orientação vertical e normalização de cobertura parcial de máscaras de glifos no renderer software, conforme a convenção documentada.
- Testes sintéticos verificam pixels exatos acima e abaixo da baseline, transformações, espaçamento, rotações, reflexões e clipping.
- Validação: 247 testes na suíte padrão com concorrência estrita; build estrito; executor GL concluiu duas suítes com sete cenas aprovadas; `git diff --check` passou. A comparação GL assimétrica permanece na US-015.
- Files changed: `Sources/OpenCoreGraphics/Rendering/SoftwareRenderer.swift`, `Tests/OpenCoreGraphicsTests/Rendering/SoftwareGlyphOrientationTests.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`.
- **Learnings for future iterations:**
  - A cobertura do glifo e do clip são bytes independentes; ambos devem ser normalizados antes da composição.
---

## 2026-11-10 - US-015
- Verificadas geometria e UV dos glifos assimétricos e comparação GL/software por pixels localizados para baseline, rotação, reflexões, transformações e espaçamento.
- Runner exige métricas locais e testes negativos que impedem média global ou dois backends igualmente errados de mascarar falha. Máxima diferença observada foi 1/255, com tolerância 4/255; sem correção adicional de backend.
- Validação: 257 testes na suíte padrão com concorrência estrita; build estrito; runner GL concluiu 5 testes em 3 suítes com cenas e métricas aprovadas; `git diff --check` passou. GL real testado em macOS, fundo opaco e MSAA desativado nas cenas sintéticas.
- Files changed: `.docs/GlyphOrientation.md`, testes e relatórios GL em `Tests/OpenCoreGraphicsTests/Rendering/`, `scripts/run-gl-tests.rb`, arquivos de progresso.
- **Learnings for future iterations:**
  - Comparar ambos os backends com referência localizada independente evita que concordem em um resultado errado.
---

## 2026-11-10 - US-016
- Estados gráficos salvos retêm a fonte carregada e seus dados nativos, sem reabrir arquivo ao restaurar; o snapshot transferível permanece Sendable e a referência à fonte fica confinada ao contexto.
- Testes com cópias temporárias comparam pixels após sobrescrita ou remoção e cobrem três níveis, tamanhos, ausência de fonte e restaurações repetidas.
- Validação: 259 testes na suíte padrão com concorrência estrita; testes direcionados e build estrito; `git diff --check` passou. GL opt-in não foi executado nesta história.
- Files changed: `Sources/OpenCoreGraphics/2D Drawing/CGContext.swift`, `Tests/OpenCoreGraphicsTests/2D Drawing/CGContextTests.swift`, arquivos de progresso.
- **Learnings for future iterations:**
  - O snapshot Sendable não pode substituir o proprietário nativo de uma fonte; a pilha confinada deve manter o objeto vivo.
---

## 2026-11-10 - US-017
- Cache de texturas compara snapshots imutáveis completos por identidade e atualiza somente conteúdo alterado; preserva ordem dos lotes e não envia novamente dados inalterados.
- Testes falsos cobrem mutações e uploads; GL real compara software antes, depois e com versões enfileiradas, com diferença média zero.
- Validação: 264 testes na suíte padrão com concorrência estrita; build estrito; runner GL concluiu 5 testes em 3 suítes com cenas aprovadas; `git diff --check` passou. Cópia e comparação custam O(n); orçamento fica para US-018.
- Files changed: `.docs/RenderingConcurrency.md`, `Sources/OpenCoreGraphics/Rendering/GL/GLTextureCache.swift`, testes GL e cache, `scripts/run-gl-tests.rb`, arquivos de progresso.
- **Learnings for future iterations:**
  - Memória externa precisa permanecer válida e não ser mutada durante a captura; comparar conteúdo evita textura obsoleta sem confiar apenas na identidade.
---

## 2026-11-10 - US-018
- Cache de imagens possui orçamento interno configurável, padrão 64 MiB, eviction LRU e descarte de entradas maiores que o limite após uso; lotes são descarregados antes de alterar ou remover texturas.
- Testes falsos verificam reutilização, ordem, orçamento e liberação; teste GL real verifica eviction no contexto proprietário.
- Validação: 272 testes na suíte padrão com concorrência estrita; testes direcionados, build estrito e runner GL conclusivo; `git diff --check` passou. A contagem estima bytes lógicos GPU e snapshots, não memória física do driver ou referências externas.
- Files changed: `Sources/OpenCoreGraphics/Rendering/GL/GLTextureCache.swift`, `GLRenderer.swift`, testes de cache e teardown, arquivos de progresso.
- **Learnings for future iterations:**
  - Flush antes de mutação ou descarte impede que um lote pendente referencie textura alterada ou liberada.
---

# Progress Log — Evolução da renderização, concorrência e qualidade

## Codebase Patterns

- O executor `ruby scripts/run-gl-tests.rb` exige os resultados individuais e o resumo final das duas suítes GL; código zero sem resumo ou teste ignorado não é sucesso.
- Execuções GL nesta sessão iniciaram ambas as suítes, mas o processo terminou sem resumo Swift Testing. Reproduzir com o executor antes de atribuir a causa ao renderer.
- Os testes do executor usam processos Ruby controlados e não precisam de GPU; a suíte roda em macOS/Linux.
- Em macOS, o target de bootstrap exclusivo dos testes inicializa AppKit antes do async main apenas no modo GL opt-in; deixar o GLFW iniciar o loop dentro do Swift Testing pode encerrar o executor sem resumo.
- O resumo de falha do Swift Testing pode terminar em `with N issues`; isso é uma execução concluída com falha, não uma saída incompleta.

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

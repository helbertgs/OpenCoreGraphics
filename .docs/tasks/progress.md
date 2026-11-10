# Progress Log — Evolução da renderização, concorrência e qualidade

## Codebase Patterns

- O executor `ruby scripts/run-gl-tests.rb` exige os resultados individuais e o resumo final das duas suítes GL; código zero sem resumo ou teste ignorado não é sucesso.
- Execuções GL nesta sessão iniciaram ambas as suítes, mas o processo terminou sem resumo Swift Testing. Reproduzir com o executor antes de atribuir a causa ao renderer.
- Os testes do executor usam processos Ruby controlados e não precisam de GPU; a suíte roda em macOS/Linux.

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

# Progress Log — Reestruturação do OpenCoreGraphics

## Codebase Patterns
- Para ver só os erros de build: `swift build 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error:|Build complete"`. O Swift para no primeiro arquivo com erro, então **depois de corrigir um erro, rode o build de novo**: outros erros podem estar escondidos.
- O build usa o sistema do Xcode (`.build/out/...`); o aviso "found 2 file(s) which are unhandled" é o `Resources/default/*.glsl` ainda não declarado em `Package.swift` (resolvido na US-005).
- `CGColor.components` é `[Double]`; qualquer chamada `glad_*` que recebe `GLfloat` precisa de `Float(...)`.
- O working tree tem trabalho em andamento do usuário (arquivos novos/movidos ainda não commitados). Os commits das stories incluem **apenas** os arquivos tocados pela story, mais `.docs/tasks/prd.json` e `progress.md`.

---

## 2026-11-09 - US-001
- Convertido `prd-reestruturacao-renderizacao.md` em `.docs/tasks/prd.json` (62 stories) e criada a branch `feature/reestruturacao-renderizacao`.
- `CGShading.setUniform4f` agora converte cada componente com `Float(...)`.
- `CGWindow.clear()` tinha o mesmo erro `Double -> GLfloat` em `glad_glClearColor`; corrigido junto, pois o critério exige build sem nenhum `error:`.
- Files changed: `Sources/OpenCoreGraphics/Utility and Support Classes/CGShading.swift`, `Sources/OpenCoreGraphics/Services/Window Services/CGWindow.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`
- **Learnings for future iterations:**
  - O erro reportado no início era só o primeiro; havia um segundo escondido em `CGWindow.swift:248`.
  - `swift test` ainda falha por `CGPathTests` (`let` em struct com métodos `mutating`): é a US-002.
---

## 2026-11-09 - US-002
- Em `CGPathTests.swift`, `let` virou `var` onde o `CGPath` (struct) é mutado; `initEmptyPath`, `initRect`, `initEllipse`, `initRoundedRect` e `containsAlwaysFalse` continuam `let`.
- O arquivo antigo `Tests/OpenCoreGraphicsTests/CGPathTests.swift` já não existe.
- `swift test`: 20 testes passam. Nenhum precisou de `withKnownIssue`.
- Files changed: `Tests/OpenCoreGraphicsTests/2D Drawing/CGPathTests.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`
- **Learnings for future iterations:**
  - O compilador avisa "never mutated" quando `var` é desnecessário; use isso para achar os `let` corretos.
  - `containsAlwaysFalse` testa o comportamento **errado** de `CGPath.contains`; a US-031 precisa reescrevê-lo.
  - A saída do Swift Testing é `✔ Test run with N tests ... passed`; a linha "Executed 0 tests" é do XCTest e pode ser ignorada.
---

## 2026-11-09 - US-003
- Removidos `NSGraphicsContext.swift`, `NSWindowGraphicsContext.swift` e `NSBitmapGraphicsContext.swift`.
- `main.swift` do Sample reescrito: cria `CGWindow` 512×512, define `display` e desenha dois retângulos via `window.cgContext`, sem comentários.
- `grep` por `NSGraphicsContext|NSWindowGraphicsContext|NSBitmapGraphicsContext` em `Sources` e `Tests` não retorna nada.
- Files changed: `Sources/OpenCoreGraphics/Services/Window Services/NS*GraphicsContext.swift` (removidos), `Sources/OpenCoreGraphicsSample/main.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`
- **Learnings for future iterations:**
  - `CGWindow` e o `main.swift` são `@MainActor`; `window.display` é uma closure simples e pode chamar `window.cgContext` direto.
  - `CGWindow.cgContext` ainda é `CGWindowContext` (vira typealias de `CGContext` na US-014).
  - Não rode o Sample dentro do loop automatizado: `makeKeyAndOrderFront()` bloqueia até a janela fechar. Verificação visual fica para o usuário.
---

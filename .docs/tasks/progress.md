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

## 2026-11-09 - US-004
- Removidos: bloco comentado `cgContext` e `// open func display()` em `CGWindow`; código comentado de `CGWindowContext.draw` e `CGFont`; todos os comentários `//` explicativos em `CGContext`, `CGWindowContext`, `CGPath`, `CGBuffer`; `print` de `CGShading` (junto com `debugShader`/`debugProgram`) e de `CGFont`.
- `// Return a rectangle that represents infinity.` em `CGRect.infinite` virou `///` (a declaração precisa de documentação).
- `CGFont.init?` não guarda mais o `Data` lido (só valida que o arquivo existe), para evitar aviso de variável não usada.
- Files changed: `CGBuffer`, `CGShading`, `CGRect`, `CGWindowContext`, `CGWindow`, `CGContext`, `CGPath`, `CGFont` (+ `prd.json`, `progress.md`)
- **Learnings for future iterations:**
  - `// MARK:` foi mantido de propósito (estilo de documentação existente). Se o `AGENTS.md` quiser proibir também, é uma limpeza separada e grande.
  - Os `//` que restam em `CGShading.swift` estão dentro de strings GLSL, não são comentários Swift.
  - Sem `debugShader`, erros de compilação de shader ficam silenciosos até a US-022 (`GLProgram` com erro tipado).
  - Script de limpeza usado: regex `^[ \t]*//(?!/)(?![ \t]*MARK:).*\n` por arquivo; revise o diff depois (comentário doc `///` de um item comentado precisa sair junto).
---

## 2026-11-09 - US-005
- `Package.swift`: dependências fixadas por `revision:` (as mesmas de `Package.resolved`), `platforms: [.macOS(.v13)]` (provisório, Q-1 do PRD), `resources: [.copy("Resources")]` no target `OpenCoreGraphics`, e o `OpenCoreGraphicsSample` deixou de ser `product` (continua `executableTarget`).
- `.gitignore`: removida a linha `Package.resolved`; o arquivo foi gerado de novo e passa a ser versionado.
- O aviso "found 2 file(s) which are unhandled" (shaders `.glsl`) desapareceu.
- Files changed: `Package.swift`, `.gitignore`, `Package.resolved`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`
- **Learnings for future iterations:**
  - Trocar `branch:` por `revision:` no manifesto **não** atualiza o `Package.resolved`: o SwiftPM reaproveita `.build/workspace-state.json` e mantém `"branch": "main"` nos pins. Para regenerar: mover esse arquivo, apagar `Package.resolved` e rodar `swift package resolve` (precisa de rede ou cache).
  - `swift package dump-package` mostra o que o manifesto realmente declara (requisitos, plataformas, recursos).
  - Os arquivos em `Resources/` são `.copy`: o acesso em código será por `Bundle.module` (US-021).
---

## 2026-11-09 - US-006
- Criado `CGGraphicsState: Sendable` com os 18 parâmetros do estado gráfico e defaults cobertos por Swift Testing.
- `CGLineCap` e `CGLineJoin` já existiam com os casos da API Apple; foram reutilizados.
- `font` guarda o nome imutável da fonte, evitando inserir a classe mutável `CGFont` em um valor `Sendable`.
- Files changed: `Sources/OpenCoreGraphics/Services/Window Services/CGGraphicsState.swift`, `Tests/OpenCoreGraphicsTests/2D Drawing/CGContextTests.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`
- **Learnings for future iterations:**
  - Para incluir uma fonte em estados transferíveis, capture seu identificador de valor; `CGFont` é uma classe mutável e não `Sendable`.
  - `CGLineCap` e `CGLineJoin` já estão definidos em `Enumerations/`; confira tipos existentes antes de duplicá-los.
---

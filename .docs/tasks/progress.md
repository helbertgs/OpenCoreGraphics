# Progress Log — Reestruturação do OpenCoreGraphics

## Codebase Patterns
- Para ver só os erros de build: `swift build 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "error:|Build complete"`. O Swift para no primeiro arquivo com erro, então **depois de corrigir um erro, rode o build de novo**: outros erros podem estar escondidos.
- O build usa o sistema do Xcode (`.build/out/...`); o aviso "found 2 file(s) which are unhandled" é o `Resources/default/*.glsl` ainda não declarado em `Package.swift` (resolvido na US-005).
- `CGColor.components` é `[Double]`; qualquer chamada `glad_*` que recebe `GLfloat` precisa de `Float(...)`.
- As conversões entre espaço de usuário e pixels usam `ctm`; `CGAffineTransform.inverse` não reverte corretamente translações 2D, então o contexto calcula a inversa 2D localmente.
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

## 2026-11-09 - US-007
- Implementados snapshots empilhados e restauração dos parâmetros gráficos em `CGContext` e `CGWindowContext`.
- O caminho atual permanece fora do estado; `restoreGState()` vazio não altera o contexto.
- Testes cobrem três níveis de aninhamento, CTM, caminho preservado e restauração sem `saveGState()`.
- Files changed: `Sources/OpenCoreGraphics/Services/Window Services/CGContext.swift`, `Sources/OpenCoreGraphics/Services/Window Services/CGWindowContext.swift`, `Tests/OpenCoreGraphicsTests/2D Drawing/CGContextTests.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`
- **Learnings for future iterations:**
  - `CGContext` e `CGWindowContext` ainda duplicam a implementação da API; mudanças de estado devem manter ambos sincronizados até a unificação prevista na US-014.
  - O current path não é parte de `CGGraphicsState` e não deve ser copiado nem restaurado.
---

## 2026-11-09 - US-008
- Unificada a composição de `rotate`, `scaleBy`, `translateBy` e `concatenate` para `ctm = ctm * transform` em `CGContext` e `CGWindowContext`.
- Atualizada a documentação de `concatenate` e adicionados testes para verificar a ordem de composição e o ponto `(1, 1) -> (12, 23)` após translação e escala.
- A fórmula textual original (`transform * ctm`) contradizia o resultado aceito no critério; o usuário escolheu priorizar o resultado `(12, 23)`.
- Files changed: `Sources/OpenCoreGraphics/Services/Window Services/CGContext.swift`, `Sources/OpenCoreGraphics/Services/Window Services/CGWindowContext.swift`, `Tests/OpenCoreGraphicsTests/2D Drawing/CGContextTests.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`
- **Learnings for future iterations:**
  - Com a convenção de `CGPoint.applying` e do operador `CGAffineTransform *`, a sequência translação seguida de escala requer CTM `translation * scaling` para preservar a translação.
  - Ainda há contextos duplicados; mantenha ambos alinhados até a US-014.
---

## 2026-11-09 - US-009
- Os métodos `addArc(center:)`, `addArc(tangent1End:)`, `addCurve` e `addQuadCurve` agora encaminham `ctm` ao `CGPath` em `CGContext` e `CGWindowContext`.
- Adicionado teste verificando a transformação por escala de pontos de arco, endpoints e pontos de controle de curvas.
- Build e testes passaram (25 testes).
- Files changed: `Sources/OpenCoreGraphics/Services/Window Services/CGContext.swift`, `Sources/OpenCoreGraphics/Services/Window Services/CGWindowContext.swift`, `Tests/OpenCoreGraphicsTests/2D Drawing/CGContextTests.swift`, `.docs/tasks/prd.json`, `.docs/tasks/progress.md`
- **Learnings for future iterations:**
  - Os métodos equivalentes do `CGPath` já aceitam `transform:`; encaminhe a CTM do contexto em vez de duplicar a matemática.
  - Pontos produzidos por `sin`/`cos` precisam de tolerância em testes por causa de resíduos de ponto flutuante.
---

## 2026-11-09 - US-010
- Conversões de pontos, retângulos e tamanhos agora usam a CTM e preservam coordenadas em pixels, sem mapear para NDC.
- Conversões de retângulos transformam os quatro cantos para obter a caixa delimitadora; conversões inversas usam a inversa 2D da CTM.
- Testes cobrem cinco pontos sob quatro CTMs, a borda superior direita de um contexto 200×100, e a ida e volta de retângulos/tamanhos com escala e translação.
- `swift test --filter CGContextTests` passou (6 testes); `swift test` passou (26 testes).
- **Learnings for future iterations:**
  - `CGAffineTransform.inverse` não reverte corretamente a translação em matrizes 2D; as conversões do contexto precisam da inversa 2D calculada explicitamente até a implementação geral ser corrigida.
  - `CGWindowContext` mantém a API duplicada de `CGContext` até a US-014; alterações em conversões de coordenadas precisam permanecer alinhadas nos dois tipos.
---

## 2026-11-09 - US-011
- Criados os tipos `DrawCommand` e `StrokeStyle`, ambos `Sendable` e `Equatable`, capturando parâmetros de preenchimento, traço, imagem, clipping e glifos.
- O caso de imagem armazena uma cópia opcional de `Data` e dimensões, em vez de reter `CGImage`, que é mutável e não `Sendable`.
- Teste verifica criação e igualdade de todos os cinco casos.
- `swift test --filter DrawCommandTests` passou (1 teste).
- **Learnings for future iterations:**
  - Comandos que atravessam o limite do backend precisam carregar valores imutáveis e `Sendable`; para imagens, copie os bytes do provedor ao criar o comando.
---

## 2026-11-09 - US-012
- Criados os protocolos internos `CGRenderTarget` e `CGRenderBackend`, além do `RecordingRenderTarget`.
- O alvo de gravação mantém a ordem das operações sem importar OpenGL e retorna `nil` para pixels, pois não rasteriza comandos.
- Teste envia três comandos e verifica dimensões, ordem e ausência de buffer de pixels.
- `swift test --filter CGRenderTargetTests` passou (1 teste).
- **Learnings for future iterations:**
  - `RecordingRenderTarget` é o alvo de injeção para testar filas de renderização sem criar uma janela ou contexto OpenGL.
---

## 2026-11-09 - US-013
- `CGContext` deixou de importar/chamar OpenGL e agora enfileira operações de preenchimento, traço, elipse, limpeza e imagem como `DrawCommand`.
- `flush()` transfere a fila ao `CGRenderTarget` em ordem e mantém os comandos pendentes quando ainda não há alvo conectado.
- `drawPath(.fillStroke)` grava dois comandos na ordem correta; fill/stroke individuais limpam o caminho depois de enfileirar.
- Formas aplicam a CTM ao construir o caminho, e os comandos capturam a regra de preenchimento, cores, blend e estilo de traço.
- `swift test --filter CGContextCommandTests` passou (4 testes); `CGContext.swift` não contém mais referências OpenGL.
- **Learnings for future iterations:**
  - O `flush()` público de CGContext já existia como método vazio; a fila de comandos usa esse ponto de integração, sem acrescentar API pública.
  - A conversão de imagem para comando copia os bytes do provider e deixa dimensões/blend capturados no valor, evitando reter a classe mutável `CGImage`.
---

## 2026-11-09 - US-014
- Adicionado `CGContext(width:height:)` para criar um contexto com dimensões em pixels.
- `CGWindow.cgContext` agora é `CGContext`; a implementação única foi movida para `2D Drawing/CGContext.swift`.
- Removido `CGWindowContext.swift`; mantido apenas o typealias público deprecated para compatibilidade.
- `swift test` passou (33 testes).
- **Learnings for future iterations:**
  - O alias legado foi colocado ao lado da implementação canônica; não há mais dependências de `CGWindowContext` no código de produção.
---

## 2026-11-09 - US-015
- Adicionadas as propriedades `name`, `model` e `numberOfComponents` a `CGColorSpace`.
- Teste parametrizado cobre sRGB, RGB linear genérico, CMYK genérico e cinza linear.
- `swift test --filter CGColorSpaceTests` passou (4 casos).
- **Learnings for future iterations:**
  - `CGColorModel` já contém os modelos necessários; os metadados do enum podem ser derivados diretamente dos quatro casos sem novos tipos auxiliares.
---

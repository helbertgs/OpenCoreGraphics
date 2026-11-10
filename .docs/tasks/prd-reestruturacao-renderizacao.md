# PRD: Reestruturação da arquitetura e do pipeline de renderização do OpenCoreGraphics

> **Origem:** [ADR 0001](../ADRs/0001-analise-arquitetural-e-reestruturacao.md) e [ADR 0002](../ADRs/0002-backend-de-renderizacao-em-software.md).
> **Idioma:** Português (Brasil). Identificadores de código ficam em inglês.
> **Escopo:** Fases 0 a 7 das ADRs.

---

## 1. Introdução / Visão geral

O OpenCoreGraphics reimplementa a API do Core Graphics da Apple sobre OpenGL para Windows e Linux. Hoje o projeto é um protótipo com problemas que impedem o uso:

- **O pacote não compila** (`CGShading.swift:111`) e os testes de `CGPath` não compilam.
- **Duas cópias quase idênticas** de contexto de desenho (`CGContext` e `CGWindowContext`, ~90 % de código repetido).
- **Resultado visual incorreto:** `stroke` pinta o polígono preenchido; o preenchimento aceita no máximo 16 vértices; elipses saem erradas; `CGImage(url:)` apaga a própria textura; `draw(_:in:)` ignora o retângulo.
- **Nada é testável sem GPU**, porque cada método de desenho chama `glad_*` diretamente. A cobertura de testes está muito abaixo da meta de 80 %.
- **O `CGContext(data:…)` (bitmap) não renderiza nada**: descarta o ponteiro de memória.

Este PRD descreve o trabalho para reestruturar o framework em camadas, com **gravação de comandos de desenho** e **dois backends de renderização**:

1. **`GLRenderer`** (OpenGL 3.3 Core) para janelas.
2. **`SoftwareRenderer`** (CPU) para bitmaps, sem contexto OpenGL.

### Glossário rápido (para quem é novo no projeto)

| Termo | Significado |
|---|---|
| **Contexto (`CGContext`)** | Objeto onde o app "desenha" (cor, retângulo, caminho, imagem). |
| **`DrawCommand`** | Um comando gravado pelo contexto, por exemplo "preencher este caminho com esta cor". |
| **Backend** | Quem executa os comandos: OpenGL (GPU) ou software (CPU). |
| **Caminho (`CGPath`)** | Descrição matemática de linhas e curvas. |
| **Flatten** | Converter curvas Bézier em pequenos segmentos de reta. |
| **Stencil-then-cover** | Técnica de OpenGL para preencher formas côncavas ou com buracos sem triangular na CPU. |
| **Pré-multiplicado** | Cor em que R, G, B já foram multiplicados pelo alfa. |
| **CTM** | Matriz de transformação atual do contexto. |

---

## 2. Objetivos

- **O1.** `swift build` e `swift test` passam em macOS, sem erros.
- **O2.** Uma janela (`CGWindow`) renderiza retângulos, elipses, caminhos, traços e imagens corretamente com OpenGL.
- **O3.** Existe **um único** `CGContext`; a duplicação de código é eliminada.
- **O4.** Nenhuma chamada `glad_*` fora da camada de backend GL.
- **O5.** `CGContext(data:…)` renderiza em memória **sem OpenGL**.
- **O6.** Cobertura de testes **≥ 80 %**, medida com `swift test --enable-code-coverage`.
- **O7.** Recursos OpenGL (programas, texturas, framebuffers) têm dono explícito e são liberados no ator correto.
- **O8.** Paridade visual aceitável entre GL e software (qualidade: clipping, anti-aliasing, blend, sombra, gradiente).
- **O9.** Texto desenhado por glifos (`showGlyphs`).

---

## 3. Regras do projeto que valem para **todas** as user stories

Extraídas do `AGENTS.md`. Cada story deve respeitá-las, mesmo que não as repita.

| Regra | Como verificar |
|---|---|
| Sem comentários de código nas implementações | Revisão: nenhum `//` ou `/* */` em código novo |
| Toda declaração (tipo, função, propriedade) documentada com `///`, em linguagem que um júnior entenda, seguindo a documentação existente | Revisão do diff |
| Chamadas OpenGL somente via OpenGLAD (`glad_*`) e **apenas** na camada de backend GL | `grep -rn "glad_" Sources` só retorna arquivos em `Sources/OpenCoreGraphics/Rendering/GL/` (a partir da US-028) |
| Código novo de concorrência segue a skill `/swift-concurrency-pro`; **sem** `@unchecked Sendable` | Revisão |
| Testes escritos com **Swift Testing** seguindo a skill `/swift-testing-pro` | Revisão |
| Novas funções auxiliares são `private` sempre que possível | Revisão |
| Alterações de declaração existente são permitidas **quando necessárias** para funcionar (ADR 0001, Q2), preferindo manter compatibilidade | Registrar no resumo do commit |

### Critérios comuns de aceite (abreviados nas stories)

Toda story inclui implicitamente:

- [ ] **Build:** `swift build` passa sem erros.
- [ ] **Testes:** `swift test` passa, com testes novos para o comportamento novo.
- [ ] **Documentação:** declarações novas documentadas com `///`; sem comentários de implementação.

Stories com verificação visual incluem: **Visual:** executar `swift run OpenCoreGraphicsSample` e confirmar o resultado descrito. (Não há navegador neste projeto; a janela do Sample substitui o `dev-browser`.)

---

## 4. User Stories

> Cada story deve caber em uma sessão de trabalho focada. A ordem respeita as dependências entre as fases.

---

### Fase 0 — Destravar o projeto

#### US-001: Corrigir a conversão `Double` → `Float` no `CGShading`
**Description:** Como desenvolvedor, quero que `swift build` compile para poder trabalhar no projeto.

**Acceptance Criteria:**
- [ ] `setUniform4f(name:value:)` (`CGShading.swift:109-112`) converte cada componente de `CGColor` para `Float` antes de chamar `glad_glUniform4f`
- [ ] `swift build` conclui sem nenhum `error:`
- [ ] Build e testes passam

#### US-002: Corrigir os testes de `CGPath`
**Description:** Como desenvolvedor, quero que os testes de `CGPath` compilem, pois `CGPath` é `struct` e os testes chamam métodos `mutating`.

**Acceptance Criteria:**
- [ ] Em `Tests/OpenCoreGraphicsTests/2D Drawing/CGPathTests.swift`, todo `let path = CGPath()` que sofre mutação passa a `var`
- [ ] O arquivo antigo `Tests/OpenCoreGraphicsTests/CGPathTests.swift` (já removido no working tree) não existe mais
- [ ] `swift test` executa todos os testes de `CGPath`; os que falharem por bugs reais do `CGPath` ficam marcados com `withKnownIssue` e referenciam a story que os corrige (US-030 a US-033)
- [ ] Build e testes passam

#### US-003: Remover as classes `NSGraphicsContext`, `NSWindowGraphicsContext` e `NSBitmapGraphicsContext`
**Description:** Como mantenedor, quero remover as classes sem uso para reduzir confusão.

**Acceptance Criteria:**
- [ ] Os três arquivos `NS*GraphicsContext.swift` em `Services/Window Services/` são removidos
- [ ] `grep -rn "NSGraphicsContext\|NSWindowGraphicsContext\|NSBitmapGraphicsContext" Sources Tests` não retorna nada
- [ ] `Sources/OpenCoreGraphicsSample/main.swift` compila usando `CGWindow` (sem `NSGraphicsContext.current`)
- [ ] Build e testes passam

#### US-004: Remover código morto e comentado
**Description:** Como mantenedor, quero eliminar código comentado e `print` de depuração, em conformidade com o `AGENTS.md`.

**Acceptance Criteria:**
- [ ] Removido o bloco comentado `cgContext` em `CGWindow.swift`
- [ ] Removido o código comentado de `CGWindowContext.draw` e de `CGFont.swift`
- [ ] Removidos os `print` de diagnóstico de `CGShading` e `CGFont`
- [ ] Removido o `// open func display()` comentado em `CGWindow.swift`
- [ ] `grep -rn "^\s*//" Sources/OpenCoreGraphics` não retorna comentários de implementação (cabeçalhos `///` são permitidos)
- [ ] Build e testes passam

#### US-005: Ajustar o `Package.swift`
**Description:** Como desenvolvedor, quero um manifesto reprodutível e correto para o build ser estável.

**Acceptance Criteria:**
- [ ] Dependências `OpenGLAD`, `OpenGLFW` e `OpenSTB` fixadas por `revision:` (não mais `branch: "main"`), usando as revisões de `Package.resolved`
- [ ] `Package.resolved` removido do `.gitignore` e versionado
- [ ] O executável `OpenCoreGraphicsSample` deixa de ser `product` (continua como `executableTarget`)
- [ ] `platforms` declarado (tentativa: `.macOS(.v13)`; ver Questão Q-1)
- [ ] Target `OpenCoreGraphics` declara `resources: [.copy("Resources")]`
- [ ] `swift package resolve` e `swift build` passam
- [ ] Build e testes passam

---

### Fase 1 — Estado gráfico e comandos (núcleo sem OpenGL)

#### US-006: Criar o tipo `CGGraphicsState`
**Description:** Como desenvolvedor, quero um tipo de valor com todo o estado gráfico para permitir `saveGState`/`restoreGState`.

**Acceptance Criteria:**
- [ ] `struct CGGraphicsState: Sendable` com: `ctm`, `fillColor`, `strokeColor`, `fillColorSpace`, `strokeColorSpace`, `lineWidth`, `lineCap`, `lineJoin`, `miterLimit`, `lineDash`, `blendMode`, `interpolationQuality`, `renderingIntent`, `clip`, `font`, `fontSize`, `characterSpacing`, `textDrawingMode`
- [ ] Valores iniciais iguais aos da API Apple (`lineWidth = 1`, `fillColor` e `strokeColor` pretos, `ctm = .identity`, `blendMode = .normal`)
- [ ] `lineCap`, `lineJoin` e `lineDash` ganham tipos novos (`CGLineCap`, `CGLineJoin`) com os mesmos casos da API Apple
- [ ] Testes verificam todos os valores iniciais
- [ ] Build e testes passam

#### US-007: Implementar `saveGState` e `restoreGState`
**Description:** Como usuário da API, quero salvar e restaurar o estado gráfico para isolar mudanças de desenho.

**Acceptance Criteria:**
- [ ] `saveGState()` empilha uma cópia do `CGGraphicsState`; `restoreGState()` desempilha
- [ ] Mudar cor, `lineWidth` ou CTM entre `save` e `restore` não afeta o estado após o `restore`
- [ ] O caminho atual (`path`) **não** faz parte do estado e não é restaurado
- [ ] `restoreGState()` sem `saveGState()` correspondente não faz nada e não falha
- [ ] Testes cobrem aninhamento de 3 níveis e o caso sem `save`
- [ ] Build e testes passam

#### US-008: Unificar a composição da CTM
**Description:** Como usuário da API, quero que `translateBy`, `scaleBy`, `rotate` e `concatenate` componham a CTM como no Core Graphics da Apple.

**Acceptance Criteria:**
- [ ] Os quatro métodos usam a **mesma** regra de composição (`ctm = transform × ctm`), hoje inconsistente (`CGContext.swift:818`, `:827`, `:837`)
- [ ] Teste: após `translateBy(x: 10, y: 20)` seguido de `scaleBy(x: 2, y: 3)`, o ponto de usuário `(1, 1)` vai para `(12, 23)` no espaço de destino
- [ ] A documentação `///` de `concatenate` descreve a regra real
- [ ] Build e testes passam

#### US-009: Aplicar a CTM em todos os métodos de caminho do contexto
**Description:** Como usuário da API, quero que todo método que adiciona ao caminho respeite a CTM.

**Acceptance Criteria:**
- [ ] `addArc(center:…)`, `addArc(tangent1End:…)`, `addCurve` e `addQuadCurve` passam `ctm` ao `CGPath`, como já fazem `addLine`, `addRect`, `addEllipse` e `addPath`
- [ ] Teste: com `scaleBy(x: 2, y: 2)`, cada um desses métodos produz pontos multiplicados por 2
- [ ] Build e testes passam

#### US-010: Unificar o sistema de coordenadas
**Description:** Como usuário da API, quero que o espaço de dispositivo seja em **pixels**, com origem no canto inferior esquerdo, como na Apple e no OpenGL.

**Acceptance Criteria:**
- [ ] `convertToDeviceSpace` (ponto, retângulo, tamanho) devolve pixels, e `convertToUserSpace` faz o inverso; ambos levam em conta a CTM
- [ ] Remove-se a conversão para NDC `[-1, 1]` dos métodos de conversão
- [ ] `userSpaceToDeviceSpaceTransform` passa a ser usado de fato pelas conversões
- [ ] Teste de ida e volta: `convertToUserSpace(convertToDeviceSpace(p)) == p` para 5 pontos e CTMs diferentes
- [ ] Teste: em contexto 200×100 sem CTM, o ponto `(200, 100)` é o canto superior direito
- [ ] Build e testes passam

#### US-011: Criar o enum `DrawCommand`
**Description:** Como desenvolvedor, quero um conjunto de comandos de desenho independente de backend.

**Acceptance Criteria:**
- [ ] `enum DrawCommand: Sendable` com casos: `fillPath`, `strokePath`, `drawImage`, `clip`, `glyphs` (carregando caminho/regra/cor/blend/estilo conforme o caso)
- [ ] Tipo auxiliar `StrokeStyle: Sendable` (largura, cap, join, miter limit, dash)
- [ ] Todos os caminhos nos comandos já estão no espaço de dispositivo (CTM aplicada)
- [ ] Testes de igualdade/criação para cada caso
- [ ] Build e testes passam

#### US-012: Criar `CGRenderTarget`, `CGRenderBackend` e `RecordingRenderTarget`
**Description:** Como desenvolvedor, quero abstrações internas para executar comandos e um alvo de gravação para testes.

**Acceptance Criteria:**
- [ ] Protocolos internos `CGRenderTarget` (`size`, `submit(_:)`, `readPixels()`) e `CGRenderBackend` (`execute(_:size:)`)
- [ ] `RecordingRenderTarget` guarda em memória a lista de comandos recebidos
- [ ] Nenhum desses tipos importa `OpenGLAD` ou `OpenGLFW`
- [ ] Teste: enviar 3 comandos e lê-los de volta na mesma ordem
- [ ] Build e testes passam

#### US-013: `CGContext` grava `DrawCommand` em vez de chamar OpenGL
**Description:** Como desenvolvedor, quero que desenhar não toque OpenGL, para poder testar o contexto sem GPU.

**Acceptance Criteria:**
- [ ] `fill(_:)`, `fill(_ rects:)`, `fillPath`, `strokePath`, `drawPath(using:)`, `stroke(_:)`, `fillEllipse`, `strokeEllipse`, `clear(_:)` e `draw(_:in:)` geram `DrawCommand` e os enviam ao `CGRenderTarget` em `flush()`
- [ ] `drawPath(using: .fillStroke)` gera **dois** comandos: preenchimento e depois traço
- [ ] A regra de preenchimento (`winding` / `evenOdd`) viaja no comando
- [ ] `fillPath` e `strokePath` limpam o caminho atual após gravar
- [ ] `CGContext.swift` não importa `OpenGLAD`
- [ ] Testes usando `RecordingRenderTarget` verificam o comando gerado para cada método acima
- [ ] Build e testes passam

#### US-014: Mesclar `CGWindowContext` em `CGContext`
**Description:** Como mantenedor, quero eliminar a duplicação entre `CGContext` e `CGWindowContext`.

**Acceptance Criteria:**
- [ ] `CGContext` ganha `init(width:height:)` de conveniência (equivalente ao de `CGWindowContext`)
- [ ] `public typealias CGWindowContext = CGContext`, marcado `@available(*, deprecated, message: …)`
- [ ] Arquivo `CGWindowContext.swift` removido; `CGWindow.cgContext` passa a ser do tipo `CGContext`
- [ ] Existe um único arquivo com a implementação de `CGContext` (move-se para `Sources/OpenCoreGraphics/2D Drawing/CGContext.swift`)
- [ ] Build e testes passam

#### US-015: `CGColorSpace` com `name`, `model` e `numberOfComponents`
**Description:** Como usuário da API, quero consultar informações do espaço de cor.

**Acceptance Criteria:**
- [ ] O enum `CGColorSpace` mantém os 4 casos atuais e ganha `name: String`, `model: CGColorModel` e `numberOfComponents: Int`
- [ ] `sRGB` e `genericRGBLinear` → `.rgb`, 3 componentes; `genericCMYK` → `.cmyk`, 4; `linearGray` → `.gray`, 1
- [ ] Teste parametrizado (`@Test(arguments:)`) cobrindo os 4 casos
- [ ] Build e testes passam

#### US-016: Substituir `CGBitmapParameters` por um tipo tipado
**Description:** Como desenvolvedor, quero eliminar o `[String: Any]` com `as!` que pode travar em tempo de execução.

**Acceptance Criteria:**
- [ ] `CGBitmapParameters` passa a ter propriedades tipadas: `colorSpace`, `layout: CGBitmapLayout`, `component: CGComponent`, `componentInfo: CGImageComponentInfo`, `alphaInfo`
- [ ] Remove-se o `@dynamicMemberLookup` e o dicionário
- [ ] Teste de criação e leitura de cada propriedade
- [ ] Build e testes passam

#### US-017: Acessores 2D em `CGAffineTransform`
**Description:** Como usuário da API, quero usar `a, b, c, d, tx, ty` como na API da Apple, mantendo a matriz 4×4.

**Acceptance Criteria:**
- [ ] Propriedades `a`, `b`, `c`, `d`, `tx`, `ty` (leitura e escrita) mapeadas para a matriz 4×4
- [ ] `init(a:b:c:d:tx:ty:)` público
- [ ] Teste: `CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 5, ty: 7)` aplicado em `(0, 0)` resulta em `(5, 7)`
- [ ] Teste: `translate(5, 7)` expõe `tx == 5` e `ty == 7`
- [ ] Build e testes passam

#### US-018: Cobertura do núcleo ≥ 80 %
**Description:** Como mantenedor, quero garantir que o núcleo sem OpenGL está bem testado.

**Acceptance Criteria:**
- [ ] `swift test --enable-code-coverage` gera relatório
- [ ] Cobertura de linhas de `CGContext`, `CGGraphicsState`, `DrawCommand`, `CGPath`, `CGColor`, `CGColorSpace` e tipos geométricos ≥ 80 %
- [ ] O comando para medir e o resultado são registrados em `.docs/tasks/coverage.md`
- [ ] Build e testes passam

---

### Fase 2 — Backend OpenGL básico (janela renderizando)

#### US-019: `GLFWPlatform` com contagem de referência
**Description:** Como desenvolvedor, quero que fechar uma janela não destrua as outras.

**Acceptance Criteria:**
- [ ] `@MainActor` `GLFWPlatform` com `retain()` e `release()`; `glfwInit` só na primeira retenção, `glfwTerminate` só quando a contagem chega a zero
- [ ] `CGWindow` usa `GLFWPlatform` e deixa de chamar `glfwInit`/`glfwTerminate` diretamente
- [ ] `CGWindow.deinit` não chama mais `glfwTerminate` de forma incondicional
- [ ] Teste unitário da contagem de referência com um *driver* falso (sem abrir janela)
- [ ] Build e testes passam

#### US-020: Título e erros tipados na criação da janela
**Description:** Como usuário da API, quero que o título apareça na janela e que falhas retornem erro em vez de `fatalError`.

**Acceptance Criteria:**
- [ ] O título passado ao criar a janela chega a `glfwCreateWindow` (hoje é sempre `""`)
- [ ] `CGWindow.init(frame:)` passa a `throws` com erros tipados (`CGWindowError.glfwInitFailed`, `.windowCreationFailed`, `.gladLoadFailed`)
- [ ] Nenhum `fatalError` resta em `CGWindow.swift`
- [ ] Sample atualizado para `try CGWindow(...)`
- [ ] Build e testes passam

#### US-021: Shaders GLSL em `Resources/`
**Description:** Como desenvolvedor, quero os shaders em arquivos próprios para facilitar edição.

**Acceptance Criteria:**
- [ ] `Resources/default/vertex.glsl` e `fragment.glsl` (cor sólida): recebem posição em pixels, usam *uniform* de projeção e `uColor`
- [ ] `Resources/image/vertex.glsl` e `fragment.glsl` (textura): posição + coordenada de textura + `uImage`
- [ ] Todos com `#version 330 core`
- [ ] Função interna que carrega o texto pelo `Bundle.module` e retorna erro tipado se o arquivo não existir
- [ ] Teste: carregar cada um dos 4 arquivos e verificar que não estão vazios e contêm `#version 330 core`
- [ ] Build e testes passam

#### US-022: `GLShaderCache` e `GLProgram`
**Description:** Como desenvolvedor, quero compilar cada shader uma única vez e não buscar *uniform locations* a cada desenho.

**Acceptance Criteria:**
- [ ] `GLProgram` (`@MainActor`, `final`) compila/linka vertex+fragment com `glad_*` e guarda um dicionário de *uniform locations*
- [ ] `GLShaderCache` devolve o mesmo `GLProgram` para o mesmo `ShaderKind` sem recompilar
- [ ] `GLProgram` libera o programa em `isolated deinit`
- [ ] Erros de compilação/link geram erro tipado com o *log* do OpenGL (sem `print`)
- [ ] Teste do cache com *loader* falso: pedir o mesmo programa 3 vezes causa 1 compilação
- [ ] Build e testes passam

#### US-023: `GLBatchBuffer`
**Description:** Como desenvolvedor, quero acumular vértices em um VBO dinâmico para reduzir *draw calls*.

**Acceptance Criteria:**
- [ ] `GLBatchBuffer` cria VAO e VBO uma única vez e os reutiliza entre desenhos
- [ ] Acumula vértices de comandos com o mesmo estado (programa, textura, blend) e faz `flush` ao mudar o estado ou ao fim do frame
- [ ] Libera VAO/VBO em `isolated deinit`
- [ ] Teste da lógica de agrupamento (sem GL): 5 comandos com 2 estados distintos resultam em 2 lotes
- [ ] Build e testes passam

#### US-024: `GLRenderer` desenha retângulos opacos
**Description:** Como usuário, quero ver retângulos coloridos na janela.

**Acceptance Criteria:**
- [ ] `GLRenderer` (`@MainActor`, `final`) implementa `CGRenderBackend`
- [ ] Projeção ortográfica enviada por *uniform*, derivada de `userSpaceToDeviceSpaceTransform`
- [ ] `fillPath` com retângulo vira 2 triângulos
- [ ] Um único programa compilado por `GLRenderer`, não por desenho
- [ ] `WindowRenderTarget` conecta o `CGContext` da janela ao `GLRenderer`
- [ ] **Visual:** `swift run OpenCoreGraphicsSample` mostra um retângulo azul e um vermelho (ver US-026)
- [ ] Build e testes passam

#### US-025: Redimensionar a janela atualiza viewport, tamanho e projeção
**Description:** Como usuário, quero que o desenho continue correto ao redimensionar a janela.

**Acceptance Criteria:**
- [ ] O callback de redimensionamento atualiza: `glViewport`, `width`/`height` do `CGContext` e a projeção
- [ ] O trabalho fica em um único ponto (`CGWindow`), sem duplicação entre callbacks
- [ ] **Visual:** ao arrastar a borda da janela do Sample, os retângulos mantêm proporção e posição em pixels
- [ ] Build e testes passam

#### US-026: Sample desenha dois retângulos
**Description:** Como desenvolvedor, quero um exemplo mínimo que prove a renderização OpenGL.

**Acceptance Criteria:**
- [ ] `main.swift` cria `CGWindow` (tamanho 512×512), define `display` e usa `window.cgContext`
- [ ] Preenche `CGRect(x: 20, y: 20, width: 150, height: 200)` com azul `(0.2, 0.5, 0.8, 1)` e `CGRect(x: 200, y: 100, width: 150, height: 200)` com vermelho `(1, 0, 0, 1)`
- [ ] **Visual:** `swift run OpenCoreGraphicsSample` abre a janela com os dois retângulos nas posições esperadas e a origem no canto inferior esquerdo
- [ ] Build e testes passam

#### US-027: Remover `CGBuffer` e `CGShading` antigos
**Description:** Como mantenedor, quero tirar os tipos públicos que vazam detalhes de OpenGL.

**Acceptance Criteria:**
- [ ] `CGBuffer.swift` e `CGShading.swift` removidos
- [ ] Nenhum uso restante em `Sources` ou `Tests`
- [ ] `fillShader` e `strokeShader` estáticos eliminados
- [ ] Build e testes passam

#### US-028: Confinar OpenGL à camada GL
**Description:** Como mantenedor, quero que só o backend GL conheça OpenGL.

**Acceptance Criteria:**
- [ ] Tipos GL ficam em `Sources/OpenCoreGraphics/Rendering/GL/` (`GLRenderer`, `GLShaderCache`, `GLProgram`, `GLBatchBuffer`, e os próximos)
- [ ] `grep -rln "glad_" Sources` retorna apenas arquivos dessa pasta, mais `CGWindow.swift` (criação do contexto, `glClear` e viewport)
- [ ] `grep -rn "import OpenGLAD" Sources` idem
- [ ] Build e testes passam

#### US-029: Isolamento de concorrência correto
**Description:** Como mantenedor, quero que o OpenGL só seja usado na thread principal, com liberação segura de recursos.

**Acceptance Criteria:**
- [ ] Tipos GL e `CGWindow` marcados `@MainActor`
- [ ] `CGContext`, `CGGraphicsState`, `DrawCommand`, `CGPath` e `CGColor` sem isolamento de ator; os valores são `Sendable`
- [ ] Recursos GL liberados com `isolated deinit` (não mais `nonisolated deinit` chamando `delete()`)
- [ ] `@preconcurrency import OpenGLAD` removido de todos os arquivos fora de `Rendering/GL/` e `CGWindow.swift`
- [ ] Nenhum `@unchecked Sendable`
- [ ] `swift build` sem avisos de concorrência
- [ ] Build e testes passam

---

### Fase 3 — Geometria de renderização (compartilhada entre GL e software)

#### US-030: `CGPath` — `closeSubpath` e `addLines`
**Description:** Como usuário da API, quero que fechar subcaminhos e adicionar linhas funcione como no Core Graphics.

**Acceptance Criteria:**
- [ ] `closeSubpath()` define `currentPoint` como o ponto inicial do subcaminho atual (hoje vai para `.zero`)
- [ ] `closeSubpath()` em caminho vazio ou subcaminho já fechado não altera nada
- [ ] `addLines(between:)` faz `move` ao primeiro ponto e linhas aos seguintes
- [ ] Testes cobrem os dois métodos, incluindo o caso vazio
- [ ] Build e testes passam

#### US-031: `CGPath` — `boundingBox`, `copy` e `contains`
**Description:** Como usuário da API, quero consultar o retângulo envolvente, copiar e testar pontos no caminho.

**Acceptance Criteria:**
- [ ] `boundingBox` inclui pontos de controle; `boundingBoxOfPath` não inclui; ambos atualizados a cada operação
- [ ] `copy()` e `copy(using:)` retornam cópia (com transformação, no segundo caso) em vez de `nil`
- [ ] `contains(_:using:transform:)` implementa `winding` e `evenOdd` com o caminho achatado
- [ ] Testes: quadrado `(0,0,10,10)` contém `(5,5)` e não contém `(15,5)`; estrela de 5 pontas difere entre `winding` e `evenOdd` no pentágono central
- [ ] Build e testes passam

#### US-032: `CGPath` — arcos corretos
**Description:** Como usuário da API, quero arcos fiéis à documentação.

**Acceptance Criteria:**
- [ ] `addArc(center:radius:startAngle:endAngle:clockwise:)` respeita `clockwise`, liga o ponto atual ao início do arco se já existir subcaminho e aproxima o arco por curvas Bézier (não 8 segmentos fixos)
- [ ] `addArc(tangent1End:tangent2End:radius:)` calcula o arco tangente às duas retas; não é mais apenas duas linhas
- [ ] `addRelativeArc` continua funcionando sobre `addArc`
- [ ] Testes: arco de 0 a π/2 com raio 10 termina em `(0, 10)` com tolerância 1e-6; o ponto médio fica a distância 10 do centro com tolerância 0,01
- [ ] Build e testes passam

#### US-033: `CGPath` — elementos padrão para retângulos
**Description:** Como desenvolvedor de backend, quero que retângulos usem os mesmos elementos de qualquer outro caminho.

**Acceptance Criteria:**
- [ ] `addRect` gera `moveToPoint`, 3× `addLineToPoint` e `closeSubpath`, em vez do elemento não padrão `addRectToPoint`
- [ ] `addRectToPoint` deixa de ser gerado (o caso do enum pode permanecer, marcado como deprecated)
- [ ] `CGPath(rect:)`, `CGPath(roundedRect:…)` e `addRects` continuam corretos
- [ ] Testes de contagem e tipo de elementos atualizados
- [ ] Build e testes passam

#### US-034: `PathFlattener`
**Description:** Como desenvolvedor de backend, quero converter curvas em segmentos de reta com erro controlado.

**Acceptance Criteria:**
- [ ] `PathFlattener.flatten(_:tolerance:)` retorna polígonos/polilinhas (`[Polyline]`) para `CGPath`, tratando `moveTo`, `line`, `quadCurve`, `curve` e `close`
- [ ] Subdivisão adaptativa (De Casteljau); tolerância padrão 0,25 pixel
- [ ] Teste: círculo de raio 100 achatado com tolerância 0,25 tem todos os pontos entre 99,75 e 100,25 do centro
- [ ] Teste: linha reta gera exatamente 2 pontos
- [ ] Build e testes passam

#### US-035: `Stroker` — largura, caps e joins
**Description:** Como desenvolvedor de backend, quero gerar o contorno de um traço com largura, extremidades e junções corretas.

**Acceptance Criteria:**
- [ ] `Stroker.outline(_:style:)` recebe polilinhas e `StrokeStyle` e devolve polígonos preenchíveis
- [ ] Suporta `lineCap` (`butt`, `round`, `square`) e `lineJoin` (`miter`, `round`, `bevel`) e respeita `miterLimit` (cai para `bevel` acima do limite)
- [ ] Teste: segmento horizontal de `(0,0)` a `(10,0)` com largura 4 e cap `butt` → retângulo `(0,-2,10,4)`; com cap `square` → `(-2,-2,14,4)`
- [ ] Teste: ângulo reto com `miter` tem o canto esperado; com `miterLimit = 1`, vira `bevel`
- [ ] Build e testes passam

#### US-036: `Stroker` — tracejado
**Description:** Como usuário da API, quero linhas tracejadas.

**Acceptance Criteria:**
- [ ] `StrokeStyle` aceita `dashPhase` e `dashLengths`
- [ ] Teste: linha de 100 de comprimento com `dashLengths = [10, 10]` gera 5 segmentos de 10
- [ ] Teste: `dashPhase = 5` desloca o início do padrão
- [ ] Padrão vazio significa traço contínuo
- [ ] Build e testes passam

#### US-037: Estado de linha no `CGContext`
**Description:** Como usuário da API, quero configurar cap, join, miter e dash como na API da Apple.

**Acceptance Criteria:**
- [ ] Novos métodos públicos: `setLineCap(_:)`, `setLineJoin(_:)`, `setMiterLimit(_:)`, `setLineDash(phase:lengths:)`
- [ ] Os valores entram em `CGGraphicsState` e são salvos/restaurados por `saveGState`/`restoreGState`
- [ ] `strokePath()` grava `StrokeStyle` completo no `DrawCommand`
- [ ] Testes com `RecordingRenderTarget` para cada setter
- [ ] Build e testes passam

#### US-038: Preenchimento no GL por *stencil-then-cover*
**Description:** Como usuário, quero preencher qualquer forma (côncava, com buracos, auto-interseção) corretamente.

**Acceptance Criteria:**
- [ ] `GLRenderer` preenche com *stencil-then-cover* para `winding` (INCR_WRAP/DECR_WRAP) e `evenOdd` (INVERT)
- [ ] Sem limite de vértices (o limite de 16 deixa de existir)
- [ ] O pedido de contexto OpenGL inclui buffer de stencil
- [ ] Retângulos e polígonos convexos continuam no caminho rápido de 2 triângulos
- [ ] **Visual:** o Sample (modo de teste, ver US-040) mostra uma estrela de 5 pontas com `winding` (pentágono central preenchido) e com `evenOdd` (pentágono central vazio)
- [ ] Build e testes passam

#### US-039: Traço no GL
**Description:** Como usuário, quero que `stroke` desenhe só a linha, com a largura pedida.

**Acceptance Criteria:**
- [ ] `strokePath` usa o `Stroker` e preenche o contorno resultante
- [ ] `glLineWidth` não é mais usado
- [ ] A cor do traço usa `strokeColor`, e a do preenchimento usa `fillColor`
- [ ] **Visual:** retângulo com `lineWidth = 8` mostra só a moldura, com o interior transparente
- [ ] Build e testes passam

#### US-040: Elipses e segmentos de linha no contexto
**Description:** Como usuário da API, quero elipses e segmentos funcionando.

**Acceptance Criteria:**
- [ ] `fillEllipse(in:)` e `strokeEllipse(in:)` aplicam o mesmo tratamento de coordenadas (hoje `strokeEllipse` é vazio em uma cópia e converte em outra)
- [ ] `strokeLineSegments(between:)` desenha cada par de pontos como uma linha separada (hoje vazio)
- [ ] Teste de gravação: `strokeLineSegments` com 4 pontos gera 2 segmentos
- [ ] **Visual:** o Sample mostra uma elipse preenchida, uma elipse só com borda e duas linhas separadas
- [ ] Build e testes passam

---

### Fase 4 — Imagens

#### US-041: `CGImage` como dado e carregamento seguro
**Description:** Como usuário da API, quero carregar imagens de arquivo sem travar o programa e sem depender de OpenGL.

**Acceptance Criteria:**
- [ ] `CGImage.init(url:)` passa a ser `init?` (retorna `nil` se o arquivo não existir ou não puder ser decodificado), sem `fatalError`
- [ ] Nenhuma chamada OpenGL em `CGImage`; `id` e `defer { glDeleteTextures }` removidos
- [ ] Decodifica com `stb_image` e converte para RGBA 8 bits (1, 2, 3 ou 4 canais), com `alphaInfo` e `bitmapInfo` preenchidos
- [ ] Os bytes são copiados para `Data` e o ponteiro do `stb_image` é liberado sem ficar guardado em `CGDataProvider.info`
- [ ] Testes com BMPs de 1×1 e 2×2 criados em `Tests/OpenCoreGraphicsTests/Resources/`, e com arquivo inexistente (retorna `nil`)
- [ ] Build e testes passam

#### US-042: `GLTextureCache`
**Description:** Como desenvolvedor, quero criar a textura uma vez por imagem e reaproveitá-la.

**Acceptance Criteria:**
- [ ] `GLTextureCache` (`@MainActor`) devolve um `GLTexture` por identidade de `CGImage` (criada no primeiro uso)
- [ ] `GLTexture` libera o recurso em `isolated deinit`; o cache oferece `evict(_:)`
- [ ] Formato (`GL_RGBA`, `GL_RGB`, `GL_RED`) escolhido pelos canais da imagem, não pelo espaço de cor
- [ ] Teste da lógica de cache com *loader* falso: duas chamadas com a mesma imagem criam 1 textura
- [ ] Build e testes passam

#### US-043: `draw(_:in:byTiling:)` respeita o retângulo
**Description:** Como usuário, quero a imagem desenhada exatamente no retângulo pedido.

**Acceptance Criteria:**
- [ ] A imagem é desenhada no retângulo (em espaço de usuário, com CTM) usando o programa `image/`
- [ ] `interpolationQuality` escolhe o filtro (`.none` → vizinho mais próximo; demais → linear) e `byTiling` repete a imagem
- [ ] Sem recriar VAO/VBO/textura a cada chamada
- [ ] **Visual:** o Sample desenha uma imagem 64×64 em `CGRect(x: 300, y: 300, width: 128, height: 128)` com a orientação correta (não invertida)
- [ ] Build e testes passam

---

### Fase 5 — Backend de software (bitmap sem OpenGL)

#### US-044: `PixelSurface`
**Description:** Como desenvolvedor, quero um buffer de pixels que possa usar memória do chamador ou alocar a sua.

**Acceptance Criteria:**
- [ ] `struct PixelSurface` com `width`, `height`, `bytesPerRow` e armazenamento próprio (alocado, liberado no `deinit`) ou emprestado (ponteiro do chamador, não liberado)
- [ ] Suporta RGBA8 `premultipliedLast`, BGRA8 `premultipliedFirst` + `byteOrder32Little`, e variantes opacas `noneSkipLast`/`noneSkipFirst`
- [ ] Leitura e escrita de pixel em `(x, y)` respeitando `bytesPerRow`
- [ ] Teste: superfície 4×4 emprestada reflete as escritas na memória original
- [ ] Teste: um formato não suportado (por exemplo, CMYK) é rejeitado
- [ ] Build e testes passam

#### US-045: `CGContext(data:…)` e `makeImage()` reais
**Description:** Como usuário da API, quero um contexto bitmap que renderize na memória.

**Acceptance Criteria:**
- [ ] `CGContext.init(data:width:height:bitsPerComponent:bytesPerRow:space:bitmapInfo:)` passa a `init?`: retorna `nil` para formato, `bytesPerRow` ou tamanho inválidos
- [ ] Com `data == nil` aloca memória; com ponteiro, usa-o sem ser dono
- [ ] `bytesPerRow == 0` com `data == nil` é calculado automaticamente
- [ ] `makeImage()` devolve um `CGImage` com **cópia** dos pixels; `data`, `width`, `height`, `bytesPerRow`, `bitsPerPixel` e `alphaInfo` refletem a superfície
- [ ] Testes para inicialização válida, inválida, ponteiro do chamador e `makeImage()`
- [ ] Build e testes passam

#### US-046: `SoftwareRenderer` — retângulos e composição *source-over*
**Description:** Como usuário, quero retângulos coloridos em um bitmap sem OpenGL.

**Acceptance Criteria:**
- [ ] `SoftwareRenderer` implementa `CGRenderBackend`, sem importar `OpenGLAD`/`OpenGLFW` e sem isolamento de ator
- [ ] `fillPath` de retângulo alinhado aos pixels preenche exatamente esses pixels
- [ ] Composição *source-over* pré-multiplicada: vermelho `(1,0,0)` com alfa 0,5 sobre branco opaco produz `(255, 128, 128, 255)` com tolerância ±1
- [ ] `clear(_:)` zera os pixels do retângulo (transparente)
- [ ] `BitmapRenderTarget` conecta `CGContext` ao `SoftwareRenderer`
- [ ] Testes de pixel exatos em superfície 8×8
- [ ] Build e testes passam

#### US-047: `ScanlineRasterizer` com anti-aliasing e regras de preenchimento
**Description:** Como usuário, quero formas arbitrárias suaves no bitmap.

**Acceptance Criteria:**
- [ ] Rasteriza polígonos achatados por *scanline*, com amostragem 4×4 (16 níveis de cobertura)
- [ ] Respeita `winding` e `evenOdd`
- [ ] Teste: círculo de raio 8 em superfície 20×20 tem o pixel central totalmente coberto (255) e um pixel de borda com cobertura intermediária
- [ ] Teste: estrela de 5 pontas difere entre `winding` e `evenOdd` no pentágono central
- [ ] Teste parametrizado de ambas as regras
- [ ] Build e testes passam

#### US-048: Traço e clip no software
**Description:** Como usuário, quero traços e recortes no bitmap.

**Acceptance Criteria:**
- [ ] `strokePath` usa o `Stroker` compartilhado e o `ScanlineRasterizer`
- [ ] Máscara de cobertura (`CoverageMask`, 8 bits por pixel) para clip; `clip` interseta com a máscara atual; a máscara faz parte do `CGGraphicsState`
- [ ] Teste: traço horizontal de largura 4 sobre linha inteira cobre 4 linhas de pixels
- [ ] Teste: com clip `(0,0,4,4)`, preencher 8×8 só altera o quadrante 4×4
- [ ] `restoreGState` restaura o clip anterior
- [ ] Build e testes passam

#### US-049: Imagens e modos de blend no software
**Description:** Como usuário, quero desenhar imagens e usar `CGBlendMode` no bitmap.

**Acceptance Criteria:**
- [ ] `drawImage` amostra a imagem pela inversa da CTM; `interpolationQuality .none` usa vizinho mais próximo, os demais usam bilinear; `byTiling` repete
- [ ] Todos os `CGBlendMode` separáveis implementados (`normal`, `multiply`, `screen`, `overlay`, `darken`, `lighten`, `colorDodge`, `colorBurn`, `softLight`, `hardLight`, `difference`, `exclusion`, `clear`, `copy`, `sourceIn`, `sourceOut`, `sourceAtop`, `destinationOver`, `destinationIn`, `destinationOut`, `destinationAtop`, `xor`, `plusDarker`, `plusLighter`)
- [ ] Os modos não separáveis (`hue`, `saturation`, `color`, `luminosity`) ficam documentados como não suportados nesta fase e retornam `normal`
- [ ] Teste parametrizado: para cada modo suportado, o resultado de um par de cores de referência bate com a fórmula, com tolerância ±1
- [ ] Teste de imagem 2×2 ampliada para 4×4 com vizinho mais próximo
- [ ] Build e testes passam

#### US-050: Exportação BMP e imagens de referência
**Description:** Como desenvolvedor, quero gravar o bitmap em arquivo e comparar com referências nos testes.

**Acceptance Criteria:**
- [ ] Codificador BMP interno: 32 bits, `BITMAPV4HEADER`, alfa **não** pré-multiplicado (converte a partir do `PixelSurface`), linhas de cima para baixo
- [ ] Teste de ida e volta: exportar uma superfície 4×4, ler com `stb_image` e comparar pixel a pixel
- [ ] Função de teste que compara um bitmap renderizado com um BMP de referência em `Tests/OpenCoreGraphicsTests/Resources/` e retorna a diferença média por canal
- [ ] Pelo menos 3 referências (retângulo semitransparente, círculo, estrela com `evenOdd`), com 64×64
- [ ] Build e testes passam

#### US-051: Exibir o bitmap na janela
**Description:** Como desenvolvedor, quero ver o resultado do software dentro de uma `CGWindow`.

**Acceptance Criteria:**
- [ ] `WindowRenderTarget` aceita enviar um `PixelSurface` como textura e desenhar um quad de tela cheia com o programa `image/`
- [ ] Reutiliza `GLTextureCache` (sem criar textura a cada frame; apenas atualiza o conteúdo)
- [ ] **Visual:** o Sample, em modo "software", mostra na janela os mesmos retângulos e a mesma elipse renderizados pelo `SoftwareRenderer`
- [ ] Build e testes passam

#### US-052: Comparação GL × software
**Description:** Como mantenedor, quero detectar divergência visual entre os dois backends.

**Acceptance Criteria:**
- [ ] Teste de integração **opcional**, habilitado por variável de ambiente (`.enabled(if:)`), que renderiza a mesma cena nos dois backends e compara por tolerância
- [ ] Cenas: retângulo sólido, elipse, estrela `evenOdd`, traço com `round` join, imagem
- [ ] Diferença média por canal ≤ 2/255 para formas sólidas; o limite para curvas é fixado ao final desta story e registrado na ADR 0002 (ver Q-3)
- [ ] Sem execução em CI (fora de escopo por ora)
- [ ] Build e testes passam

---

### Fase 6 — Qualidade visual

#### US-053: Clipping (API pública) nos dois backends
**Description:** Como usuário da API, quero recortar o desenho por retângulo ou caminho.

**Acceptance Criteria:**
- [ ] Novos métodos `clip(to rect: CGRect)`, `clip(using rule:)` (usa o caminho atual) e `resetClip()`/`boundingBoxOfClipPath` conforme a API Apple
- [ ] GL: retângulo → `glScissor`; caminho → bit separado do *stencil*
- [ ] Software: usa `CoverageMask` (US-048)
- [ ] `saveGState`/`restoreGState` restauram o clip nos dois backends
- [ ] **Visual:** o Sample recorta um retângulo grande por uma elipse e só a interseção aparece
- [ ] Build e testes passam

#### US-054: Anti-aliasing no GL (MSAA)
**Description:** Como usuário, quero bordas suaves na janela.

**Acceptance Criteria:**
- [ ] A janela pede MSAA 4× (`GLFW_SAMPLES`) e habilita `GL_MULTISAMPLE`
- [ ] Se o driver não suportar, a janela continua funcionando sem MSAA (sem `fatalError`)
- [ ] **Visual:** a borda de uma elipse no Sample não mostra "escadas" evidentes
- [ ] Build e testes passam

#### US-055: Blend pré-multiplicado e `CGBlendMode` no GL
**Description:** Como usuário, quero o mesmo alfa e blend do software também no OpenGL.

**Acceptance Criteria:**
- [ ] Pipeline GL usa blend pré-multiplicado (`ONE, ONE_MINUS_SRC_ALPHA`); as cores são pré-multiplicadas antes do envio
- [ ] `CGBlendMode` mapeado para equações de blend do OpenGL; os modos sem equivalente direto estão documentados em uma tabela em `.docs/` e recaem em `normal`
- [ ] Teste da tabela de mapeamento (sem GL): cada `CGBlendMode` tem uma entrada
- [ ] **Visual:** o Sample mostra um retângulo vermelho semitransparente sobre um azul, com `normal` e `multiply`
- [ ] Build e testes passam

#### US-056: Conversão de cor sRGB ↔ linear em um único ponto
**Description:** Como desenvolvedor, quero uma única função de conversão usada pelos dois backends.

**Acceptance Criteria:**
- [ ] Função interna `CGColor.converted(to: CGColorSpace)` para `sRGB` ↔ `genericRGBLinear`
- [ ] `GL_FRAMEBUFFER_SRGB` configurado de forma consistente e documentado
- [ ] Teste: `0.5` em sRGB ≈ `0.2140` linear e o inverso, tolerância 0,001
- [ ] GL e software chamam a mesma função
- [ ] Build e testes passam

#### US-057: Sombras
**Description:** Como usuário da API, quero sombras projetadas.

**Acceptance Criteria:**
- [ ] `setShadow(offset:blur:color:)` e `setShadow(offset:blur:)` entram no `CGGraphicsState`
- [ ] Software: sombra por deslocamento + desfoque gaussiano da máscara de cobertura
- [ ] GL: sombra por passe adicional (desfoque separável em FBO) ou, se inviável, aviso documentado e `normal` sem sombra
- [ ] Teste de software: com `offset (4,4)` e `blur 0`, o pixel `(x+4, y+4)` da forma recebe a cor da sombra
- [ ] **Visual:** o Sample mostra um retângulo com sombra
- [ ] Build e testes passam

#### US-058: Gradientes lineares e radiais
**Description:** Como usuário da API, quero gradientes de duas ou mais cores.

**Acceptance Criteria:**
- [ ] Tipo `CGGradient` (cores e posições) e métodos `drawLinearGradient(_:start:end:options:)` e `drawRadialGradient(_:startCenter:startRadius:endCenter:endRadius:options:)` (ver Q-4 sobre o nome)
- [ ] Software: interpolação por pixel
- [ ] GL: programa novo em `Resources/gradient/` com *uniforms* de pontos e cores
- [ ] Teste de software: gradiente linear preto→branco em 11 pixels dá `0, 26, 51, …, 255` (tolerância ±1)
- [ ] **Visual:** o Sample mostra um gradiente linear horizontal e um radial
- [ ] Build e testes passam

#### US-059: Cobertura global ≥ 80 %
**Description:** Como mantenedor, quero atingir a meta do projeto.

**Acceptance Criteria:**
- [ ] `swift test --enable-code-coverage` mostra cobertura de linhas **≥ 80 %** em todo o target `OpenCoreGraphics`, **excluindo** apenas arquivos de `Rendering/GL/` e `CGWindow.swift` (exigem GPU)
- [ ] Resultado registrado em `.docs/tasks/coverage.md`, com data
- [ ] Build e testes passam

---

### Fase 7 — Texto

#### US-060: `CGFont` carrega fonte TrueType e mede glifos
**Description:** Como usuário da API, quero carregar uma fonte `.ttf` e obter métricas.

**Acceptance Criteria:**
- [ ] `CGFont.init?(_:)` retorna `nil` para arquivo inexistente ou inválido, sem `print`
- [ ] Usa `stb_truetype` para inicializar a fonte; expõe `glyph(for: Character) -> CGGlyph?`, `advance(for:)` e `unitsPerEm`
- [ ] Teste com uma fonte pequena incluída em `Tests/OpenCoreGraphicsTests/Resources/`: o avanço de `"A"` é maior que zero e `glyph(for: "A")` não é `nil`
- [ ] Build e testes passam

#### US-061: Atlas de glifos e `showGlyphs` no software
**Description:** Como usuário, quero texto desenhado em bitmaps.

**Acceptance Criteria:**
- [ ] Rasteriza glifos com `stb_truetype` (`stbtt_BakeFontBitmap` ou equivalente) em um atlas de 8 bits, usado como máscara de cobertura
- [ ] `showGlyphs(_:at:)` grava `DrawCommand.glyphs` e o `SoftwareRenderer` o executa respeitando `fontSize`, `characterSpacing`, `textMatrix` e `textPosition`
- [ ] `CGTextDrawingMode`: `fill` suportado; `stroke`, `fillStroke` e `clip` documentados como não suportados nesta fase (retornam `fill`)
- [ ] Teste de pixel: desenhar `"I"` em 20 px produz pixels não vazios apenas dentro do retângulo esperado
- [ ] Build e testes passam

#### US-062: `showGlyphs` no GL
**Description:** Como usuário, quero texto na janela.

**Acceptance Criteria:**
- [ ] Atlas enviado como textura (`GL_RED`) pelo `GLTextureCache`; programa novo em `Resources/text/`
- [ ] Glifos agrupados em lote no `GLBatchBuffer`
- [ ] **Visual:** o Sample mostra a frase "OpenCoreGraphics" em 24 px, legível, com a linha de base na posição pedida
- [ ] Build e testes passam

---

## 5. Requisitos Funcionais

### Build, pacote e qualidade
- **FR-1:** O pacote deve compilar com `swift build` e passar em `swift test` em macOS.
- **FR-2:** As dependências devem estar fixadas por revisão e o `Package.resolved` deve ser versionado.
- **FR-3:** Os shaders GLSL devem ficar em `Sources/OpenCoreGraphics/Resources/` e ser carregados por `Bundle.module`.
- **FR-4:** A cobertura de linhas deve ser ≥ 80 % (exceto arquivos que exigem GPU).

### Núcleo (`CGContext`)
- **FR-5:** Deve existir um único `CGContext`; `CGWindowContext` é apenas um `typealias` *deprecated*.
- **FR-6:** `CGContext` deve manter uma pilha de `CGGraphicsState` com `saveGState`/`restoreGState` funcionais.
- **FR-7:** Os métodos de desenho do `CGContext` devem gravar `DrawCommand`, sem chamar OpenGL.
- **FR-8:** Todos os métodos de caminho do contexto devem aplicar a CTM.
- **FR-9:** O espaço de dispositivo deve ser em pixels, com origem no canto inferior esquerdo.
- **FR-10:** A composição da CTM deve ser `ctm = transform × ctm` em todos os métodos.
- **FR-11:** O contexto deve suportar `lineWidth`, `lineCap`, `lineJoin`, `miterLimit` e `lineDash`.

### Caminhos e geometria
- **FR-12:** `CGPath.closeSubpath` deve levar o ponto atual ao início do subcaminho.
- **FR-13:** `CGPath` deve calcular `boundingBox`, `boundingBoxOfPath`, `copy`, `copy(using:)` e `contains`.
- **FR-14:** `CGPath.addArc` deve respeitar `clockwise` e usar curvas Bézier.
- **FR-15:** `PathFlattener` deve achatar curvas com tolerância configurável (padrão 0,25 px).
- **FR-16:** `Stroker` deve gerar contornos com caps, joins, limite de miter e tracejado.
- **FR-17:** `CGAffineTransform` deve manter a matriz 4×4 e expor `a, b, c, d, tx, ty`.

### Backend OpenGL
- **FR-18:** O `GLRenderer` deve ser `@MainActor` e compilar cada programa uma só vez.
- **FR-19:** O preenchimento no GL deve usar *stencil-then-cover* para `winding` e `evenOdd`.
- **FR-20:** O traço no GL deve usar o contorno gerado pelo `Stroker`.
- **FR-21:** O GL deve acumular vértices em lotes por estado.
- **FR-22:** Recursos GL (`GLProgram`, `GLTexture`, `GLBatchBuffer`) devem ser liberados com `isolated deinit`.
- **FR-23:** `GLFWPlatform` deve contar referências para `glfwInit`/`glfwTerminate`.
- **FR-24:** A janela deve usar o título informado, tratar redimensionamento e retornar erros tipados em vez de `fatalError`.
- **FR-25:** Nenhuma chamada `glad_*` pode existir fora de `Rendering/GL/` e `CGWindow.swift`.

### Imagens
- **FR-26:** `CGImage.init(url:)` deve ser falível, converter 1–4 canais para RGBA e não usar OpenGL.
- **FR-27:** `GLTextureCache` deve criar uma textura por imagem e reaproveitá-la.
- **FR-28:** `draw(_:in:byTiling:)` deve respeitar retângulo, CTM, `interpolationQuality` e repetição.

### Backend de software
- **FR-29:** `CGContext(data:…)` deve ser falível e renderizar na memória do chamador ou em memória própria.
- **FR-30:** O `SoftwareRenderer` deve funcionar sem OpenGL, em qualquer thread, com RGBA8/BGRA8 pré-multiplicado e variantes opacas.
- **FR-31:** O rasterizador deve oferecer anti-aliasing 4×4 e as regras `winding` e `evenOdd`.
- **FR-32:** O software deve suportar clip por máscara, traço, imagens e os `CGBlendMode` separáveis.
- **FR-33:** `makeImage()` deve devolver uma cópia dos pixels.
- **FR-34:** Deve existir exportação BMP 32 bits, usada pelos testes de referência.
- **FR-35:** O bitmap em software deve poder ser exibido em uma `CGWindow`.

### Qualidade visual e texto
- **FR-36:** Clipping deve funcionar nos dois backends e ser restaurado por `restoreGState`.
- **FR-37:** O GL deve usar MSAA quando disponível, com blend pré-multiplicado.
- **FR-38:** A conversão sRGB ↔ linear deve ter uma única implementação compartilhada.
- **FR-39:** Devem existir sombras e gradientes linear e radial.
- **FR-40:** `CGFont` deve carregar `.ttf`; `showGlyphs` deve funcionar nos dois backends (modo `fill`).

---

## 6. Não-Objetivos (fora de escopo)

- Eventos de janela (teclado, mouse, `CGEvent` além do que existe). Prioridade é renderizar.
- Contextos PDF e de impressão.
- Gerenciamento de cor ICC completo e `CGColorRenderingIntent` efetivo.
- Modos de blend não separáveis (`hue`, `saturation`, `color`, `luminosity`).
- Modos de texto `stroke`, `fillStroke` e `clip`; *shaping* de texto, ligaduras e *hinting* idêntico ao CoreText.
- Janela sem OpenGL (Win32/X11 nativos).
- Integração contínua (CI), em qualquer plataforma.
- Suporte a Swift anterior ao 6.4.
- Renomear o prefixo `CG` dos tipos.
- Redução de `CGAffineTransform` para 3×3 ou evolução da API 3D.
- Exportação em PNG e alteração do repositório `OpenSTB`.
- Resultados idênticos pixel a pixel aos da Apple; paridade é "melhor esforço".
- Adoção de `defaultIsolation(MainActor.self)` no pacote.
- Remoção do `typealias CGWindowContext` (fica *deprecated*).

---

## 7. Considerações de Design

- **Camadas (ADR 0001, seção 6.2):** 1 Valores → 2 Núcleo (`CGContext`, estado, comandos) → 3 Geometria de render → 4 Backends (`GLRenderer`, `SoftwareRenderer`) → 5 Plataforma (`CGWindow`, `GLFWPlatform`). Cada camada só depende das inferiores; as camadas 1–3 e o `SoftwareRenderer` não importam OpenGL.
- **Estrutura de pastas sugerida:**
  - `Sources/OpenCoreGraphics/Rendering/` — `DrawCommand`, `CGRenderTarget`, `CGRenderBackend`, `PathFlattener`, `Stroker`
  - `Sources/OpenCoreGraphics/Rendering/GL/` — `GLRenderer`, `GLShaderCache`, `GLProgram`, `GLBatchBuffer`, `GLTextureCache`, `GLTexture`
  - `Sources/OpenCoreGraphics/Rendering/Software/` — `SoftwareRenderer`, `PixelSurface`, `CoverageMask`, `ScanlineRasterizer`, codificador BMP
  - `Sources/OpenCoreGraphics/Resources/{default,image,gradient,text}/`
- **Reuso:** manter `CGPoint`, `CGSize`, `CGRect`, `CGVector`, `CGColor`, enums existentes e a API pública de `CGContext`.
- **Modelo de execução:** o `CGContext` grava comandos; `flush()` os executa no backend do seu alvo. Janela → `GLRenderer`; bitmap → `SoftwareRenderer`.
- **Diagramas:** ver as seções 4.2, 4.3, 6.3 e 6.4 da ADR 0001 e as seções 4.1 e 4.2 da ADR 0002.

## 8. Considerações Técnicas

- **Swift 6.4**, OpenGL 3.3 Core via OpenGLAD; OpenGLFW para janela; OpenSTB para `stb_image` e `stb_truetype`.
- **Concorrência:** todo OpenGL no `MainActor`; o resto sem isolamento; valores `Sendable`; `isolated deinit` para recursos GL. Seguir `/swift-concurrency-pro`.
- **Testes:** Swift Testing (`@Suite`, `@Test(arguments:)`, `#expect`, `#require`, `withKnownIssue`), seguindo `/swift-testing-pro`. Testes que exigem GPU ficam opcionais, via `.enabled(if:)`.
- **Dependência externa de plataforma:** OpenGL no macOS está limitado à 4.1 e é *deprecated*; o alvo continua 3.3 Core. macOS é ambiente de desenvolvimento.
- **Resources:** `Bundle.module` com `.copy("Resources")`; validar manualmente em Windows e Linux (sem CI).
- **Colisão de nomes:** `CGPoint`, `CGRect`, `CGContext` etc. coexistem com `CoreGraphics`/`Foundation` no macOS; qualificar com `OpenCoreGraphics.` quando houver ambiguidade.
- **Riscos:** divergência visual GL × software (mitigada por comandos e geometria compartilhados); *stencil*/MSAA variam por driver; formatos de bitmap limitados; ponteiro emprestado do chamador deve viver mais que o `CGContext`.

---

## 9. Métricas de Sucesso

| Métrica | Meta | Como medir |
|---|---|---|
| Build e testes | 100 % verdes em macOS | `swift build && swift test` |
| Cobertura de linhas | ≥ 80 % (sem GL/janela) | `swift test --enable-code-coverage` |
| Duplicação de contexto | 1 implementação de `CGContext` | `find Sources -name 'CG*Context*.swift'` |
| OpenGL fora da camada GL | 0 arquivos | `grep -rln "glad_" Sources` |
| Programas compilados por renderer | 1 por `ShaderKind` | Teste do `GLShaderCache` |
| Sample | Mostra retângulos, elipse, traço, imagem, gradiente e texto corretamente | Verificação visual |
| Bitmap sem GL | Renderiza em memória, sem janela | Testes de pixel do `SoftwareRenderer` |
| Diferença GL × software | ≤ 2/255 por canal (formas sólidas) | Teste opcional da US-052 |
| Avisos de concorrência | 0 | `swift build` |

---

## 10. Questões em Aberto

- **Q-1:** Qual versão mínima de macOS declarar em `platforms`? (a US-005 usa `.macOS(.v13)` provisoriamente).
- **Q-2:** Quando remover o `typealias CGWindowContext` *deprecated*?
- **Q-3:** Qual o limite de diferença GL × software para curvas anti-aliased? (a US-052 define na execução).
- **Q-4:** A ADR 0001 chama os gradientes de "`CGShading` real", mas na API da Apple o gradiente é `CGGradient` (e `CGShading` é outro tipo). Seguimos `CGGradient` como na US-058?
- **Q-5:** Fonte de teste (`.ttf`) para a US-060: qual fonte com licença livre incluir em `Tests/…/Resources/`?
- **Q-6:** O GL deve suportar `shouldAntialias`/`setShouldAntialias` por contexto, como na API da Apple? (hoje fora de escopo).
- **Q-7:** Resolução e tamanho de janela padrão do Sample (a US-026 usa 512×512).

# Fronteiras de concorrência da renderização

O bitmap e a janela compartilham a API síncrona de `CGContext`, mas não o
contrato de execução do backend:

- `BitmapRenderTarget`, `SoftwareRenderer` e `CGRenderBackend` não exigem
  `MainActor`. Uma instância mutável de `CGContext` ou de seu armazenamento
  não deve ser acessada simultaneamente; bitmaps independentes podem renderizar
  em tarefas independentes.
- `CGWindow`, `WindowRenderTarget`, `CGWindowRenderBackend`,
  `CGPixelSurfaceRenderer`, `CGPixelReadbackRenderer` e `GLRenderer` são
  isolados ao `MainActor`. As chamadas ao backend de janela, apresentação e
  leitura são verificadas pelo compilador. A seleção do contexto OpenGL
  proprietário continua sendo uma operação separada, feita pelo destino antes
  da execução; isolamento de ator, por si só, não seleciona um contexto GL.
- A conformidade de `WindowRenderTarget` com `CGRenderTarget` mantém uma
  ponte síncrona não isolada, necessária porque `CGContext` expõe operações
  síncronas não isoladas e também atende bitmaps. `size`, `submit`,
  `readPixels`, `flush` e `setClipRegions` usam as verificações de runtime
  preexistentes `MainActor.assumeIsolated`: o chamador já deve estar no
  executor do `MainActor`, caso contrário a chamada pode falhar em runtime.
  Essas verificações não agendam trabalho nem fornecem garantia estática na
  chamada pública de `CGContext`. Operações de clip podem atravessar a ponte
  antes de `flush`; a exigência não se limita à apresentação. Uma garantia
  estática integral exigiria alterar a API síncrona pública ou separar sua
  representação pública, o que requer decisão específica de compatibilidade.

`DrawCommand`, `CGImageSnapshot`, `CGGlyphAtlas` e `CGGraphicsState` são
valores `Sendable` verificados pelo compilador. O snapshot da imagem copia
os bytes inclusive quando o `Data` original usa armazenamento externo sem
cópia; o atlas constrói seu próprio buffer. A captura ainda exige que a origem
não seja modificada simultaneamente durante a cópia. `CGContext`, `CGImage`,
`CGDataProvider` e `CGFont` não recebem garantia `Sendable` por isso.

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

## Conteúdo de imagem e texturas

Cada desenho copia todos os bytes do `Data` do provider, inclusive memória
externa usada por `Data(bytesNoCopy:)`. O cache mantém o último snapshot
enviado por identidade e compara os bytes e metadados completos, sem depender
de versão nem de hash: alterações via atribuição, operações mutantes de
`Data` ou escrita na memória externa são detectadas na próxima captura.
`info` não é fonte de pixels. Uma atualização malsucedida não altera o
snapshot registrado; dados ausentes ou inválidos continuam sujeitos aos erros
existentes do carregador.

A cópia e, para conteúdo igual, a comparação custam O(n) por desenho, com
armazenamento adicional O(n) para cada último snapshot e também para
comandos pendentes; o custo não foi medido. O cache não tem orçamento de
memória nesta etapa. Não há upload quando o conteúdo e os metadados não
mudam. Antes de modificar uma textura, o renderer executa o lote anterior;
assim, comandos pendentes com versões diferentes mantêm sua ordem. A origem
externa deve permanecer válida e não pode ser escrita simultaneamente à
captura; este mecanismo não sincroniza acesso concorrente.

## Evidência automatizada das fronteiras

`RenderingConcurrencyTests` parte do `MainActor` e cria duas tarefas
estruturadas. Cada tarefa executa uma função `@concurrent`, cria e renderiza
seu próprio bitmap e devolve somente os bytes; os resultados vermelho e verde
são verificados separadamente. Isso demonstra o uso independente, não a
segurança de acessos simultâneos a uma mesma instância mutável.

`WindowRenderTargetTests` exercita `CGContext` e um backend de janela de
teste no `MainActor`, incluindo clip antes de `flush`. Em macOS e Linux,
testes de saída verificam em processos filhos que chamadas não isoladas de
`flush` e de substituição de clip no destino de janela falham fora do ator.
Cada filho cria seu próprio destino no `MainActor` e não transfere um
`CGContext`; um marcador confirma que a chamada foi alcançada. No macOS
também se verifica o sinal `SIGTRAP`; no Linux verifica-se apenas uma saída
malsucedida. Esses resultados comprovam o comportamento de runtime observado,
não uma garantia estática para a ponte legada nem uma troca de executor.

Os testes de saída são desabilitados quando
`OPENCOREGRAPHICS_RUN_GL_COMPARISON=1`, para não iniciar o bootstrap gráfico
do conjunto de testes nos processos filhos. Não são executados em outras
plataformas; um teste ignorado não constitui evidência de aprovação. O
backend falso não comprova funcionamento com um driver OpenGL real.

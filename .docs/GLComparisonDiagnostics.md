# Diagnóstico da comparação GL e software

## Ambiente e reprodução

Em 2026-11-10, a execução usou macOS 26.6.2, Apple M3 Pro, OpenGL `4.1 Metal - 90.5`, framebuffer de 128×128 pixels, codificação linear, `GL_FRAMEBUFFER_SRGB` desabilitado e MSAA ativo com quatro amostras. A janela foi solicitada com 64×64 pontos; a comparação usa as dimensões reais do framebuffer.

```sh
ruby scripts/run-gl-tests.rb --timeout 40
```

O executor informa o diretório de artefatos exclusivo da execução. Cada cena tem um JSON com as condições e o resultado; quando falha, os arquivos `.rgba` mantêm os pixels **originais**, antes da normalização. Um processo sem resumo final é falha de infraestrutura, não aprovação visual.

## Resultados

As diferenças são médias absolutas por canal, normalizadas para o intervalo de 0 a 1. Antes da correção, bytes lineares de GL eram comparados diretamente aos bytes sRGB do bitmap. Após a correção, o teste converte os bytes GL lineares para sRGB antes da comparação; se o framebuffer já armazenar sRGB, não converte novamente. Os limites da ADR 0002 permanecem inalterados.

| Cena | Antes | Após normalização | Limite | Resultado |
|---|---:|---:|---:|---|
| Retângulo | 0,08272059 | 0,00055147 | 2/255 | Passou |
| Elipse | 0,03866685 | 0,00068467 | 4/255 | Passou |
| Estrela `evenOdd` | 0,02738528 | 0,00144366 | 4/255 | Passou |
| Traço com join arredondado | 0,02879034 | 0,00011339 | 4/255 | Passou |
| Imagem | 0 | 0 | 2/255 | Passou |
| Interseção de clips | 0,05833273 | 0,00014648 | 4/255 | Passou |
| Glifos da fixture | 0 | 0 | 4/255 | Passou |

Para o retângulo, o interior GL continha `[229, 64, 26, 255]` e o bitmap `[243, 137, 89, 255]`; a conversão linear → sRGB explica a diferença. A imagem continha as quatro cores esperadas em ambos os buffers; os glifos produziram 140 pixels brancos em cada backend. Os testes agora também verificam que cada cena contém pixels coloridos, evitando aprovação por dois buffers pretos.

## Hipóteses verificadas e limites

- **Contexto e dimensões:** nesta execução, o contexto atual era o da janela tanto antes do desenho quanto antes da leitura; o viewport e ambos os framebuffers eram 128×128. Isso não valida a alternância entre janelas.
- **Estado de cor:** framebuffer linear com conversão sRGB desabilitada contra bitmap sRGB explicava as diferenças nas cinco cenas. Não foi necessário alterar os limites de tolerância.
- **MSAA:** quatro amostras estavam ativas. As diferenças residuais de borda permaneceram abaixo dos limites após normalizar a cor; outros drivers ou configurações ainda podem divergir.
- **Sincronização:** a leitura de cada cena foi idêntica antes e após `glFinish`; isso não demonstra ausência de problemas em outros drivers ou contextos.
- **Ciclo de vida:** o início do loop AppKit por GLFW dentro do async main encerrava o helper antes do resumo. O bootstrap exclusivo dos testes inicializa AppKit antes do async main no macOS; a execução posterior terminou com resumo e código de saída corretos.
- **Cobertura:** esta comparação usa fundo opaco; o normalizador rejeita pixels não opacos em vez de interpretar incorretamente RGB pré-multiplicado. Não certifica alpha parcial, todas as transformações de texto, múltiplas janelas ou os backends de Linux e Windows.

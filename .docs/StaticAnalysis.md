# Baseline de análise estática

Esta baseline registra a execução em macOS de 10 de novembro de 2026. Não altera
o PRD/progresso, não adiciona dependências e não configura CI para Windows/Linux.

## Swift build e testes

Toolchain observado:

- Swift 6.4.2 (`swiftlang-6.4.2.1.9`, `swift-driver` 1.168.6)
- macOS 26.0, arm64
- Swift Testing 2403

Comandos executados:

```sh
swift build -Xswiftc -strict-concurrency=complete
swift test -Xswiftc -strict-concurrency=complete
```

Ambos concluíram com código 0. O build não emitiu diagnósticos. Os testes
concluíram com **288 testes em 51 suítes aprovados**; as suítes/testes GL que
exigem opt-in/contexto gráfico foram ignorados, portanto esse resultado não é
uma validação GL real. A saída também inclui o resumo XCTest de zero testes,
seguido pelo resumo efetivo do Swift Testing (288 testes).

Como gate adicional para que avisos futuros não passem silenciosamente, também
foram executados com sucesso:

```sh
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

Assim, novas emissões de warning pelo compilador Swift causam falha em vez de
serem aceitas como baseline.

## Swift format e SwiftLint

`swift-format` 6.4.4 está instalado. Avaliação feita com:

```sh
swift-format lint --strict --recursive Sources Tests tools
```

O comando retornou 1 e encontrou 22.010 diagnósticos no código Swift do
checkout avaliado. Por esse volume, a ferramenta foi avaliada, mas não foi
adotada como gate amplo nesta história: formatar automaticamente esses
arquivos seria uma alteração extensa e não relacionada. Nenhuma regra foi
desativada e nenhum arquivo Swift foi alterado para contornar os resultados.
Uma adoção futura pode introduzir a formatação incrementalmente.

SwiftLint não está instalado (`command -v swiftlint` não encontrou executável);
nenhuma dependência foi adicionada para instalá-lo.

## Clang Static Analyzer na ponte C

Clang disponível: Apple Clang 21.0.0 (`clang-2100.3.34.1`). A ponte é analisada
com:

```sh
ruby scripts/check-clang-analyzer.rb
```

O script executa Clang Static Analyzer em
`Sources/OpenCoreGraphicsSTB/stb_truetype.c`, que inclui o header upstream
`stb_truetype.h`. A única ocorrência atual é
`deadcode.DeadStores` na linha 3180 do header upstream: a atribuição de `xb`
no swap é reportada como armazenamento não lido. É código de terceiro, não da
ponte mantida aqui. Não há diagnóstico do arquivo C próprio.

`scripts/clang-analyzer-baseline.json` permite somente essa ocorrência explícita
(arquivo, linha, coluna, severidade, check e mensagem), com contagem máxima
exata de um, identificada como `third-party`.
Qualquer diagnóstico adicional — inclusive no código próprio ou um novo
diagnóstico idêntico em outro ponto do stb — retorna código diferente de zero.
Uma nova ocorrência duplicada na mesma linha também excede a contagem permitida.
Não há supressão global; o `#pragma` local já
existente em torno da implementação stb afeta apenas `-Wshorten-64-to-32`, não
o diagnóstico do analyzer.

O teste de detecção usa um fixture negativo, sem modificar o código analisado:

```sh
ruby scripts/check-clang-analyzer.rb --self-test
```

Ele verifica que a ocorrência conhecida é aceita, que uma duplicata idêntica e
uma ocorrência deslocada para outra linha são rejeitadas, e que um formato de
diagnóstico não reconhecido falha fechado. O self-test passou.

## Limitações

- A baseline é específica à versão do Apple Clang acima; uma atualização de
  toolchain que altere a mensagem/check exige revisão explícita, não supressão.
- A linha e coluna exatas tornam a baseline deliberadamente frágil a mudanças
  no header stb: inserir linhas antes do aviso fará o gate falhar até que a nova
  localização seja revisada e aprovada na baseline. Essa fragilidade evita
  aceitar silenciosamente um novo ponto de diagnóstico.
- A análise cobre a ponte de fontes C indicada, não é uma auditoria completa de
  todas as dependências ou dos caminhos de runtime.
- O build/test nesta execução foram incrementais; as saídas não mostraram
  avisos do compilador Swift. Não se afirma que os testes GL opt-in foram
  validados.

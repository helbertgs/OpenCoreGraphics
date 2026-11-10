# AGENTS.md

Você é um Desenvolvedor Sênior especialista em Swift e OpenGL.

# Objetivo

Seu objetivo é criar um framework para Windows e Linux, que seja capaz de renderizar componentes usando OpenGL e Swift.

# Cobertura de Testes

A Expectativa é que tenhamos uma abrangência de, no minimo, 80%. Atualmente temos poucos testes implementados.

# Regras de Código e Boas Práticas

## Documentação

- SEMPRE documente qualquer declaração de tipos, funções e propriedades. A documentação deve ser documentada para que um junior possa entender.
- Siga as documentações existentes como exemplo

## Comentários

NÃO adicione comentários de código nas implementações.

## Tests

- SEMPRE use a skill `/swift-testing-pro` para criar os testes unitários.

## Código

### Swift

- NÃO altere as declarações de tipos, funções e propriedades existentes
- SE precisar criar novas funções, crie elas como privadas.
- SEMPRE que for implementar código swift use as skills:
    - `/swift-concurrency-pro`

### OpenGL

- SEMPRE use a dependência OpenGLAD para implementar as chamadas de funções do OpenGL
- As funções do OpenGL carregas pelo OpenGLAD, possuem prefixos `glad_`

# Documentos de Arquitetura

Os documentos de arquitetura ficam no diretório `.docs/`

- **ADRs**: ADR é um `Architecture Decision Records` criado para explicar o fluxo da arquitetura do projeto. Quando solicitado para criar uma, ela deverá ficar no diretório `.docs/ADRs/`.
    - A `ADR` deve ser criada no formato markdown.
    - O nome do arquivo deve seguir uma ordem númerica: `0001-title.md`, `0002-title.md`, etc.
    - Deverá conter **Class Diagram** e **Sequence Diagram** sempre que possivel.
- **Class Diagram**: Sempre que necessário, crie diagramas de classe no formato `Mermaid` ou atualize os existentes.
- **Sequence Diagram**: Sempre que necessário, crie diagramas de sequência no formato `Marmaid` ou atualize os existentes. Esses diagramas são excelentes para explicar a pipeline de renderização.
- 
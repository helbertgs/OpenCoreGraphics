# PRD: Evolução da renderização, concorrência e qualidade

> **Origem:** [ADR 0003 — Evolução da renderização, concorrência e qualidade](../ADRs/0003-evolucao-renderizacao-concorrencia-e-qualidade.md).
> **Idioma:** Português (Brasil); identificadores de código permanecem em inglês.
> **Estado:** proposta para implementação incremental; a ADR de origem ainda está proposta.
> **Recorte solicitado:** CI para Windows e Linux está fora do escopo atual. Isso não autoriza quebrar o suporte do framework a essas plataformas.

---

## 1. Introdução

O OpenCoreGraphics possui um pipeline baseado em comandos de desenho, com renderizadores de software e OpenGL. A revisão após as US-001 a US-062 identificou riscos na propriedade dos contextos de janelas, na fronteira de concorrência, na restauração de fontes e na invalidação de texturas. Também identificou trabalho repetido na renderização de texto e lacunas na validação visual.

Este PRD transforma as propostas da ADR 0003 em histórias independentes e verificáveis. As divergências de pixels e o possível espelhamento dos glifos são **hipóteses a investigar**, não resultados já diagnosticados. A implementação deve preservar a ordem dos comandos e a API pública existente.

### Glossário

| Termo | Significado |
|---|---|
| Contexto GL atual | Contexto OpenGL associado à thread em que os comandos GL serão executados. |
| `MainActor` | Executor de Swift que serializa operações isoladas ao ator principal; não seleciona um contexto GL automaticamente. |
| Snapshot | Cópia imutável do estado necessário a um comando, preservada após mudanças no objeto de origem. |
| Atlas de glifos | Imagem que agrupa máscaras de cobertura de caracteres para reduzir o número de texturas ou uploads. |
| Invalidação | Atualização ou descarte de um item de cache quando seu conteúdo muda. |
| Readback | Leitura dos pixels de um framebuffer OpenGL para comparação ou inspeção. |
| Eviction | Remoção controlada de entradas do cache para respeitar um limite de memória. |

## 2. Objetivos

- **O1.** Desenho, resize, leitura de pixels e liberação de recursos usam o contexto GL da janela proprietária, inclusive com duas janelas.
- **O2.** A fronteira de janela informa e aplica seu isolamento; contextos de bitmap continuam utilizáveis fora do `MainActor` sem compartilhamento simultâneo da mesma instância mutável.
- **O3.** A comparação GL/software termina com resultado confiável e explica as diferenças observadas, sem aumentar tolerâncias apenas para passar.
- **O4.** A orientação de texto é comprovada com máscara assimétrica e a fonte salva no estado gráfico sobrevive à mudança ou remoção do arquivo original.
- **O5.** Imagens alteradas não usam texturas antigas; os caches respeitam limites verificáveis e a propriedade do contexto GL.
- **O6.** A otimização de glifos é decidida com medições; textos longos respeitam o limite de textura do dispositivo.
- **O7.** Build, testes, análise estática e cobertura têm critérios e escopo claros; a documentação reflete o comportamento real.

## 3. Regras comuns

Aplicam-se a todas as histórias, mesmo quando não repetidas:

- Preservar alterações locais não relacionadas; não modificar o PRD ou o progresso de histórias anteriores.
- Preservar declarações e comportamento público existentes, conforme [AGENTS.md](../../AGENTS.md). Se uma garantia exigir alterar uma declaração ou criar API pública, registrar a limitação e obter uma decisão específica antes de prosseguir; não introduzir alteração incompatível silenciosamente.
- Não introduzir dependências de terceiros sem autorização. Chamadas OpenGL usam OpenGLAD (`glad_*`); GLFW seleciona contextos e processa eventos.
- Novos testes usam Swift Testing e a skill `/swift-testing-pro`; trabalho Swift usa `/swift-concurrency-pro`. Documentar declarações novas, sem comentários de implementação.
- Executar `swift build` e `swift test`, além dos testes direcionados da história. Não contar testes ignorados ou processos sem resultado final como aprovação.
- Casos que exigem GL real são executados com sessão gráfica e driver disponível. Indisponibilidade deve ser explicitada como **bloqueio da validação**, não como sucesso.
- Uma história pode documentar uma investigação ou decisão, mas não marca implementação ou paridade como concluída apenas porque a hipótese foi registrada.

### Dependências

1. US-001 e US-002 tornam os resultados de comparação confiáveis; US-003 registra o diagnóstico inicial.
2. US-004 a US-007 estabelecem propriedade do contexto GL antes de implementar o ciclo de vida dos caches GPU.
3. US-008 a US-011 definem isolamento e estratégia de loop; US-012 implementa a opção compatível aprovada.
4. US-013 a US-016 tratam texto e estado; US-015 depende de US-002, US-003 e US-007.
5. US-017 a US-020 tratam imagens; US-021 a US-023 tratam limites e decisões de desempenho de glifos.
6. US-024 a US-027 consolidam automação, cobertura e documentação.

## 4. Histórias de usuário

### Fase 0 — Diagnóstico reproduzível

### US-001: Tornar conclusivo o executor de testes GL
**Descrição:** Como mantenedor, quero que o resultado dos testes GL não dependa apenas do código de saída do processo para detectar falhas e interrupções.

**Critérios de aceite:**
- [ ] Um executor local dedicado roda as suítes GL opt-in com tempo limite configurável e exige um resultado final explícito do teste.
- [ ] Uma falha de asserção, interrupção, timeout ou saída sem resultado final gera código de saída diferente de zero, mesmo que o processo filho retorne zero.
- [ ] Um teste que conclui com sucesso retorna zero; ambiente sem contexto gráfico retorna resultado distinto e documentado, sem ser classificado como aprovação.
- [ ] Testes automatizados do executor simulam sucesso, falha, timeout e saída incompleta, sem GPU.

### US-002: Registrar ambiente e artefatos da comparação GL
**Descrição:** Como desenvolvedor, quero reproduzir a comparação entre backends com informações suficientes para entender suas diferenças.

**Critérios de aceite:**
- [ ] O resultado registra sistema, driver/versão GL, dimensões reais do framebuffer, estado de cor, MSAA, cenário e tolerância aplicada.
- [ ] Em caso de divergência, preserva imagens ou dados de pixels de ambos os backends e um resumo da diferença; não registra dados sensíveis.
- [ ] O formato de saída distingue cenário aprovado, falho, ignorado e execução incompleta.
- [ ] A execução com GL real usa o executor da US-001 e termina com resumo verificável.

### US-003: Diagnosticar a diferença inicial GL/software
**Descrição:** Como mantenedor, quero identificar se as diferenças observadas vêm do ambiente, do readback ou dos renderizadores antes de alterar os limites de comparação.

**Critérios de aceite:**
- [ ] Reexecutar as cenas de retângulo, elipse, estrela `evenOdd`, stroke, imagem e clip com o executor conclusivo; registrar valores por cenário.
- [ ] Investigar contexto atual, dimensões, estado de cor, MSAA, sincronização e ciclo de vida; registrar o resultado de cada hipótese e sua evidência.
- [ ] Registrar separadamente falhas reproduzidas e limitações do ambiente; corrigir a infraestrutura quando identificada como causa.
- [ ] Preservar os limites da ADR 0002: diferença média absoluta ≤ 2/255 para formas sólidas/imagens e ≤ 4/255 para curvas, `evenOdd` e joins arredondados. Qualquer exceção requer justificativa por cenário e decisão documentada, não aumento silencioso.

### Fase 1 — Contexto OpenGL e concorrência

### US-004: Introduzir seleção testável do contexto por janela
**Descrição:** Como desenvolvedor, quero associar explicitamente cada janela ao seu contexto para impedir que operações sejam enviadas à janela errada.

**Critérios de aceite:**
- [ ] A seleção do contexto GLFW é centralizada em colaborador interno injetável/testável, associado à janela proprietária.
- [ ] Um driver falso registra contexto anterior, contexto selecionado e falhas; a política de restauração ou manutenção do contexto atual é documentada.
- [ ] Testes alternam A/B e verificam que cada operação seleciona o contexto solicitado, inclusive quando outro contexto já estava atual.
- [ ] Uma janela encerrada não permite operação GL sobre seu contexto; a falha é explicitada pelo mecanismo compatível existente.

### US-005: Selecionar o contexto antes de desenhar e ler pixels
**Descrição:** Como usuário de múltiplas janelas, quero desenhar e ler cada uma sem interferência da outra.

**Critérios de aceite:**
- [ ] Inicialização de recursos, execução de comandos, apresentação de superfície e readback selecionam o contexto da janela correspondente.
- [ ] Testes com driver falso verificam a sequência seleção → operação para A e B, preservando a ordem dos comandos.
- [ ] Em GL real, desenhar cores distintas em duas janelas e alternar readbacks confirma que cada framebuffer mantém sua cor.
- [ ] Testar também desenho de A após a criação de B, sem depender de chamadas prévias que tenham selecionado A.

### US-006: Selecionar o contexto nos callbacks de framebuffer
**Descrição:** Como usuário, quero redimensionar uma janela sem alterar o viewport ou clip de outra.

**Critérios de aceite:**
- [ ] O callback de framebuffer ativa o contexto da janela correspondente antes de alterar viewport e estado GL.
- [ ] Um teste simula resize de A com B atual e verifica contexto, dimensões e ordem das operações.
- [ ] Com GL real, redimensionar A não altera a área de desenho nem os pixels esperados de B.
- [ ] Estado de clip e dimensões do `CGContext` continuam coerentes após o resize.

### US-007: Liberar recursos antes de destruir o contexto
**Descrição:** Como mantenedor, quero que cada recurso GL seja liberado no contexto proprietário antes de a janela ser destruída.

**Critérios de aceite:**
- [ ] Buffers, texturas e programas são liberados com o contexto proprietário atual e antes de `glfwDestroyWindow`.
- [ ] Testes com driver falso verificam a ordem e a liberação exatamente uma vez em sucesso, erro de inicialização e destruição.
- [ ] Testes cobrem destruir A antes de B e B antes de A, incluindo contexto diferente inicialmente atual.
- [ ] Após o encerramento, nenhuma operação GL usa o contexto destruído; falhas de inicialização não vazam recursos já criados.

### US-008: Separar contratos internos de bitmap e janela
**Descrição:** Como desenvolvedor, quero que a execução da janela tenha isolamento explícito sem exigir `MainActor` do renderer de bitmap.

**Critérios de aceite:**
- [ ] Os pontos internos de execução GL e destino de janela expõem isolamento `MainActor` verificável pelo compilador, ou documentam precisamente a limitação quando a API síncrona existente impedir essa garantia.
- [ ] O caminho de bitmap permanece síncrono e não isolado ao `MainActor`; `DrawCommand` e snapshots transferidos preservam `Sendable` real.
- [ ] Não introduzir `@unchecked Sendable` nem usar `assumeIsolated` para simular uma troca de executor.
- [ ] `swift build -Xswiftc -strict-concurrency=complete` e testes direcionados passam; não alterar declarações públicas sem decisão específica.

### US-009: Testar fronteiras de concorrência
**Descrição:** Como mantenedor, quero testes que distingam uso independente de bitmap do uso isolado de janela.

**Critérios de aceite:**
- [ ] Duas tarefas independentes criam e renderizam seus próprios contextos de bitmap; seus pixels são determinísticos e independentes.
- [ ] Testes não compartilham simultaneamente a mesma instância mutável de `CGContext` ou superfície sem sincronização.
- [ ] A execução de janela é exercitada no `MainActor`; os testes cobrem o limite suportado dos caminhos legados fora dele sem tratar uma precondição de runtime como garantia estática.
- [ ] `swift test -Xswiftc -strict-concurrency=complete` passa sem novos diagnósticos de concorrência.

### US-010: Medir o loop atual da janela
**Descrição:** Como mantenedor, quero uma baseline do loop de janela para escolher uma integração cooperativa sem causar travamentos.

**Critérios de aceite:**
- [ ] Registrar procedimento reproduzível, ambiente e valores de CPU em repouso e latência de resposta a eventos.
- [ ] Registrar se uma tarefa agendada no `MainActor` progride enquanto o loop síncrono existente está ativo, com timeout que não bloqueia a suíte padrão.
- [ ] Registrar comportamento de animação, redraw, fechamento e múltiplas janelas.
- [ ] O relatório identifica limitações do ambiente sem supor que uma medida em um único computador vale para todas as plataformas.

### US-011: Definir estratégia cooperativa compatível
**Descrição:** Como mantenedor, quero escolher como integrar eventos e tarefas sem alterar silenciosamente a API existente.

**Critérios de aceite:**
- [ ] Comparar loop integrado à plataforma, atualização incremental e API aditiva assíncrona quanto a isolamento, compatibilidade, cancelamento e suporte a múltiplas janelas.
- [ ] Documentar como acordar para eventos, animação, redraw e encerramento, inclusive quando a janela está em repouso.
- [ ] Registrar a alternativa escolhida, as assinaturas afetadas e como a API síncrona existente conserva seu comportamento.
- [ ] Se nenhuma alternativa satisfizer as restrições de API, registrar o bloqueio e solicitar decisão antes de uma mudança pública; não marcar US-012 concluída por documentação apenas.

### US-012: Implementar e verificar cooperação do loop
**Descrição:** Como usuário de janela, quero que outras tarefas do ator principal progridam e que a janela responda a eventos.

**Critérios de aceite:**
- [ ] Implementar a alternativa compatível definida na US-011; manter o caminho público existente funcional.
- [ ] Em uma sessão gráfica, uma tarefa agendada no `MainActor` executa enquanto a janela está aberta; testes usam confirmação e timeout determinísticos.
- [ ] Testar animação, evento, pedido de redraw, fechamento e duas janelas sem congelamento.
- [ ] Comparar CPU em repouso e latência com a baseline da US-010; registrar resultados e eventuais regressões.

### Fase 2 — Texto e estado gráfico

### US-013: Definir convenção de orientação dos glifos
**Descrição:** Como desenvolvedor, quero uma convenção inequívoca de baseline e linhas do atlas para que os dois backends desenhem texto consistente.

**Critérios de aceite:**
- [ ] Documentar orientação do bitmap stb, origem do atlas e mapeamento de quad GL e software, inclusive acima e abaixo da baseline.
- [ ] Definir um exemplo numérico com máscara 2×3 assimétrica, seus pixels e posições esperadas.
- [ ] Cobrir `textMatrix`, `textPosition`, CTM, espaçamento, rotação e escala negativa na especificação de teste.
- [ ] Não concluir qual backend está errado sem confrontar a convenção com resultado observado.

### US-014: Corrigir e testar glifos assimétricos no software
**Descrição:** Como usuário, quero que máscaras de glifos no bitmap respeitem a orientação e a baseline definidas.

**Critérios de aceite:**
- [ ] Um teste determinístico usa máscara 2×3 assimétrica e verifica valores exatos em posições acima e abaixo da baseline.
- [ ] Testes verificam posição, espaçamento, rotação, escala negativa e CTM conforme US-013.
- [ ] Se houver divergência, corrigir o renderer de software; se não houver, registrar a evidência sem alterar o comportamento.
- [ ] Testes existentes de texto e clipping continuam passando.

### US-015: Validar glifos GL contra software
**Descrição:** Como usuário, quero texto com orientação e posição consistentes entre janela GL e bitmap.

**Critérios de aceite:**
- [ ] Verificar coordenadas UV e geometria dos quads com a máscara assimétrica da US-013.
- [ ] Em GL real, executar comparação conclusiva de texto assimétrico e baseline, com artefatos e dimensões registradas conforme US-001 e US-002.
- [ ] Corrigir o backend que divergir da convenção validada; diferenças residuais de pixels e tolerância são justificadas e registradas.
- [ ] Uma falha localizada na orientação não passa apenas porque a média global é baixa: verificar também regiões e pixels representativos.

### US-016: Preservar fonte no estado salvo
**Descrição:** Como usuário de `saveGState`, quero restaurar a fonte original mesmo se seu arquivo for alterado ou removido.

**Critérios de aceite:**
- [ ] Salvar o estado mantém acesso seguro aos dados necessários da fonte original sem reabrir o arquivo em `restoreGState()`.
- [ ] Testes usam cópia temporária da fonte, salvam o estado, alteram ou removem a cópia e confirmam que a fonte restaurada ainda desenha os mesmos pixels.
- [ ] Testar três níveis aninhados com fontes/tamanhos diferentes, ausência de fonte e restauração repetida.
- [ ] A propriedade dos dados nativos e o isolamento são documentados; não declarar `CGFont` como `Sendable` sem garantia real de segurança.

### Fase 3 — Caches e limites

### US-017: Invalidar textura quando pixels da imagem mudam
**Descrição:** Como usuário, quero que alterar os dados do provider atualize a imagem desenhada no GL.

**Critérios de aceite:**
- [ ] Snapshot de imagem distingue conteúdo alterado da mesma identidade, cobrindo todas as mutações expostas pelo provider público.
- [ ] Desenhar uma imagem, alterar seus bytes e desenhar novamente atualiza a textura; dados inalterados reutilizam a textura sem upload adicional.
- [ ] Um teste de integração compara os pixels GL e software antes e depois da alteração.
- [ ] A estratégia preserva a API pública e documenta o custo de cópia, versão ou comparação de conteúdo.

### US-018: Definir orçamento e eviction de texturas
**Descrição:** Como mantenedor, quero limitar a memória do cache de imagens para evitar crescimento indefinido.

**Critérios de aceite:**
- [ ] O cache mantém contagem de bytes e orçamento configurável internamente; a política de descarte e o comportamento de uma textura maior que o orçamento são documentados.
- [ ] Testes com driver falso verificam reutilização, ordem de eviction, orçamento respeitado e liberação exatamente uma vez.
- [ ] Eviction não libera textura referenciada por lote pendente: testar flush ou retenção antes da liberação.
- [ ] A liberação usa o contexto proprietário estabelecido na US-007; o encerramento libera as entradas restantes.

### US-019: Testar conteúdo e limites sob carga
**Descrição:** Como mantenedor, quero evidência de que o cache se mantém correto e limitado em uma sequência de frames.

**Critérios de aceite:**
- [ ] Teste determinístico usa imagens repetidas, imagens novas e alterações no provider, ultrapassando o orçamento configurado.
- [ ] Em cada etapa, verificar conteúdo esperado, número de uploads e bytes retidos; o cache não ultrapassa o orçamento fora da política explicitamente documentada para itens em uso.
- [ ] Com GL real, verificar pelo menos uma atualização e uma eviction sem corrupção visual ou erro de ciclo de vida.
- [ ] Registrar o custo e as métricas observadas, sem alegar ganho de desempenho não medido.

### US-020: Comparar estratégias de atualização de imagens
**Descrição:** Como desenvolvedor, quero medir o custo da invalidação para evitar uma solução correta, porém desnecessariamente lenta.

**Critérios de aceite:**
- [ ] Medir quantidade de cópias/comparações, uploads, tempo e memória para imagens estáticas e mutáveis em uma carga reproduzível.
- [ ] Comparar a implementação escolhida com a baseline anterior ou uma referência sem reutilização, usando os mesmos dados e ambiente.
- [ ] Registrar compromissos e limitações; nenhuma otimização pode trocar correção de pixels por desempenho.

### US-021: Medir rasterização e upload de glifos
**Descrição:** Como mantenedor, quero medir o texto estático e dinâmico antes de decidir se um cache de glifos vale o custo.

**Critérios de aceite:**
- [ ] Uma carga reproduzível mede número de rasterizações, uploads, tempo de frame e memória para texto repetido e texto que muda.
- [ ] Comparar atlas por comando, atlas paginados e cache de máscaras na CPU por métricas ou protótipo controlado; registrar ambiente e limitações.
- [ ] Registrar uma decisão explícita com base nos resultados: implementar cache limitado ou manter o desenho atual por enquanto, com justificativa e parâmetros medidos.
- [ ] A decisão não dispensa o tratamento de limite de textura da US-022.

### US-022: Respeitar o tamanho máximo do atlas GL
**Descrição:** Como usuário, quero desenhar texto longo sem depender de uma textura maior que a capacidade do dispositivo.

**Critérios de aceite:**
- [ ] Consultar `GL_MAX_TEXTURE_SIZE` no contexto proprietário e dividir ou paginar o atlas e os lotes quando necessário.
- [ ] Testes com limite GL simulado pequeno cobrem texto que exige múltiplas páginas, repetição e preservação da ordem e das posições.
- [ ] Um glifo individual que não caiba e falhas de alocação/upload produzem erro explícito pelo mecanismo compatível adotado, sem sucesso silencioso.
- [ ] Teste com GL real valida texto dividido e equivalência com software, sem exceder o limite consultado.

### US-023: Aplicar a decisão de cache de glifos
**Descrição:** Como mantenedor, quero que a estratégia de glifos reflita as medições sem comprometer pixels ou memória.

**Critérios de aceite:**
- [ ] Se a US-021 justificar cache, implementar cache limitado com chave por identidade imutável da fonte, tamanho e demais parâmetros que mudem a rasterização; cor e posição não invalidam a máscara por si só.
- [ ] Testar reutilização, fontes/tamanhos distintos, alteração da fonte, eviction por bytes, lotes pendentes e liberação no contexto proprietário.
- [ ] Medir novamente a mesma carga da US-021 e registrar rasterizações, uploads, tempo e memória antes/depois; confirmar pixels equivalentes.
- [ ] Se a decisão for não implementar cache, registrar as medições e razões e verificar que US-022 e as regressões de texto passam; não afirmar melhoria de desempenho inexistente.

### Fase 4 — Qualidade e documentação

### US-024: Estabelecer baseline de análise estática
**Descrição:** Como mantenedor, quero diagnósticos reproduzíveis de Swift e da ponte C sem esconder problemas de código próprio.

**Critérios de aceite:**
- [ ] Executar e documentar `swift build` e `swift test` com `-Xswiftc -strict-concurrency=complete`; registrar versão do toolchain e diagnósticos.
- [ ] Avaliar `swift-format`, SwiftLint quando disponível e Clang Static Analyzer na ponte C; documentar comandos e baseline.
- [ ] Distinguir avisos do código próprio e de terceiros, incluindo o aviso observado no stb; nenhuma supressão global esconde ambos.
- [ ] Não adicionar dependência nova sem autorização; verificações adotadas devem retornar falha inequívoca para diagnóstico novo fora da baseline.

### US-025: Automatizar verificações no macOS
**Descrição:** Como mantenedor, quero que verificações repetíveis sejam executadas automaticamente sem exigir GPU de todos os jobs.

**Critérios de aceite:**
- [ ] Um workflow de macOS executa build, testes padrão e verificação completa de concorrência usando toolchain compatível com o pacote.
- [ ] Publicar resumo explícito dos testes executados e ignorados e do escopo da cobertura.
- [ ] Testes GL ficam em job dedicado ou opt-in somente quando há contexto gráfico disponível; falta de GPU não aparece como comparação visual aprovada.
- [ ] Uma falha intencional de teste ou de verificação é detectada como falha do job; remover a falha de teste após a verificação.
- [ ] Não criar nem exigir workflows de CI para Windows ou Linux nesta fase.

### US-026: Medir cobertura com escopo explícito
**Descrição:** Como mantenedor, quero saber o que a porcentagem de cobertura realmente inclui para não confundir núcleo e backend GL.

**Critérios de aceite:**
- [ ] `swift test --enable-code-coverage` passa; agregar apenas fontes Swift do target `OpenCoreGraphics`, excluindo `Rendering/GL/` e `CGWindow.swift` para a meta histórica.
- [ ] O relatório registra data, comando, numerador, denominador, percentual e exclusões; a cobertura elegível é ≥ 80%.
- [ ] Registrar separadamente cobertura de GL/janela quando mensurável, incluindo testes ignorados e infraestrutura utilizada; não somar percentuais com denominadores diferentes.
- [ ] Incluir testes direcionados aos novos casos de contexto, caches, glifos e restauração de fonte.

### US-027: Atualizar documentação pública e guias
**Descrição:** Como usuário do framework, quero instruções coerentes com as APIs e limitações realmente implementadas.

**Critérios de aceite:**
- [ ] `CGFont.init?(_:)` documenta que recebe caminho de arquivo TrueType, mostra exemplo e descreve falha; não promete busca por nome PostScript.
- [ ] O README explica `--font`, execução de testes padrão e GL opt-in, pré-requisitos aplicáveis e diagnóstico de teste incompleto.
- [ ] Documentar isolamento e propriedade dos contextos, acesso exclusivo ao bitmap e vida útil dos buffers conforme implementação final.
- [ ] Vincular as limitações existentes de sombras, blend GL e gradientes; distinguir suporte, fallback e funcionalidade futura.
- [ ] Validar links e exemplos contra os comandos e caminhos reais, preservando alterações locais preexistentes.

## 5. Requisitos funcionais

- **RF-01:** cada janela deve selecionar seu próprio contexto GL para inicialização, desenho, viewport, clip, readback e destruição dos recursos.
- **RF-02:** os recursos GL devem ser liberados uma vez, antes da destruição do contexto proprietário, mesmo em inicialização parcial.
- **RF-03:** a janela deve ter fronteira `MainActor` explícita; o bitmap deve continuar utilizável fora dela, sem promessa de uso simultâneo da mesma instância.
- **RF-04:** o processamento de eventos deve permitir progresso cooperativo sem impedir redraw, animação ou fechamento, respeitando a decisão de compatibilidade da US-011.
- **RF-05:** comparações GL devem registrar ambiente e terminar com resultado explícito; falha, timeout e saída incompleta devem ser distinguíveis de sucesso.
- **RF-06:** orientação de máscaras, baseline e transformações de texto devem seguir a convenção da US-013 nos dois backends.
- **RF-07:** a restauração do estado gráfico deve preservar a fonte efetivamente salva, independentemente do arquivo de origem.
- **RF-08:** mudanças nos dados de imagem devem atualizar a textura; o cache deve ter orçamento e política de descarte testáveis.
- **RF-09:** atlas GL deve respeitar `GL_MAX_TEXTURE_SIZE`; falhas de tamanho e upload devem ser explícitas.
- **RF-10:** a decisão de cache de glifos deve ser baseada em medições; se implementado, seu uso de memória e sua identidade devem ser limitados e testáveis.
- **RF-11:** verificações automatizadas e documentação devem informar testes ignorados, pré-requisitos e escopo da cobertura.

## 6. Fora de escopo

- Workflows ou exigência de CI para Windows e Linux nesta fase; suporte e portabilidade do framework permanecem objetivos do projeto.
- Implementação de sombras GL, de todos os modos de blend GL ou de uma API de busca de fonte por nome.
- Mudanças públicas incompatíveis, novas dependências sem autorização ou reescrita integral da renderização.
- Considerar execução visual ignorada, resultado incompleto ou cobertura parcial como prova de paridade GL/software.
- Implementar cache de glifos independentemente das medições e da decisão da US-021.

## 7. Considerações técnicas e riscos

- `MainActor.assumeIsolated` não faz troca de executor; `@MainActor` não escolhe o contexto OpenGL atual. As duas garantias precisam ser tratadas separadamente.
- A ordem de comandos, os estados de clip/blend e a semântica síncrona do bitmap devem ser preservados durante refatorações.
- A ponte stb mantém ponteiros para dados da fonte: preservar os bytes e a vida útil do parser antes de considerar qualquer compartilhamento.
- O cache de imagens deve detectar alterações feitas pela API pública existente; hashing integral por frame pode ser caro e deve ser medido.
- Atlas e cache GPU devem respeitar limites do dispositivo, contexto proprietário e lotes pendentes. Não presumir que um único atlas ilimitado é seguro.
- Testes visuais podem variar com driver, MSAA e cor; usar limites justificáveis e verificações localizadas, sem ignorar falhas.
- As metas de cobertura da ADR anterior referem-se ao núcleo com exclusões; a cobertura GL/janela deve ser relatada separadamente.

## 8. Métricas de sucesso

| Métrica | Resultado esperado |
|---|---|
| Contexto de duas janelas | Desenho, resize, readback e teardown corretos nos cenários de US-005 a US-007. |
| Executor GL | Os quatro cenários sintéticos de US-001 são classificados corretamente; não há falso sucesso para saída incompleta. |
| Concorrência | Build e testes com verificação completa passam; tarefas de bitmap independentes produzem pixels esperados. |
| Glifos | Máscara assimétrica, baseline e transformações passam em software e em comparação GL conclusiva. |
| Fonte salva | Pixels após restauração são idênticos mesmo após remover ou alterar a cópia temporária do arquivo. |
| Caches | Conteúdo atualizado é correto; orçamento e eviction são demonstrados por contadores e testes de lotes pendentes. |
| Cobertura | ≥ 80% no escopo histórico explicitado, com relatório separado para GL/janela quando mensurável. |
| Desempenho | CPU em repouso, latência, rasterizações, uploads, tempo e memória são registrados antes/depois; ganhos não são presumidos. |

## 9. Questões em aberto

1. Qual estratégia de loop atende à cooperação sem mudar a API existente? Se for necessária API pública aditiva, como será aprovada?
2. Qual divisão interna de protocolos garante isolamento estático preservando `CGContext` síncrono e bitmap fora do `MainActor`?
3. Quais causas explicam as diferenças GL/software registradas na revisão de 2026-11-10 e a ausência de resumo final?
4. Qual proprietário imutável de dados da fonte e qual estratégia de versão de imagem melhor respeitam vida útil e custo?
5. Qual orçamento inicial e política de descarte são adequados para imagens e glifos após medir cargas representativas?
6. O ambiente macOS disponível para automação oferece contexto GL e readback confiáveis? Caso contrário, qual ambiente dedicado será usado?

Estas questões são resolvidas pelas histórias de diagnóstico e decisão antes das implementações dependentes. Não alteram o escopo que exclui CI de Windows e Linux.

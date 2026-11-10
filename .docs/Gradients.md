# Gradientes lineares e radiais

`CGGradient(colors:locations:)` cria um gradiente com pelo menos duas cores e posições normalizadas, finitas e não decrescentes entre `0` e `1`. O renderer aceita até 128 paradas por gradiente.

`CGContext.drawLinearGradient(_:start:end:options:)` interpola as cores ao longo da projeção de cada pixel sobre o eixo informado. `drawRadialGradient(_:startCenter:startRadius:endCenter:endRadius:options:)` interpola entre círculos concêntricos ou deslocados. Ambos pintam a região atual do contexto, respeitam o clipping e o modo de blend, e aplicam a transformação corrente aos pontos e raios.

As cores são convertidas para RGB linear e interpoladas em RGBA pré-multiplicado. Sem opções de extensão, pixels antes da primeira parada ou depois da última ficam transparentes; `drawsBeforeStartLocation` e `drawsAfterEndLocation` estendem as cores extremas. O raio radial sob escalas não uniformes usa a média geométrica das escalas dos eixos.

O software calcula a cor por pixel; o OpenGL usa o shader em `Resources/gradient/`. Para visualizar os dois tipos no Sample, execute `swift run OpenCoreGraphicsSample --test-gradient`.

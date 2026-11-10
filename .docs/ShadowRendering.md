# Sombras

`CGContext.setShadow(offset:blur:color:)` configura uma sombra para os próximos preenchimentos e traços de caminhos. O overload sem `color` usa preto. O deslocamento e o desvio padrão do desfoque são informados em unidades do espaço do usuário, transformados para pixels do dispositivo quando o comando é capturado, e fazem parte do estado salvo por `saveGState()` e restaurado por `restoreGState()`.

O renderer de software desloca a máscara de cobertura da forma, aplica um desfoque gaussiano separável e compõe a sombra antes da forma. Deslocamentos fracionários são amostrados bilinearmente; o valor de `blur` é o desvio padrão gaussiano em pixels após a transformação.

**Limitação do backend OpenGL:** o passe de desfoque em FBO ainda não está implementado. O backend desenha o preenchimento ou traço sem a sombra; o modo de blend da forma permanece inalterado. Para visualizar a implementação de software na janela do Sample, execute `swift run OpenCoreGraphicsSample --test-shadow`.

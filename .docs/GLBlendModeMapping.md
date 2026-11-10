# OpenGL Blend Mode Mapping

OpenGL batches use premultiplied source colors and `GL_FUNC_ADD`. Modes with an exact fixed-function factor mapping use separate RGB and alpha factors below. Modes that need a nonlinear color blend function use normal source-over instead.

| `CGBlendMode` | RGB factors (source, destination) | Alpha factors (source, destination) | OpenGL behavior |
|---|---|---|---|
| `normal` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Direct source-over |
| `multiply` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `screen` | `GL_ONE_MINUS_DST_COLOR`, `GL_ONE` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Direct screen |
| `overlay` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `darken` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `lighten` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `colorDodge` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `colorBurn` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `softLight` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `hardLight` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `difference` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `exclusion` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `hue` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `saturation` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `color` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `luminosity` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `clear` | `GL_ZERO`, `GL_ZERO` | `GL_ZERO`, `GL_ZERO` | Direct clear |
| `copy` | `GL_ONE`, `GL_ZERO` | `GL_ONE`, `GL_ZERO` | Direct copy |
| `sourceIn` | `GL_DST_ALPHA`, `GL_ZERO` | `GL_DST_ALPHA`, `GL_ZERO` | Direct Porter-Duff |
| `sourceOut` | `GL_ONE_MINUS_DST_ALPHA`, `GL_ZERO` | `GL_ONE_MINUS_DST_ALPHA`, `GL_ZERO` | Direct Porter-Duff |
| `sourceAtop` | `GL_DST_ALPHA`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_DST_ALPHA`, `GL_ONE_MINUS_SRC_ALPHA` | Direct Porter-Duff |
| `destinationOver` | `GL_ONE_MINUS_DST_ALPHA`, `GL_ONE` | `GL_ONE_MINUS_DST_ALPHA`, `GL_ONE` | Direct Porter-Duff |
| `destinationIn` | `GL_ZERO`, `GL_SRC_ALPHA` | `GL_ZERO`, `GL_SRC_ALPHA` | Direct Porter-Duff |
| `destinationOut` | `GL_ZERO`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ZERO`, `GL_ONE_MINUS_SRC_ALPHA` | Direct Porter-Duff |
| `destinationAtop` | `GL_ONE_MINUS_DST_ALPHA`, `GL_SRC_ALPHA` | `GL_ONE_MINUS_DST_ALPHA`, `GL_SRC_ALPHA` | Direct Porter-Duff |
| `xor` | `GL_ONE_MINUS_DST_ALPHA`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE_MINUS_DST_ALPHA`, `GL_ONE_MINUS_SRC_ALPHA` | Direct Porter-Duff |
| `plusDarker` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | `GL_ONE`, `GL_ONE_MINUS_SRC_ALPHA` | Normal fallback |
| `plusLighter` | `GL_ONE`, `GL_ONE` | `GL_ONE`, `GL_ONE` | Direct additive |

Run the sample with `swift run OpenCoreGraphicsSample --test-blend-modes` to display semitransparent red rectangles over a blue rectangle using `normal` and `multiply`. The multiply rectangle demonstrates the documented normal fallback in the OpenGL backend.

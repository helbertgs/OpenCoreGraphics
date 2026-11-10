# Core line coverage

Measured on 2026-11-10 with `swift test --enable-code-coverage`.

The generated LLVM coverage report is available at
`.build/out/Products/Debug/codecov/OpenCoreGraphics.json`.

| Source file | Lines covered | Line coverage |
|---|---:|---:|
| `CGBitmapInfo.swift` | 0 / 15 | 0.00% |
| `CGContext.swift` | 811 / 871 | 93.11% |
| `CGImage.swift` | 102 / 102 | 100.00% |
| `CGLayer.swift` | 0 / 4 | 0.00% |
| `CGPath.swift` | 540 / 600 | 90.00% |
| `CGColor.swift` | 85 / 87 | 97.70% |
| `CGColorSpace.swift` | 26 / 29 | 89.66% |
| `CGFont.swift` | 137 / 151 | 90.73% |
| `CGGlyphAtlas.swift` | 57 / 58 | 98.28% |
| `CGGradient.swift` | 18 / 18 | 100.00% |
| `CGAffineTransform.swift` | 378 / 400 | 94.50% |
| `CGPoint.swift` | 41 / 43 | 95.35% |
| `CGRect.swift` | 70 / 72 | 97.22% |
| `CGSize.swift` | 16 / 20 | 80.00% |
| `CGVector.swift` | 96 / 104 | 92.31% |
| `BMPEncoder.swift` | 106 / 110 | 96.36% |
| `BitmapRenderTarget.swift` | 15 / 18 | 83.33% |
| `CGRenderTarget.swift` | 17 / 17 | 100.00% |
| `DrawCommand.swift` | 14 / 14 | 100.00% |
| `PathFlattener.swift` | 144 / 156 | 92.31% |
| `PixelSurface.swift` | 102 / 102 | 100.00% |
| `SoftwareRenderer.swift` | 1,016 / 1,183 | 85.88% |
| `Stroker.swift` | 309 / 361 | 85.60% |
| `CGEvent.swift` | 0 / 36 | 0.00% |
| `CGGraphicsState.swift` | 37 / 39 | 94.87% |
| `GLFWPlatform.swift` | 20 / 26 | 76.92% |
| `CGBitmapParameters.swift` | 7 / 7 | 100.00% |
| `CGDataProvider.swift` | 3 / 16 | 18.75% |
| **Total** | **4,167 / 4,659** | **89.44%** |

The aggregation includes all Swift source files in the `OpenCoreGraphics` target, excluding only `Rendering/GL/` and `CGWindow.swift`. Dependency, test, and Sample files are not included. The full instrumented test run passed with 167 tests in 31 suites.

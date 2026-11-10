# Core line coverage

Measured on 2026-11-10 with:

```sh
swift test --enable-code-coverage
```

The generated LLVM coverage report is available at
`.build/out/Products/Debug/codecov/OpenCoreGraphics.json`.

| Type | Lines covered | Line coverage |
|---|---:|---:|
| `CGContext` | 342 / 408 | 83.82% |
| `CGGraphicsState` | 16 / 16 | 100% |
| `CGPath` | 201 / 214 | 93.93% |
| `CGColor` | 49 / 50 | 98.00% |
| `CGColorSpace` | 26 / 29 | 89.66% |
| `CGAffineTransform` | 378 / 400 | 94.50% |
| `CGPoint` | 41 / 43 | 95.35% |
| `CGRect` | 69 / 72 | 95.83% |
| `CGSize` | 16 / 20 | 80.00% |
| `CGVector` | 96 / 104 | 92.31% |
| `DrawCommand` | N/A | Declaration-only source; tests construct and compare all five cases. |

The full test run passed with 53 tests in 12 suites.

# Swift source coverage

## Measurement and scope

Measured on 2026-11-10 with Swift 6.4.2, Xcode 27.2, macOS 26.6.2 arm64,
and LLVM coverage 21.0.0. The source inventory is all **60 `.swift` files**
under `Sources/OpenCoreGraphics`; test, sample, tool, C, and dependency sources
are excluded.

The historical core includes sources outside the `Rendering/GL` path
components and excludes only the exact relative path
`Services/Window Services/CGWindow.swift`. File suffix and path components are
checked explicitly. A same-named `CGWindow.swift` elsewhere remains eligible.

Line counts use LLVM's per-file `summary.lines.covered` and
`summary.lines.count` fields. The aggregate is the sum of covered instrumentable
lines divided by the sum of instrumentable lines. File percentages are never
averaged. Each scope must have a positive denominator.

LLVM maps line coverage for 42 of the 60 files. Investigation of every
unmapped eligible source found 18 files with **no source-authored executable
lines**: declaration-only Swift types, stored-property-only structs, a
typealias, or an empty file. No conditional-compilation exclusion was used to
explain these files. Each path, reason, platform, and SHA-256 is recorded in
[`scripts/coverage-reviewed-no-lines.json`](../../scripts/coverage-reviewed-no-lines.json).
The hash binds each review to the inspected contents. A changed file, a file
that gains line mappings, a stale manifest entry, or a newly missing eligible
source blocks the report and requires re-review. These 18 files are not treated
as covered or assigned invented line counts: because they contain no
source-authored executable lines, they add zero instrumentable lines to the
denominator.

| Scope | Inventory files (mapped) | Covered / instrumentable lines | Coverage |
|---|---:|---:|---:|
| Historical core | 49 (31 mapped + 18 reviewed no-line) | **4,501 / 5,014** | **89.77%** |
| `Rendering/GL/` (separate) | 10 (10 mapped) | 1,066 / 2,220 | 48.02% |
| Window services, including `CGWindow.swift` | 8 (6 mapped + 2 reviewed no-line) | 313 / 881 | 35.53% |
| Exact excluded `CGWindow.swift` path | 1 (1 mapped) | 84 / 625 | 13.44% |

The core row is from the required default run. A separate complete run with
`OPENCOREGRAPHICS_RUN_GL_COMPARISON=1` reported **4,522 / 5,014 = 90.19%**
for the core, **1,880 / 2,220 = 84.68%** for GL, and **640 / 881 = 72.64%**
for window services including `CGWindow.swift`. Window-services overlaps
with core in five non-`CGWindow.swift` files. Do not add these scope
percentages or numerators/denominators together.

## Review of all unmapped eligible sources

The LLVM export has no line mapping for each path below. The source itself was
reviewed on macOS 26.6.2 arm64; no source-authored executable lines or
conditional branches were found. Compiler-synthesized conformance/initializer
behavior is not attributed to authored source lines by this LLVM export. The
exact file bytes are pinned in the JSON manifest so future edits cannot inherit
this exception silently.

| Relative source path | Finding |
|---|---|
| `2D Drawing/CGBlendMode.swift` | Enum cases and conformances only. |
| `2D Drawing/CGImageAlphaInfo.swift` | Enum cases and conformances only. |
| `2D Drawing/CGInterpolationQuality.swift` | Frozen enum cases and conformances only. |
| `Colors and Fonts/CGColorRenderingIntent.swift` | Enum cases and conformances only. |
| `Colors and Fonts/CGGlyph.swift` | `UInt16` typealias only. |
| `Colors and Fonts/CGGlyphBitmap.swift` | Immutable stored fields; synthesized `Equatable`/`Sendable` only. |
| `Colors and Fonts/CGTextDrawingMode.swift` | Enum cases and conformances only. |
| `Enumerations/CGBitmapLayout.swift` | Enum cases and conformances only. |
| `Enumerations/CGColorModel.swift` | Enum cases and conformances only. |
| `Enumerations/CGComponent.swift` | Enum cases and conformances only. |
| `Enumerations/CGImageComponentInfo.swift` | Enum cases and conformances only. |
| `Enumerations/CGLineCap.swift` | Enum cases and conformances only. |
| `Enumerations/CGLineJoin.swift` | Enum cases and conformances only. |
| `Rendering/CGClipCoverageError.swift` | One enum case and `Equatable` conformance only. |
| `Rendering/Polyline.swift` | Immutable stored fields; synthesized `Equatable`/`Sendable` only. |
| `Services/Display Services/CGDisplay.swift` | Empty, zero-byte file. |
| `Services/Window Services/CGWindowError.swift` | Error enum cases and synthesized conformances only. |
| `Services/Window Services/WindowLoopTestHandle.swift` | Stored closure properties and actor annotation only. |

## Fail-closed gate

`scripts/report-swift-coverage.py` compares the complete target `.swift`
inventory to LLVM's export. An eligible source absent from LLVM must be in the
reviewed manifest and match its recorded SHA-256. It also fails if a reviewed
file changes, gains executable-line mapping, disappears from the target, or
has a non-eligible path. The historical percentage is emitted only after this
inventory check succeeds and the aggregate denominator is positive. A
previously unknown eligible source is **not** silently counted as zero lines
or omitted.

Fixture coverage includes an out-of-target Swift path and a non-Swift path,
the exact `CGWindow.swift` exclusion versus a different file of the same name,
GL path components, an explicitly reviewed zero-line source, an unreviewed
missing eligible source (must fail), a changed reviewed source (must fail),
and a zero denominator (must fail). The below-threshold fixture reports
**82 / 103 = 79.61%** and fails the 80% gate even though its missing file has a
valid no-line review.

## Reproduction

The required test command passed with 288 tests in 51 suites. The default run
reported 13 opt-in tests skipped:

```sh
swift test --enable-code-coverage
python3 -c 'import runpy; runpy.run_path("scripts/report-swift-coverage.py", run_name="__main__")'
python3 -c 'import runpy; runpy.run_path("scripts/tests/test_report_swift_coverage.py", run_name="__main__")'
```

In the current shell, `python3` is available as Python 3.15.2 but its shim
does not pass script-file arguments through. The `python3 -c`/`runpy` form
above uses that interpreter without requiring Python 3.15 specifically. On a
normal Python installation, invoke the `.py` files directly with `python3`.

The complete suite was also run with GL context tests enabled: 288 tests in
51 suites passed, with three unrelated cooperative-window tests explicitly
skipped:

```sh
OPENCOREGRAPHICS_RUN_GL_COMPARISON=1 swift test --enable-code-coverage
python3 -c 'import runpy; runpy.run_path("scripts/report-swift-coverage.py", run_name="__main__")'
```

The profile is local to this macOS/Swift/LLVM environment. It does not claim
coverage for other OSes, toolchains, or graphics drivers.

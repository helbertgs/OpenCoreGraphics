# Glyph rasterization and upload benchmark

## Reproduction and scope

Run the deterministic benchmark with:

```sh
swift test -Xswiftc -strict-concurrency=complete --filter GLGlyphCacheBenchmarkTests
```

The test uses the bundled `tiny-test.ttf`, the production
`CGFont.rasterizedGlyph(_:at:)` rasterizer and `CGGlyphAtlas(bitmaps:)` packer.
For each frame it prepares 48 glyphs at 20 pixels, for 30 frames per scenario:

- **Static:** the same `"IA"` repeated 24 times in every frame.
- **Mutable:** the first 46 glyphs are repeated `"IA"` and the final two alternate
  between `"IA"` and `"AI"` on successive frames.

Both scenarios contain only two distinct glyph IDs. Each reported prototype
CPU frame-preparation time is the median of seven measured runs, divided by 30
frames; each strategy is warmed once before timing.
The mutable case changes the trailing glyph order but introduces no new glyph
IDs after its first frame, so it measures reuse across changing text rather
than cache-miss behavior for a growing alphabet. The timings are one observed
local run and should be treated as descriptive measurements, not guarantees.

Three alternatives are compared:

1. **Command atlas (current path):** rasterize every glyph occurrence and build
   one real production atlas per frame. The upload count and bytes follow the
   current GL path: one full R8 texture upload for each fresh atlas, followed
   by eviction after the draw.
2. **CPU mask cache (prototype):** retain each distinct rasterized mask, but
   build the same production per-command atlas and model the same full upload
   and eviction for each frame.
3. **Paged atlas (test-only prototype):** retain 64×64 R8 pages, pack actual
   rasterized masks with one-pixel gutters, and count a full page upload when a
   page is first created. Subsequent new masks in an existing page are modeled
   as subregion updates carrying only that mask's coverage bytes. The sample
   workload fits in one page and discovers both glyphs on its first frame.

Counters for rasterization and atlas construction are exercised directly.
Upload counts/bytes are controlled accounting models based on the production
texture-loader formats, fresh atlas identities, and immediate atlas eviction;
the test does not create GL textures or instrument driver calls. Retained CPU
bytes count cached coverage and, for the page prototype, its CPU page backing.
Retained GPU bytes count the logical R8 texture storage. Transient CPU/GPU
bytes report the largest one-frame atlas allocation, not allocator or driver
overhead.

## Environment and observed run

- macOS 26.6.2 (Build 25G83), Apple M3 Pro, arm64.
- Swift 6.4.2; Swift Testing library 2403.
- Font: bundled `tiny-test.ttf`; 20-pixel rasterization.
- Workload: 30 frames × 48 glyphs; 7 timing repetitions; 64×64 page.
- Timing: monotonic `ContinuousClock`; values are CPU frame-preparation
  nanoseconds, not rendered frame times.

| Scenario | Strategy | Rasterizations | Atlas builds | Modeled uploads | Modeled bytes uploaded | Retained CPU bytes | Retained GPU bytes | Peak transient CPU / GPU bytes | Draw batches | Median CPU prep / frame |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Static | Command atlas | 1,440 | 30 | 30 | 161,760 | 0 | 0 | 5,392 / 5,392 | 30 | 229,846 ns |
| Static | CPU mask cache | 2 | 30 | 30 | 161,760 | 140 | 0 | 5,392 / 5,392 | 30 | 170,533 ns |
| Static | Paged atlas | 2 | 0 | 1 | 4,096 | 4,236 | 4,096 | 0 / 0 | 30 | 17,685 ns |
| Mutable | Command atlas | 1,440 | 30 | 30 | 161,760 | 0 | 0 | 5,392 / 5,392 | 30 | 229,083 ns |
| Mutable | CPU mask cache | 2 | 30 | 30 | 161,760 | 140 | 0 | 5,392 / 5,392 | 30 | 170,047 ns |
| Mutable | Paged atlas | 2 | 0 | 1 | 4,096 | 4,236 | 4,096 | 0 / 0 | 30 | 18,714 ns |

These are the medians from the latest rerun on 2026-11-11 using the command
above. The operation, upload, and logical-memory counts were unchanged from the
previous run. The earlier CPU preparation medians were 237,074 / 236,460 ns
(command atlas), 174,415 / 172,015 ns (CPU mask cache), and 19,246 / 19,063 ns
(paged atlas), for static / mutable respectively. The latest values are lower
in this run, but CPU preparation times vary between runs and these are prototype
measurements, not a before/after production comparison.

The page's 4,096-byte upload is the initial 64×64 R8 page, including empty
texels; the separate 140 bytes are the two cached source masks. The command
atlas occupies 5,392 bytes for a single frame because each repeated glyph
occurrence is packed separately.

## Decision

**Keep the current per-command drawing strategy for now; do not introduce a
production glyph cache.** For these two-character repeated workloads, the
CPU-mask prototype reduces rasterizations from 1,440 to 2 and its latest
preparation medians are about 26% lower, but it does not reduce atlas builds,
uploads, or uploaded bytes. The paged prototype models one upload instead of
30 and the lowest CPU preparation time, at the cost of retaining 4,236 CPU
bytes and 4,096 logical GPU bytes for this tiny working set. Its timing excludes
real GL updates, texture binding, geometry generation, draw submission, and
synchronization; it is not evidence of an end-to-end frame-time win.

The fixture has only two glyphs and does not model broad alphabets, varying
fonts/sizes, eviction, page fragmentation, alpha/color text, or page overflow.
The prototype comparison does not measure process RSS, actual GPU memory,
actual driver upload latency, or rendered frame time. The separate real-GL
measurement below covers only the current implementation. Therefore the
measured CPU preparation advantage alone is insufficient to select a
production cache policy or budget.
The 64×64 page is a prototype parameter, not a device texture-limit decision.
In particular, this decision does not implement, replace, or dispense with
US-022's texture-limit handling.

## GL pixel validation

The controlled prototype metrics remain GPU-independent. The existing opt-in GL
pixel and texture lifecycle suites run alongside the current-pipeline GL
workload using:

```sh
ruby scripts/run-gl-tests.rb --timeout 90
```

It completed 28 tests in five suites. The glyph rendering comparison passed
with zero measured difference at a 4/255 tolerance. The pixel-comparison tests
recorded Apple M3 Pro / Apple GL 4.1 Metal - 90.5, 128×128 linear RGBA8
framebuffer, MSAA 4, and system version 26.6.2. The real current-pipeline frame timings are reported separately below;
prototype comparisons above remain CPU/model measurements only. The runner's
required paged-glyph report verified two pages for 2,731 glyphs at a queried
16,384 texture limit. There were 34 non-black GL/software pixels before the
page boundary and 102 after it; overall and both regional mean differences
were `3.5903033088235294e-7` (within the 4/255 tolerance).

## Real GL current-pipeline frame timing

The opt-in glyph comparison test also runs a repeatable workload through the
production `CGContext.showGlyphs` → `CGContext.flush` → `GLRenderer` path. Run
it with the conclusive runner, which validates the timing record as part of
the GL test result:

```sh
ruby scripts/run-gl-tests.rb --timeout 90
```

The workload uses `Tests/OpenCoreGraphicsTests/Resources/tiny-test.ttf`,
20-pixel glyphs and 48 glyphs per frame. It draws 30 frames per scenario for five measured
repetitions, after ten untimed warmup frames per scenario:

- **Static:** the same 48 glyphs from repeated `"IA"` on every frame.
- **Mutable:** the final two glyphs alternate between `"IA"` and `"AI"`; the
  alphabet remains the same two glyphs.

Every timed frame clears the framebuffer to black, submits opaque white glyphs
at precomputed positions, calls `CGContext.flush()`, then calls
`glad_glFinish()` before stopping `ContinuousClock`. Elapsed wall time therefore
includes CPU text preparation/rasterization, atlas packing, GL submission and
upload, GPU execution, and the blocking completion wait. It excludes buffer
swap, v-sync, and presentation. The report summarizes individual frame times
as min/median/p95/max and is saved as `glyph-frame-time.json` in the runner's
unique artifact directory. For the latest rerun, the report is
`.build/gl-comparison/run-20261111T005827-25540/glyph-frame-time.json`.
Runner success requires the JSON report, valid GL
metadata, 150 samples per scenario, expected source-derived operation counts,
and positive timings and atlas payloads.

**Latest observed run (2026-11-11):** Apple M3 Pro, arm64, macOS 26.6.2
(Build 25G83), Swift 6.4.2,
11 logical processors, Apple GL 4.1 Metal - 90.5. The benchmark window is
512×96 points; its measured RGBA8 framebuffer was 1024×192 pixels with MSAA 4.
The conclusive runner completed all 28 tests in five suites and validated the
emitted real-GL and paged-glyph reports.

| Current GL path, per 150-frame scenario | Static | Mutable |
|---|---:|---:|
| Timed frames | 150 | 150 |
| Production glyph rasterizations (source-derived from submitted occurrences) | 7,200 | 7,200 |
| Atlas texture uploads (source-derived, one fresh atlas per draw) | 150 | 150 |
| R8 bytes uploaded (source-derived from atlas payloads) | 808,800 | 808,800 |
| Largest one-frame atlas payload | 5,392 bytes | 5,392 bytes |
| Logical glyph-cache bytes after flush/eviction | 0 | 0 |
| Frame completion minimum | 999,833 ns | 999,375 ns |
| Frame completion median | 1,074,334 ns | 1,068,458 ns |
| Frame completion p95 | 1,336,708 ns | 1,296,750 ns |
| Frame completion maximum | 1,607,292 ns | 3,481,542 ns |

Rasterization and upload counters describe measured frames and are exact counts
derived from the production call path and submitted text, not GL-call
interception. The byte-size preflight separately rasterizes one atlas for each
distinct text ordering outside the timed frames; warmup frames are also not in
the reported counts. Upload byte totals use the production atlas format and
those exact preflight payload sizes. Memory is logical atlas/cache
accounting only: no RSS, allocator overhead, driver allocation, or physical
GPU-memory counter is collected. Per-frame times are one observed run on this
host and remain sensitive to system load. `glFinish` intentionally serializes
frames and does not represent v-synced interactive throughput.

These are real measurements for the current pipeline only. The previous
recorded medians were 829,333 ns static and 791,125 ns mutable; the latest are
1,074,334 ns and 1,068,458 ns respectively. The mutable maximum also changed
from 1,700,291 ns to 3,481,542 ns. These are separate runs, so this is
run-to-run variation, not a before/after cache comparison and not evidence of a
regression or gain. The
command-atlas, CPU-mask-cache, and paged-atlas comparisons above remain CPU
timings and controlled upload/accounting models; neither prototype was run or
timed on GL. The similar static and mutable medians for this two-glyph workload
do not establish performance for other text, devices, drivers, or workloads.
This evidence does not justify changing the decision to defer a production
cache and does not address or waive US-022 texture-size limits.

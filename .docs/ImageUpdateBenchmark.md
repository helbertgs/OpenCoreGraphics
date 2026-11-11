# Image update benchmark

## Scope and reproducibility

Run the measured workload with:

```sh
swift test -Xswiftc -strict-concurrency=complete --filter GLImageUpdateBenchmarkTests
```

`GLImageUpdateBenchmarkTests` creates a real `CGImage` with a `CGDataProvider`
and captures each frame by calling the production `CGImageSnapshot(image:)`
initializer. The provider is set to the frame's data before each capture, so
the mutable workload exercises actual provider capture and stable image
identity. The resulting same snapshot array is passed to the production
`GLTextureCache` and a direct, allocate-on-every-frame reference. The reference
does not retain or reuse textures. Both paths use the same recording, no-op
`GLTextureLoader`; this isolates cache comparison, bookkeeping and upload
decisions from the GPU. Each scenario warms both paths once, then measures
seven passes per path using `ContinuousClock` and reports the median of those
seven frame-loop times.

Each scenario contains 30 immutable 128×128 RGBA8 snapshots (65,536 bytes each)
with one stable identity:

- **Static:** every snapshot contains the same `0x7f` byte pattern.
- **Mutable:** the final blue-channel byte alternates between 126 and 128.

Deterministic source-frame byte arrays are prepared before timing. Production
snapshot capture is timed separately, including assigning provider data and
calling `CGImageSnapshot(image:)` for every frame. That initializer's
`Data(Array(provider.data))` explicitly copies each provider payload into the
snapshot. The report therefore counts 30 explicit snapshot copy operations and
1,966,080 source payload bytes per scenario. This is measured production
capture and payload size; it is not allocator-level instrumentation of
intermediate allocations or a count of physical memory-copy instructions.

## Observed run

Environment: Apple Swift 6.4.2, macOS 26.6.2 (Build 25G83), arm64. No GL
context was used for these numbers.

| Metric per 30-frame workload | Static: cache | Static: no reuse | Mutable: cache | Mutable: no reuse |
|---|---:|---:|---:|---:|
| Production captures / explicit payload copies / bytes | 30 / 30 / 1,966,080 | Same shared snapshots | 30 / 30 / 1,966,080 | Same shared snapshots |
| Cache equality decisions | 29 | 0 | 29 | 0 |
| Texture-loader create calls | 1 | 30 | 1 | 30 |
| Texture-loader update calls | 0 | 0 | 29 | 0 |
| Payload bytes passed to loader | 65,536 | 1,966,080 | 1,966,080 | 1,966,080 |
| Median frame-loop time (7 passes) | 88,125 ns | 9,708 ns | 91,167 ns | 9,709 ns |
| Logical bytes retained by image cache | 131,072 | 0 | 131,072 | 0 |
| Peak one-texture logical size | 65,536 | 65,536 | 65,536 | 65,536 |
| Production provider capture loop (30 frames) | 288,834 ns | Shared inputs | 244,500 ns | Shared inputs |

The cache retains one estimated 65,536-byte RGBA8 texture plus the latest
65,536-byte immutable snapshot. The reference has no cache retention and
processes at most one 65,536-byte logical texture at a time. The source frames
and captured snapshot arrays are constructed once and shared across all
repetitions and both compared paths; their 1,966,080-byte-per-scenario footprint
is therefore excluded from the per-strategy cache-retained figure.

## Interpretation, trade-offs, and limitations

- For static content, the cache reduced recording-loader create/upload calls
  from 30 to 1 and payload bytes from 1,966,080 to 65,536, while making 29
  content comparisons and retaining an additional snapshot. In this run its
  CPU frame-loop median was higher than the direct no-reuse reference.
- For changing content, the cache made 29 comparisons and 29 in-place update
  calls after its initial allocation. The payload bytes were unchanged from
  the reference; this synthetic run also measured a higher cache-path median.
- These timings are for Swift cache logic plus a no-op loader, not OpenGL
  transfer latency, GPU allocation/deletion, drawing, or end-to-end frame
  time. They do not demonstrate a performance gain or predict other image
  sizes, mutation patterns, drivers, or machines.
- Memory is logical accounting from the cache's documented GPU-level-zero
  estimate and retained snapshot. It is not process RSS or physical driver
  allocation, and excludes transient `Data`/`Array` buffers, allocator
  overhead, the prebuilt input frames and snapshots retained by the benchmark.
- Equality decision counts are derived from the deterministic cache-hit path;
  compared byte counts and early-exit behavior inside `Data` equality are not
  instrumented.
- The test verifies that both paths pass the last input payload unchanged.
  The opt-in GL runner also completed in this environment: 28 tests in five
  suites passed, including the rendered mutable-image update and eviction
  checks; the updated pixel was `[0, 0, 255, 255]` and the replacement pixel
  was `[0, 255, 0, 255]`. This validates existing pixel behavior, but provides
  no real-GL timing for the benchmark workload.
- No production declarations or public APIs were changed. The workload and
  fake backend are test-only; there are no performance claims based on the
  counts alone.

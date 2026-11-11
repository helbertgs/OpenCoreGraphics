# macOS automation

`.github/workflows/macos.yml` runs the supported automated checks on
GitHub-hosted `macos-26` runners. The package requires Swift tools version
6.4. Before building, `scripts/select-swift-toolchain.sh` tries each installed
Xcode independently, setting `DEVELOPER_DIR` for `xcrun --find swift` for that
specific Xcode, then tries standalone toolchains by invoking their compiler
directly. It accepts Swift 6.4 or later and continues past incompatible or
unresolvable candidates. For Xcode selection it exports that Xcode's
`DEVELOPER_DIR`; for standalone selection it exports the toolchain identifier
and compiler path. It fails explicitly rather than attempting a build with an
unknown or incompatible default if no suitable candidate exists. This avoids
conflating Xcode installations that share the default toolchain identifier.

The published `actions/runner-images` macOS 26 image definition inspected on
November 10, 2026 lists Xcode 26.6 as default and Command Line Tools 26.6, but
does not identify the bundled Swift compiler version or list Swift 6.4 as a
separately installed toolchain. Swift 6.4 was released September 15, 2026.
Those image details alone therefore do not verify that the hosted image
contains a usable Swift 6.4-or-later toolchain. The workflow's selector is the
runtime check; its result on GitHub Actions cannot be claimed until the job
runs. No Windows or Linux CI workflow is created or required.

Before selecting a real compiler, the workflow runs
`scripts/test-select-swift-toolchain.sh` with executable fixtures. It verifies
that an invalid first Xcode candidate does not block a valid second one,
accepts Swift 6.4 and 6.5, rejects Swift 6.3, tries later standalone candidates,
and fails explicitly when every available fixture is below the minimum.
These tests do not require Xcode or assert availability on the hosted image.

## Standard job

The standard job runs, in order:

```sh
swift build
swift test
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

GitHub Actions fails the job when any command exits unsuccessfully, and the
summary step reports the outcome of each check even if an earlier check fails.
The test steps use `set -o pipefail` with `tee`, so a failing `swift test`
cannot be masked by a successful log-capture process.
The test summary explicitly lists opt-in integration suites not run by the
standard job. In particular, GL comparison, texture-cache integration, resource
teardown, GLFW lifecycle and initialization tests require
`OPENCOREGRAPHICS_RUN_GL_COMPARISON=1`; the cooperative window integration test
requires `OPENCOREGRAPHICS_RUN_WINDOW_COOPERATIVE=1`. These are reported as
**not run**, never as passing visual comparisons.

This workflow does not collect coverage or claim a coverage percentage. The
summary states that limitation; coverage measurement and its denominator and
exclusions are separate work.

## Optional GL job

The GL job is disabled by default and can only be requested through
`workflow_dispatch` with `run_gl: true`. It runs on a self-hosted macOS runner
that an operator must configure with the `graphics` label, an active graphical
session and an OpenGL 3.3 driver. A GitHub-hosted runner is not assumed to
provide a usable interactive GL context.

The job invokes `ruby scripts/run-gl-tests.rb --timeout 600`. That runner
requires final Swift Testing summaries and the expected per-scene, glyph-page,
texture-cache and glyph benchmark reports. A test failure, skipped test,
timeout, interruption or incomplete report exits nonzero. Its distinct
graphics-unavailable exit code (2) also fails the job; the summary explicitly
labels that outcome unavailable rather than passed. Thus enabling the job on a
host without a working context does not create a false visual-comparison pass.

The manual job's execution depends on repository configuration and an available
self-hosted runner. A local validation of this workflow cannot claim that
GitHub-hosted CI or the opt-in GL runner has executed; those results are only
available after their corresponding Actions jobs run.

## Failure propagation check

On November 10, 2026, a temporary Swift Testing test with an intentional
failed expectation was run through the same command shape as the workflow test
step: `swift test --filter WorkflowFailureProbe 2>&1 | tee /dev/stderr` with
`set -o pipefail`. Swift Testing reported one failed test, and the pipeline
returned exit status 1; the surrounding validation accepted only that
nonzero status. The temporary probe source was then removed. This verifies
local propagation through `swift test` and `tee`; it does not claim that a
GitHub Actions job has run.

## References for hosted toolchain availability

- [macOS 26 hosted runner image definition](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)
- [Swift 6.4 release announcement](https://www.swift.org/blog/swift-6.4-released/)

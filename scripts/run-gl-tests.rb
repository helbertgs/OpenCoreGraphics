#!/usr/bin/env ruby

require "optparse"
require "json"

timeout = 120.0
parser = OptionParser.new do |options|
  options.banner = "Usage: ruby scripts/run-gl-tests.rb [--timeout SECONDS] [-- COMMAND ARG...]"
  options.on("--timeout SECONDS", Float, "Maximum duration including build (default: 120)") do |value|
    timeout = value
  end
end

begin
  parser.parse!
  raise OptionParser::InvalidArgument, "timeout must be positive and finite" unless timeout.finite? && timeout > 0
rescue OptionParser::ParseError => error
  warn error.message
  warn parser
  exit 2
end

command = ARGV.empty? ? [
  "swift", "test", "--filter",
  "GLSoftwareComparisonTests|GLGlyphComparisonTests|GLTextureCacheTests|GLTextureCacheIntegrationTests|GlyphMetricTests"
] : ARGV
artifacts_root = ENV["OPENCOREGRAPHICS_GL_ARTIFACTS"] || File.expand_path("../.build/gl-comparison", __dir__)
artifacts = File.join(File.expand_path(artifacts_root), "run-#{Time.now.utc.strftime('%Y%m%dT%H%M%S')}-#{Process.pid}")
environment = {
  "OPENCOREGRAPHICS_RUN_GL_COMPARISON" => "1",
  "OPENCOREGRAPHICS_GL_ARTIFACTS" => artifacts
}
puts "GL runner: artifacts directory: #{artifacts}"
reader, writer = IO.pipe

begin
  pid = Process.spawn(environment, *command, out: writer, err: writer, pgroup: true)
rescue SystemCallError => error
  reader.close
  writer.close
  warn "GL runner: could not start test process: #{error.message}"
  exit 1
end
writer.close

output = +""
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
status = nil
timed_out = false
eof = false

begin
  until eof && status
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if remaining <= 0
      timed_out = true
      break
    end

    ready = IO.select(eof ? nil : [reader], nil, nil, [remaining, 0.1].min)
    if ready
      begin
        chunk = reader.read_nonblock(16_384)
        $stdout.write(chunk)
        $stdout.flush
        output << chunk
      rescue IO::WaitReadable
        next
      rescue EOFError
        eof = true
      end
    end
    status ||= Process.waitpid2(pid, Process::WNOHANG)&.last
  end
ensure
  if timed_out || status.nil?
    begin
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH
    end
    status ||= Process.waitpid2(pid).last
  end
  reader.close
end

if timed_out
  warn "GL runner: TIMEOUT after #{timeout} seconds; execution incomplete."
  exit 1
end

unless status.exited?
  warn "GL runner: FAILED: test process terminated by signal #{status.termsig}."
  exit 1
end

complete = output.match?(/^.*Test run with 28 tests in 5 suites (?:passed|failed) after .+ seconds(?: with \d+ issues?)?\.\s*$/)
if !complete
  warn "GL runner: INCOMPLETE: missing final Swift Testing result for all selected suites."
  exit 1
end

unavailable = output.scan(/^GL_RUNNER_GRAPHICS_UNAVAILABLE: (.+)$/).flatten
failed_tests = output.scan(/^.*Test (?:comparesSharedScenesAcrossBackends|comparesGlyphRenderingAcrossBackends|updatesAndEvictsRealTexturesWithoutChangingRenderedPixels)\(\) failed after .+ seconds(?: with \d+ issues?)?\.\s*$/)
all_failed_tests = output.scan(/^.*Test (?!run with ).+ failed after .+ seconds(?: with \d+ issues?)?\.\s*$/)
if !unavailable.empty? && unavailable.length == failed_tests.length && failed_tests.length == all_failed_tests.length &&
   !output.match?(/^.*(?:Expectation failed|Issue recorded|skipped)\b/i)
  warn "GL runner: GRAPHICS_UNAVAILABLE: #{unavailable.uniq.join(', ')}"
  exit 2
end

if output.match?(/^.*(?:Suite|Test) .* skipped\.\s*$/)
  warn "GL runner: SKIPPED: one or more GL tests did not run."
end

passed = [
  /^.*Test comparesSharedScenesAcrossBackends\(\) passed after .+ seconds\.\s*$/,
  /^.*Test comparesGlyphRenderingAcrossBackends\(\) passed after .+ seconds\.\s*$/,
  /^.*Test preservesContentAndBudgetAcrossFrameSequence\(\) passed after .+ seconds\.\s*$/,
  /^.*Test updatesAndEvictsRealTexturesWithoutChangingRenderedPixels\(\) passed after .+ seconds\.\s*$/,
  /^.*Test localFailureCannotHideInMean\(\) passed after .+ seconds\.\s*$/,
  /^.*Test identicalWrongBackendsFailReference\(\) passed after .+ seconds\.\s*$/,
  /^.*Test invalidBuffersAreRejected\(\) passed after .+ seconds\.\s*$/,
  /^.*Test run with 28 tests in 5 suites passed after .+ seconds\.\s*$/
].all? { |pattern| output.match?(pattern) }

glyph_reports = %w[above below rotation horizontal vertical order spacing].product(%w[mean local])
glyph_reports_complete = glyph_reports.all? do |scene, metric|
  matches = output.scan(/^GL_COMPARISON: glyph_#{scene}_#{metric} (PASSED|FAILED) difference=(\S+) tolerance=(\S+)\s*$/)
  next false unless matches.length == 1
  status_text, difference_text, tolerance_text = matches.first
  begin
    difference = Float(difference_text)
    tolerance = Float(tolerance_text)
    status_text == "PASSED" && difference.finite? && tolerance.finite? &&
      difference >= 0 && tolerance >= 0 && tolerance <= 4.0 / 255.0 && difference <= tolerance
  rescue ArgumentError
    false
  end
end

glyph_paging_reports = output.scan(
  /^GL_GLYPH_PAGING: maxTextureSize=(\d+) glyphCount=(\d+) pages=(\d+) difference=(\S+) beforeGLPixels=(\d+) beforeSoftwarePixels=(\d+) beforeDifference=(\S+) afterGLPixels=(\d+) afterSoftwarePixels=(\d+) afterDifference=(\S+)\s*$/
)
glyph_paging_complete = glyph_paging_reports.length == 1 && begin
  limit, glyph_count, page_count, overall_difference,
    before_gl_pixels, before_software_pixels, before_difference,
    after_gl_pixels, after_software_pixels, after_difference =
    glyph_paging_reports.first
  overall_difference, before_difference, after_difference =
    [overall_difference, before_difference, after_difference].map { |value| Float(value) }
  limit.to_i.positive? &&
    glyph_count.to_i.positive? &&
    page_count.to_i > 1 &&
    [before_gl_pixels, before_software_pixels, after_gl_pixels, after_software_pixels]
      .all? { |count| count.to_i.positive? } &&
    [overall_difference, before_difference, after_difference]
      .all? { |difference| difference.finite? && difference >= 0 && difference <= 4.0 / 255.0 }
rescue ArgumentError
  false
end

mutable_reports_complete = %w[mutable_before mutable_after mutable_queued].all? do |scene|
  matches = output.scan(/^GL_COMPARISON: #{scene} (PASSED|FAILED) difference=(\S+) tolerance=(\S+)\s*$/)
  next false unless matches.length == 1
  status_text, difference_text, tolerance_text = matches.first
  begin
    difference = Float(difference_text)
    tolerance = Float(tolerance_text)
    status_text == "PASSED" && difference.finite? && tolerance.finite? &&
      difference >= 0 && tolerance >= 0 && tolerance <= 2.0 / 255.0 && difference <= tolerance
  rescue ArgumentError
    false
  end
end

deterministic_cache_report =
  "GL_TEXTURE_CACHE_METRICS: frames=6 uploads=5 updates=1 uploadedBytes=20 " \
  "retainedBytes=8,8,16,16,16,16 budgetBytes=16 evictions=2 externallyRetainedBytes=8"
deterministic_cache_complete = output.scan(/^#{Regexp.escape(deterministic_cache_report)}\s*$/).length == 1

real_glyph_benchmark_lines = output.scan(/^GLYPH_REAL_FRAME_BENCHMARK: (.+)$/).flatten
real_glyph_benchmark_complete = real_glyph_benchmark_lines.length == 1 && begin
  report = JSON.parse(real_glyph_benchmark_lines.first)
  scenarios = [report.fetch("static"), report.fetch("mutable")]
  scenarios.all? do |scenario|
    timings = %w[minimumNanoseconds medianNanoseconds p95Nanoseconds maximumNanoseconds]
      .map { |key| Float(scenario.fetch(key)) }
    timings.all?(&:finite?) && timings.first.positive? &&
      timings == timings.sort &&
      scenario.fetch("measuredFrames") == 150 &&
      scenario.fetch("rasterizations") == 7_200 &&
      scenario.fetch("uploadCalls") == 150 &&
      scenario.fetch("uploadedBytes").positive? &&
      scenario.fetch("peakTransientAtlasBytes").positive? &&
      scenario.fetch("retainedGlyphCacheBytesAfterFlush").zero?
  end &&
    report.fetch("framebufferWidth").positive? &&
    report.fetch("framebufferHeight").positive? &&
    report.fetch("samples").positive? &&
    report.fetch("msaaEnabled") == true &&
    report.fetch("glVendor").length.positive? &&
    report.fetch("glRenderer").length.positive? &&
    report.fetch("glVersion").length.positive? &&
    report.fetch("synchronization").include?("glad_glFinish") &&
    report.fetch("uploadCountingMethod").include?("source-derived")
rescue JSON::ParserError, KeyError, TypeError, ArgumentError
  false
end

real_cache_reports = output.scan(
  Regexp.new(
    "^GL_TEXTURE_CACHE_REAL: updates=(\\d+) evictions=(\\d+) retainedBytes=(\\d+) budgetBytes=(\\d+) " \
    "updatedPixel=\\[(\\d+), (\\d+), (\\d+), (\\d+)\\] " \
    "evictedPixel=\\[(\\d+), (\\d+), (\\d+), (\\d+)\\] lifetime=verified\\s*$"
  )
)
real_cache_complete = real_cache_reports.length == 1 && begin
  updates, evictions, retained, budget, ur, ug, ub, ua, er, eg, eb, ea =
    real_cache_reports.first.map(&:to_i)
  updates == 1 && evictions == 1 && retained == budget && budget == 8 &&
    ur < 10 && ug < 10 && ub > 245 && ua > 245 &&
    er < 10 && eg > 245 && eb < 10 && ea > 245
end

if status.success? && passed && glyph_reports_complete && glyph_paging_complete && mutable_reports_complete &&
   deterministic_cache_complete && real_cache_complete && real_glyph_benchmark_complete &&
   !output.match?(/^.*(?:skipped|failed|Issue recorded)\b/i)
  puts "GL runner: PASSED: GL rendering, texture-cache lifecycle, synthetic metrics, and real glyph frame-time workloads completed successfully."
  exit 0
end

warn "GL runner: FAILED: test failure, missing glyph or paginated-glyph reports, mutable-image reports, texture-cache evidence, or glyph frame-time benchmark evidence, skipped test, or unsuccessful process exit."
exit 1

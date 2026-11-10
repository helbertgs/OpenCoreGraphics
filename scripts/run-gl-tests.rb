#!/usr/bin/env ruby

require "optparse"

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
  "swift", "test", "--filter", "GLSoftwareComparisonTests|GLGlyphComparisonTests|GlyphMetricTests"
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

complete = output.match?(/^.*Test run with 5 tests in 3 suites (?:passed|failed) after .+ seconds(?: with \d+ issues?)?\.\s*$/)
if !complete
  warn "GL runner: INCOMPLETE: missing final Swift Testing result for both GL suites."
  exit 1
end

unavailable = output.scan(/^GL_RUNNER_GRAPHICS_UNAVAILABLE: (.+)$/).flatten
failed_tests = output.scan(/^.*Test (?:comparesSharedScenesAcrossBackends|comparesGlyphRenderingAcrossBackends)\(\) failed after .+ seconds(?: with \d+ issues?)?\.\s*$/)
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
  /^.*Test localFailureCannotHideInMean\(\) passed after .+ seconds\.\s*$/,
  /^.*Test identicalWrongBackendsFailReference\(\) passed after .+ seconds\.\s*$/,
  /^.*Test invalidBuffersAreRejected\(\) passed after .+ seconds\.\s*$/,
  /^.*Test run with 5 tests in 3 suites passed after .+ seconds\.\s*$/
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

if status.success? && passed && glyph_reports_complete && !output.match?(/^.*(?:skipped|failed|Issue recorded)\b/i)
  puts "GL runner: PASSED: both GL tests and synthetic metric tests completed successfully."
  exit 0
end

warn "GL runner: FAILED: test failure, missing glyph reports, skipped test, or unsuccessful process exit."
exit 1

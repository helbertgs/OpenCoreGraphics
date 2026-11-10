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

command = ARGV.empty? ? ["swift", "test", "--filter", "GLSoftwareComparisonTests|GLGlyphComparisonTests"] : ARGV
environment = { "OPENCOREGRAPHICS_RUN_GL_COMPARISON" => "1" }
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

complete = output.match?(/^.*Test run with 2 tests in 2 suites (?:passed|failed) after .+ seconds\.\s*$/)
if !complete
  warn "GL runner: INCOMPLETE: missing final Swift Testing result for both GL suites."
  exit 1
end

unavailable = output.scan(/^GL_RUNNER_GRAPHICS_UNAVAILABLE: (.+)$/).flatten
failed_tests = output.scan(/^.*Test (?:comparesSharedScenesAcrossBackends|comparesGlyphRenderingAcrossBackends)\(\) failed after .+ seconds\.\s*$/)
if !unavailable.empty? && unavailable.length == failed_tests.length &&
   !output.match?(/^.*(?:Expectation failed|Issue recorded|skipped)\b/i)
  warn "GL runner: GRAPHICS_UNAVAILABLE: #{unavailable.uniq.join(', ')}"
  exit 2
end

passed = [
  /^.*Test comparesSharedScenesAcrossBackends\(\) passed after .+ seconds\.\s*$/,
  /^.*Test comparesGlyphRenderingAcrossBackends\(\) passed after .+ seconds\.\s*$/,
  /^.*Test run with 2 tests in 2 suites passed after .+ seconds\.\s*$/
].all? { |pattern| output.match?(pattern) }

if status.success? && passed && !output.match?(/^.*(?:skipped|failed|Issue recorded)\b/i)
  puts "GL runner: PASSED: both GL tests completed successfully."
  exit 0
end

warn "GL runner: FAILED: test failure, skipped test, or unsuccessful process exit."
exit 1

#!/usr/bin/env ruby

require "optparse"

timeout = 30.0
parser = OptionParser.new do |options|
  options.banner = "Usage: ruby scripts/run-window-baseline.rb [--timeout SECONDS] [-- COMMAND ARG...]"
  options.on("--timeout SECONDS", Float) { |value| timeout = value }
end
begin
  parser.parse!
  raise OptionParser::InvalidArgument, "timeout must be positive and finite" unless timeout.finite? && timeout > 0
rescue OptionParser::ParseError => error
  warn error.message
  exit 2
end

command = ARGV.empty? ? ["swift", "run", "OpenCoreGraphicsWindowBaseline"] : ARGV
reader, writer = IO.pipe
begin
  pid = Process.spawn(
    *command, out: writer, err: writer, pgroup: true
  )
rescue SystemCallError => error
  reader.close
  writer.close
  warn "WINDOW_BASELINE RUNNER: spawn failed: #{error.message}"
  exit 1
end
writer.close
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
output = +""
status = nil
eof = false
timed_out = false
begin
  until eof && status
    remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if remaining <= 0
      timed_out = true
      break
    end
    if IO.select(eof ? nil : [reader], nil, nil, [remaining, 0.1].min)
      begin
        chunk = reader.read_nonblock(16_384)
        output << chunk
        $stdout.write(chunk)
        $stdout.flush
      rescue IO::WaitReadable
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
  warn "WINDOW_BASELINE RUNNER: TIMEOUT after #{timeout}s; incomplete"
  exit 1
end
complete = [
  /^WINDOW_BASELINE idle_seconds=\S+ idle_cpu_seconds=\S+ idle_cpu_percent_one_core=\S+ idle_iterations=\d+$/,
  /^WINDOW_BASELINE events_posted=\d+ events_received=\d+ event_latency_ms=\[.*\]$/,
  /^WINDOW_BASELINE frames=\d+ animation_frames=\d+ idle_draws=\d+ second_automatic_frames=\d+ second_after_manual_redraw=\d+ task_during_loop=(?:true|false) task_at_return=(?:true|false) close_ms=\S+$/,
  /^WINDOW_BASELINE COMPLETE$/
].all? { |pattern| output.match?(pattern) }
if status.success? && complete
  puts "WINDOW_BASELINE RUNNER: PASSED"
  exit 0
end
warn "WINDOW_BASELINE RUNNER: FAILED or INCOMPLETE (exit=#{status.exitstatus.inspect}, signal=#{status.termsig.inspect})"
exit 1

#!/usr/bin/env ruby

require "optparse"

timeout = 60.0
async_main = false
initialization_failure = false
parser = OptionParser.new do |options|
  options.banner = "Usage: ruby scripts/run-window-cooperative.rb [--timeout SECONDS] [-- COMMAND ARG...]"
  options.on("--timeout SECONDS", Float) { |value| timeout = value }
  options.on("--async-main") { async_main = true }
  options.on("--initialization-failure") { initialization_failure = true }
end
begin
  parser.parse!
  raise OptionParser::InvalidArgument, "timeout must be positive and finite" unless timeout.finite? && timeout > 0
  raise OptionParser::InvalidArgument, "--initialization-failure requires --async-main" if initialization_failure && !async_main
rescue OptionParser::ParseError => error
  warn error.message
  exit 2
end

command = if ARGV.empty?
            if async_main
              ["swift", "run", "OpenCoreGraphicsWindowAsyncMain", *(initialization_failure ? ["--initialization-failure"] : [])]
            else
              ["swift", "run", "OpenCoreGraphicsWindowCooperative"]
            end
          else
            ARGV
          end
reader, writer = IO.pipe
begin
  pid = Process.spawn(*command, out: writer, err: writer, pgroup: true)
rescue SystemCallError => error
  reader.close
  writer.close
  warn "WINDOW_COOPERATIVE RUNNER: spawn failed: #{error.message}"
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
  warn "WINDOW_COOPERATIVE RUNNER: TIMEOUT after #{timeout}s; incomplete"
  exit 1
end
patterns = if async_main && initialization_failure
  [/^WINDOW_ASYNC_MAIN before_first_window$/, /^WINDOW_ASYNC_MAIN initialization_error_observed$/,
   /^WINDOW_ASYNC_MAIN FAILURE_PATH_COMPLETE$/]
elsif async_main
  [/^WINDOW_ASYNC_MAIN before_first_window$/, /^WINDOW_ASYNC_MAIN first_window_created$/,
   /^WINDOW_ASYNC_MAIN second_window_created$/,
   /^WINDOW_ASYNC_MAIN COMPLETE frames_a=\d+ frames_b=\d+ cancelled_without_closing=true$/]
else
  [
  /^WINDOW_COOPERATIVE host_running$/,
  /^WINDOW_COOPERATIVE precancelled$/,
  /^WINDOW_COOPERATIVE duplicate_rejected$/,
  /^WINDOW_COOPERATIVE idle_seconds=\S+ idle_cpu_seconds=\S+ idle_cpu_percent_one_core=\S+$/,
  /^WINDOW_COOPERATIVE events_posted=20 events_received=20 event_latency_ms=\[.*\]$/,
  /^WINDOW_COOPERATIVE frames_a=\d+ frames_b=\d+ idle_draws_a=0 idle_draws_b=0 task_during_loop=true close_ms=\S+ second_survived_close=true cancellation_kept_visible=true restart_closed=true$/,
  /^WINDOW_COOPERATIVE COMPLETE$/
  ]
end
complete = patterns.all? { |pattern| output.match?(pattern) }
if status.success? && complete
  puts "WINDOW_COOPERATIVE RUNNER: PASSED"
  exit 0
end
warn "WINDOW_COOPERATIVE RUNNER: FAILED or INCOMPLETE (exit=#{status.exitstatus.inspect}, signal=#{status.termsig.inspect})"
exit 1

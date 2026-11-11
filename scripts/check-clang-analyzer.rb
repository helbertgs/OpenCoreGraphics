#!/usr/bin/env ruby

require "json"
require "open3"
require "optparse"
require "pathname"

ROOT = Pathname.new(__dir__).parent
SOURCE = "Sources/OpenCoreGraphicsSTB/stb_truetype.c"
BASELINE = ROOT.join("scripts/clang-analyzer-baseline.json")
NEGATIVE_FIXTURE = ROOT.join("scripts/fixtures/clang-analyzer-new-diagnostic.txt")

Diagnostic = Struct.new(
  :source,
  :line,
  :column,
  :severity,
  :message,
  :check,
  keyword_init: true
) do
  def signature
    [source, line, column, severity, check, message]
  end
end

def parse_diagnostics(output)
  diagnostics = []
  output.each_line do |line|
    match = line.match(/\A(.+?):(\d+):(\d+): (warning|error): (.*?)(?: \[([^\]]+)\])?\s*\z/)
    if match
      path = Pathname.new(match[1])
      relative_path = if path.absolute?
        path.relative_path_from(ROOT).to_s
      else
        path.cleanpath.to_s
      end
      diagnostics << Diagnostic.new(
        source: relative_path,
        line: Integer(match[2]),
        column: Integer(match[3]),
        severity: match[4],
        message: match[5],
        check: match[6]
      )
    elsif line.match?(/\b(?:warning|error):/)
      raise "Unrecognized compiler diagnostic format: #{line}"
    end
  end
  diagnostics
end

def baseline_counts
  data = JSON.parse(BASELINE.read)
  data.fetch("diagnostics").each_with_object(Hash.new(0)) do |entry, counts|
    unless entry.fetch("ownership") == "third-party"
      raise "Only explicitly classified third-party diagnostics may be baselined"
    end

    diagnostic = Diagnostic.new(
      source: entry.fetch("source"),
      line: entry.fetch("line"),
      column: entry.fetch("column"),
      severity: entry.fetch("severity"),
      message: entry.fetch("message"),
      check: entry.fetch("check")
    )
    counts[diagnostic.signature] += entry.fetch("count")
  end
end

def unexpected_diagnostics(diagnostics, allowed_counts)
  seen_counts = Hash.new(0)
  diagnostics.reject do |diagnostic|
    seen_counts[diagnostic.signature] += 1
    seen_counts[diagnostic.signature] <= allowed_counts.fetch(diagnostic.signature, 0)
  end
end

def self_test
  allowed = baseline_counts
  baseline_entry = JSON.parse(BASELINE.read).fetch("diagnostics").first
  baseline_diagnostic = Diagnostic.new(
    source: baseline_entry.fetch("source"),
    line: baseline_entry.fetch("line"),
    column: baseline_entry.fetch("column"),
    severity: baseline_entry.fetch("severity"),
    message: baseline_entry.fetch("message"),
    check: baseline_entry.fetch("check")
  )

  unless unexpected_diagnostics([baseline_diagnostic], allowed).empty?
    abort "Self-test failed: the recorded baseline diagnostic was not accepted"
  end

  duplicate = parse_diagnostics(NEGATIVE_FIXTURE.read)
  unless duplicate.length == 2 && unexpected_diagnostics(duplicate, allowed).length == 1
    abort "Self-test failed: a duplicate of the baseline diagnostic was not rejected"
  end

  relocated_fixture = duplicate.first.to_h.merge(line: duplicate.first.line + 1).then do |entry|
    "#{entry[:source]}:#{entry[:line]}:#{entry[:column]}: #{entry[:severity]}: " \
      "#{entry[:message]} [#{entry[:check]}]"
  end
  relocated = parse_diagnostics(relocated_fixture)
  unless unexpected_diagnostics(relocated, allowed).length == 1
    abort "Self-test failed: a diagnostic at a changed source location was not rejected"
  end

  begin
    parse_diagnostics("warning: unlocated analyzer warning\n")
    abort "Self-test failed: an unrecognized diagnostic format was accepted"
  rescue RuntimeError => error
    raise unless error.message.start_with?("Unrecognized compiler diagnostic format:")
  end

  puts "Self-test passed: exact baseline accepted; duplicate and relocated diagnostics rejected; unknown format fails closed."
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/check-clang-analyzer.rb [--self-test]"
  parser.on("--self-test", "Verify baseline matching with a negative fixture") do
    options[:self_test] = true
  end
end.parse!

if options[:self_test]
  self_test
  exit 0
end

command = [
  "clang",
  "--analyze",
  "-fno-color-diagnostics",
  "-Xanalyzer",
  "-analyzer-output=text",
  "-ISources/OpenCoreGraphicsSTB",
  SOURCE
]
stdout, stderr, status = Open3.capture3(*command, chdir: ROOT.to_s)
print stdout
warn stderr unless stderr.empty?
abort "Clang Static Analyzer failed with status #{status.exitstatus || status.termsig}" unless status.success?

diagnostics = parse_diagnostics(stdout + stderr)
unexpected = unexpected_diagnostics(diagnostics, baseline_counts)
unless unexpected.empty?
  warn "New Clang Static Analyzer diagnostic(s) outside the reviewed baseline:"
  unexpected.each do |diagnostic|
    warn "  #{diagnostic.source}:#{diagnostic.line}:#{diagnostic.column}: " \
      "#{diagnostic.severity}: #{diagnostic.message} [#{diagnostic.check}]"
  end
  exit 1
end

if diagnostics.empty?
  puts "Clang Static Analyzer completed with no diagnostics."
else
  puts "Clang Static Analyzer completed; #{diagnostics.length} diagnostic(s) match the reviewed baseline."
end

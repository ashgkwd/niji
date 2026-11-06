# frozen_string_literal: true

require "json"

module Niji
  # Turns a Result into what a person, an agent or a CI log reads.
  class Report
    attr_reader :result

    def initialize(result, all: false, config: Niji.config)
      @result = result
      @all = all
      @config = config
    end

    def success? = result.success?

    def to_s
      [ *finding_lines, *stale_lines, summary, *(success? ? [] : next_steps) ].join("\n")
    end

    def to_json(*)
      JSON.pretty_generate(
        success: success?,
        scanned: result.scanned,
        findings: shown.map { |finding| finding.to_h.compact },
        stale: result.stale
      )
    end

    def summary
      counts = result.findings.map(&:status).tally
      "-- #{result.scanned} files scanned: #{STATUSES.map { |status| "#{counts.fetch(status, 0)} #{status}" }.join(', ')}, #{result.stale.size} stale"
    end

    private

    def shown = @all ? result.findings : result.violations

    def finding_lines
      shown.map do |finding|
        via = finding.via ? " (via #{finding.via})" : ""
        reason = finding.reason ? "\n    #{finding.reason}" : ""
        format("%-8s %-5s %s:%d  %s%s%s", finding.status.upcase, finding.kind, finding.file, finding.line, finding.code, via, reason)
      end
    end

    def stale_lines
      result.stale.map { |entry| "STALE    #{entry['file']}  #{entry['code']}  (no longer a read that needs review, remove it from #{@config.allowlist_path})" }
    end

    def next_steps
      lines = [ "" ]
      if (example = result.violations.first)
        lines += <<~TEXT.lines(chomp: true)
          Each EXPOSED line prints one person's data where another person may see it.
          Fix it (show the viewer only what the page already prints for them), or, when
          it is safe, add an entry with a one-sentence reason to #{@config.allowlist_path}:
            - file: #{example.file}
              code: #{example.code.to_json}
              kind: #{example.kind}
              reason: <who sees this, and why the value is already theirs or public>
        TEXT
      end
      lines << "Remove each STALE entry from #{@config.allowlist_path}." if result.stale.any?
      lines << "Add --all to see every read and its verdict. The niji skill explains how to triage."
    end
  end
end

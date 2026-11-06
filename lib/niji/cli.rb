# frozen_string_literal: true

require "json"
require "optparse"

module Niji
  # `bundle exec niji`: boots the app (in the test environment unless
  # RAILS_ENV says otherwise, like CI), runs the check and exits 1 when a read
  # needs review. `--hook claude` speaks the Claude Code Stop hook protocol.
  class CLI
    HOOKS = %w[ claude ].freeze

    def initialize(argv, stdin: $stdin, stdout: $stdout, stderr: $stderr, root: Dir.pwd)
      @argv = argv
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @root = root
      @options = { all: false, format: "text", hook: nil }
    end

    def run
      parse!
      return 0 if @done

      boot
      report(Niji.check)
    rescue Niji::Error, OptionParser::ParseError => error
      @stderr.puts "niji: #{error.message}"
      2
    end

    # The exit code for a result: 0 clean, 1 needs review. In hook mode a
    # failure exits 2 so Claude Code shows the report to the agent and keeps it
    # working, once per stop: when the agent is already continuing because of
    # this hook (stop_hook_active), it may stop, so a leak it cannot fix never
    # loops forever.
    def report(result)
      report = Report.new(result, all: @options[:all])
      return hook(report) if @options[:hook]

      @stdout.puts(@options[:format] == "json" ? report.to_json : report.to_s)
      report.success? ? 0 : 1
    end

    private

    def parse!
      OptionParser.new do |parser|
        parser.banner = "Usage: niji [--all] [--format text|json] [--hook claude]"
        parser.separator ""
        parser.separator "Follows personal data from your models to every view, mailer, helper,"
        parser.separator "controller and service, and fails on a read nobody has reviewed."
        parser.separator ""
        parser.on("--all", "Also list the reads that are fine, with their verdict") { @options[:all] = true }
        parser.on("--format FORMAT", %w[ text json ], "Output format (text, json)") { |format| @options[:format] = format }
        parser.on("--hook AGENT", HOOKS, "Run as a hook for an agent (claude: the Stop hook)") { |agent| @options[:hook] = agent }
        parser.on("-v", "--version", "Print the version") do
          @stdout.puts "niji #{VERSION}"
          @done = true
        end
        parser.on("-h", "--help", "Print this help") do
          @stdout.puts parser
          @done = true
        end
      end.parse!(@argv)
    end

    def boot
      environment = File.join(@root, "config/environment.rb")
      raise Niji::Error, "run niji from the root of a Rails app (no config/environment.rb in #{@root})" unless File.exist?(environment)

      ENV["RAILS_ENV"] ||= "test"
      require environment
    end

    def hook(report)
      return 0 if report.success?

      input = begin
        JSON.parse(@stdin.read.to_s)
      rescue JSON::ParserError
        {}
      end
      @stderr.puts "niji found personal data that may reach the wrong person. Fix it or record why it is safe before you finish.\n\n#{report}"
      input["stop_hook_active"] ? 0 : 2
    end
  end
end

# frozen_string_literal: true

require "test_helper"
require "stringio"

# The command line: exit codes for CI, JSON for tools, and the Claude Code
# Stop hook protocol.
class CliTest < ActiveSupport::TestCase
  CLEAN = Niji::Result.new(findings: [], stale: [], scanned: 3)

  setup do
    @leaky = Niji.check
    @stdout = StringIO.new
    @stderr = StringIO.new
  end

  def cli(*argv, stdin: "")
    Niji::CLI.new(argv, stdin: StringIO.new(stdin), stdout: @stdout, stderr: @stderr).tap { |cli| cli.send(:parse!) }
  end

  test "exits 0 when clean and 1 when a read needs review" do
    assert_equal 0, cli.report(CLEAN)
    assert_equal 1, cli.report(@leaky)
    assert_match "EXPOSED", @stdout.string
  end

  test "--all lists the reads that are fine too" do
    cli("--all").report(@leaky)

    assert_match "OWN", @stdout.string
    assert_match "ALLOWED", @stdout.string
    assert_match "Review#user_name is the reviewer's public display name", @stdout.string
  end

  test "--format json is machine readable" do
    cli("--format", "json").report(@leaky)
    json = JSON.parse(@stdout.string)

    assert_equal false, json["success"]
    assert_equal [ "@spotlight_agent.maker.name", "avatar_tag review.user" ], json["findings"].map { |finding| finding["code"] }
  end

  test "as a Claude Code Stop hook it blocks once and explains on stderr" do
    assert_equal 0, cli("--hook", "claude").report(CLEAN)
    assert_equal 2, cli("--hook", "claude", stdin: '{"stop_hook_active":false}').report(@leaky)
    assert_match "avatar_tag review.user", @stderr.string
    assert_empty @stdout.string

    assert_equal 0, cli("--hook", "claude", stdin: '{"stop_hook_active":true}').report(@leaky), "a leak the agent cannot fix must not loop"
  end

  test "refuses to run outside a Rails app" do
    Dir.mktmpdir do |dir|
      status = Niji::CLI.new([], stdout: @stdout, stderr: @stderr, root: dir).run

      assert_equal 2, status
      assert_match "config/environment.rb", @stderr.string
    end
  end

  test "--version and --help print and exit 0" do
    assert_equal 0, Niji::CLI.new([ "--version" ], stdout: @stdout).run
    assert_equal 0, Niji::CLI.new([ "--help" ], stdout: @stdout).run
    assert_match "niji #{Niji::VERSION}", @stdout.string
    assert_match "--hook", @stdout.string
  end
end

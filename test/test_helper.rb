# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require_relative "dummy/config/environment"
require "active_support/test_case"
require "minitest/autorun"
require "tmpdir"
require "niji"
require "niji/cli"

ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:users) { |t| t.string :name; t.string :email_address }
  create_table(:agents) { |t| t.string :name; t.references :maker }
  create_table(:reviews) { |t| t.references :user; t.references :agent }
  create_table(:blogs) { |t| t.references :author; t.references :invited_by }
end

module NijiTestHelper
  SOURCES = Niji.sources

  # Takes the files as a hash, or as "path" => text keyword arguments.
  def analyze(files = nil, allowlist: [], config: Niji::Configuration.new, sources: SOURCES, **paths)
    Niji.analyze(files || paths.transform_keys(&:to_s), sources:, allowlist:, config:)
  end

  def status_of(result, code)
    result.findings.find { |finding| finding.code == code }&.status
  end

  def statuses(result) = result.findings.to_h { |finding| [ finding.code, finding.status ] }

  # The setup of an app whose ApplicationController requires an admin, and
  # where a controller opens up with allow_non_admin_access.
  def admin_by_default
    Niji::Configuration.new.tap do |config|
      config.admin_by_default = true
      config.guard_lowering_methods += %i[ allow_non_admin_access ]
    end
  end
end

ActiveSupport::TestCase.include NijiTestHelper

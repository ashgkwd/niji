# frozen_string_literal: true

require "niji"

module Niji
  # Minitest assertions. Include them in a test case:
  #
  #   class NijiTest < ActiveSupport::TestCase
  #     include Niji::Assertions
  #
  #     test "no person's data reaches another person unreviewed" do
  #       assert_no_pii_exposure
  #     end
  #   end
  module Assertions
    def assert_no_pii_exposure(result = Niji.check)
      report = Report.new(result)
      assert report.success?, -> { "niji found reads that need review:\n#{report}" }
    end
  end
end

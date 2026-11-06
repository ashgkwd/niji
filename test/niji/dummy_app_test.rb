# frozen_string_literal: true

require "test_helper"
require "niji/assertions"

# The whole check on the dummy app, which keeps both leaks that started niji:
# the digest line that named another maker, and the avatar helper that put a
# reviewer's email in the alt text of every public review. A check that has
# only ever passed proves little, so these must stay red.
class DummyAppTest < ActiveSupport::TestCase
  setup { @result = Niji.check }

  test "reports exactly the two original leaks" do
    assert_equal [
      [ "app/views/maker_mailer/daily_reviews_digest.html.erb", 3, "@spotlight_agent.maker.name", :name, nil ],
      [ "app/views/reviews/_review.html.erb", 2, "avatar_tag review.user", :email, "avatar_tag" ]
    ], @result.violations.map { |finding| [ finding.file, finding.line, finding.code, finding.kind, finding.via ] }
    assert_empty @result.stale
  end

  test "gives every other read the verdict a reader of the app would" do
    assert_equal({
      "maker.email_address" => :recipient,
      "@maker.greeting_name" => :recipient,
      "review.user_name" => :allowed,
      "review.user.email_address" => :admin,
      "avatar_tag Current.user" => :own,
      "Current.user&.name" => :own,
      "Current.user.name" => :own,
      "Current.user.email_address" => :own,
      "user.name_with_email" => :admin
    }, statuses(@result).except("@spotlight_agent.maker.name", "avatar_tag review.user"))
  end

  test "a reviewer name that falls back to an email turns the review red and its entry stale" do
    sources = Niji.sources.map(&:dup)
    sources.first.instance_variable_set(:@derived, sources.first.derived.merge(user_name: :email))

    result = Niji.analyze(Niji.app_files, sources:, allowlist: Niji.load_allowlist)

    assert_equal :exposed, status_of(result, "review.user_name")
    assert_equal [ "review.user_name" ], result.stale.map { |entry| entry["code"] }
  end

  test "the report says what to do next" do
    report = Niji::Report.new(@result).to_s

    assert_match "EXPOSED  email app/views/reviews/_review.html.erb:2  avatar_tag review.user (via avatar_tag)", report
    assert_match "files scanned: 2 exposed, 1 allowed, 2 admin, 2 recipient, 4 own, 0 stale", report
    assert_match "config/pii_exposure.yml", report
  end

  test "the assertion fails with the report" do
    test_case = Class.new(Minitest::Test) { include Niji::Assertions }.new("probe")

    error = assert_raises(Minitest::Assertion) { test_case.assert_no_pii_exposure(@result) }
    assert_match "avatar_tag review.user", error.message
  end
end

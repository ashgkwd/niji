# frozen_string_literal: true

require "test_helper"

# What niji derives from the person model before it reads a single view.
class SourcesTest < ActiveSupport::TestCase
  setup { @user = SOURCES.first }

  test "readers are the declared columns, their aliases and every method that returns them" do
    assert_equal({ name: :name, email_address: :email, email: :email }, @user.readers.slice(:name, :email_address, :email))
    assert_equal :email, @user.readers[:name_with_email], "a method that reaches a name and an email is an email"
    assert_equal :name, @user.readers[:greeting_name], "a method from a concern counts"
    assert_not_includes @user.readers.keys, :verified?
  end

  test "holders are the associations that point at the person model" do
    %w[ user maker author invited_by ].each { |holder| assert_includes @user.holders, holder }
    assert_not_includes @user.holders, "agent"
  end

  test "a method on another model that hands a name on is a source" do
    assert_equal :name, @user.derived[:user_name], "Review#user_name hands user.name on"
  end

  test "Review#user_name is a name and never an email" do
    assert_equal "Anonymous", Review.new.user_name
    assert_equal "Maker Two", Review.new(user: User.new(name: "Maker Two")).user_name
    assert_equal "Anonymous", Review.new(user: User.new(email_address: "nameless@example.com")).user_name
  end

  test "a method that falls back to an email is derived as an email" do
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      root.join("app/models").mkpath
      root.join("app/models/fallback_review.rb").write(<<~RUBY)
        class FallbackReview < ApplicationRecord
          belongs_to :user
          def user_name = user&.name.presence || user&.email_address
        end
      RUBY
      Object.const_set(:FallbackReview, Class.new(ApplicationRecord) { self.table_name = "reviews" }) unless defined?(FallbackReview)
      config = Niji::Configuration.new.tap { |c| c.root = root }

      assert_equal :email, Niji::Sources.new(User, config:).derived[:user_name]
    end
  end

  test "a model without the constant can list its columns in the configuration" do
    config = Niji::Configuration.new.tap { |c| c.attributes_constant = :MISSING }
    error = assert_raises(Niji::Error) { Niji::Sources.new(User, config:) }
    assert_match %(config.personal_attributes["User"]), error.message

    config.personal_attributes = { "User" => %w[ email_address ] }
    assert_equal({ email_address: :email, email: :email }, Niji::Sources.new(User, config:).readers.slice(:email_address, :email))
  end

  test "kinds come from the column name unless configured" do
    config = Niji::Configuration.new
    assert_equal :email, Niji.kind_of(:email_address, config:)
    assert_equal :phone, Niji.kind_of(:mobile_number, config:)
    assert_equal :name, Niji.kind_of(:full_name, config:)
    assert_equal :date_of_birth, Niji.kind_of(:date_of_birth, config:)

    config.kinds = { "handle" => :name }
    assert_equal :name, Niji.kind_of(:handle, config:)
  end
end

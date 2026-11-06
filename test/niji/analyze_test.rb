# frozen_string_literal: true

require "test_helper"

# The reads niji must report, and the ones it must leave alone, on files given
# as strings so each shape is visible in the test.
class AnalyzeTest < ActiveSupport::TestCase
  test "reports the digest spotlight that named another listing's maker" do
    result = analyze("app/views/maker_mailer/daily_reviews_digest.html.erb" => <<~ERB)
      <% spotlight_maker_name = @spotlight_agent.maker.name.presence || t(".fellow_maker") %>
      <%= t(".heading", maker_name: spotlight_maker_name) %>
    ERB

    assert_equal :exposed, status_of(result, "@spotlight_agent.maker.name")
    assert_equal [ 1 ], result.violations.map(&:line)
  end

  test "reports a helper that prints a person's email at the views that call it with someone else" do
    result = analyze(
      "app/helpers/demo_helper.rb" => <<~RUBY,
        module DemoHelper
          def avatar(user)
            image_tag "x.png", alt: user.name_with_email
          end
        end
      RUBY
      "app/views/reviews/_demo.html.erb" => "<%= avatar review.user %>\n<%= avatar Current.user %>\n"
    )

    assert_equal %i[ exposed own ], result.findings.map(&:status)
    assert_equal [ "avatar" ], result.findings.filter_map(&:via).uniq
    assert_equal [ :email ], result.findings.map(&:kind).uniq
  end

  test "a helper in a path that is not a relay is judged where it reads" do
    config = Niji::Configuration.new.tap { |c| c.relay_paths = [] }
    result = analyze({ "app/helpers/demo_helper.rb" => "module DemoHelper\n  def avatar(user) = user.name\nend\n", "app/views/a/_b.html.erb" => "<%= avatar Current.user %>" }, config:)

    assert_equal [ "user.name" ], result.violations.map(&:code)
  end

  test "reports a model method that hands a name on, wherever it is called" do
    result = analyze("app/views/reviews/_demo.html.erb" => "<%= review.user_name %>")

    assert_equal :exposed, status_of(result, "review.user_name")
    assert_equal :name, result.findings.first.kind
  end

  test "the viewer's own data is fine" do
    result = analyze("app/views/reviews/_demo.html.erb" => "<%= Current.user.name %> <%= Current.user.email_address %>")

    assert_equal %i[ own own ], result.findings.map(&:status)
  end

  test "the viewer can be current_user, for Devise" do
    config = Niji::Configuration.new.tap { |c| c.viewer_expressions += %w[ current_user ] }
    result = analyze({ "app/views/a/_b.html.erb" => "<%= current_user.email %> <%= other.user.email %>" }, config:)

    assert_equal({ "current_user.email" => :own, "other.user.email" => :exposed }, statuses(result))
  end

  test "an admin check clears its own branch only" do
    result = analyze("app/views/reviews/_demo.html.erb" => <<~ERB)
      <% if admin? %><%= agent.maker.email_address %><% else %><%= other.maker.email_address %><% end %>
      <% unless admin? %><%= one.maker.name %><% else %><%= two.maker.name %><% end %>
      <% if admin? || owner? %><%= any.maker.name %><% end %>
      <% if Current.user.admin? && ready? %><%= both.maker.name %><% end %>
    ERB

    assert_equal :admin, status_of(result, "agent.maker.email_address")
    assert_equal :exposed, status_of(result, "other.maker.email_address")
    assert_equal :exposed, status_of(result, "one.maker.name")
    assert_equal :admin, status_of(result, "two.maker.name")
    assert_equal :exposed, status_of(result, "any.maker.name"), "admin? || owner? is not an admin check"
    assert_equal :admin, status_of(result, "both.maker.name")
  end

  test "admin paths are admin only, and can be configured" do
    config = Niji::Configuration.new.tap { |c| c.admin_paths += [ "app/views/dashboard/", %r{\Aapp/views/ops_} ] }
    result = analyze({
      "app/views/admin/users/index.html.erb" => "<%= a.maker.email %>",
      "app/views/dashboard/demo.html.erb" => "<%= b.maker.email %>",
      "app/views/ops_reports/show.html.erb" => "<%= c.maker.email %>",
      "app/views/agents/show.html.erb" => "<%= d.maker.email %>"
    }, config:)

    assert_equal({ "a.maker.email" => :admin, "b.maker.email" => :admin, "c.maker.email" => :admin, "d.maker.email" => :exposed }, statuses(result))
  end

  test "the block variable of a scope chain on the person model holds a person" do
    result = analyze("app/helpers/makers_helper.rb" => <<~RUBY)
      module MakersHelper
        def maker_options = User.where(verified: true).map { |person| [ person.name_with_email, person.id ] }
        def maker_names = User.all.map { it.name }
        def agent_names = Agent.all.map { |person| person.name }
      end
    RUBY

    assert_equal [ "person.name_with_email", "it.name" ], result.violations.map(&:code)
  end

  test "a mail template that greets the person its action mails to is the recipient's own" do
    result = analyze(
      "app/mailers/demo_mailer.rb" => <<~RUBY,
        class DemoMailer < ApplicationMailer
          def hello(maker)
            @maker = maker
            mail to: maker.email, subject: "Hi"
          end

          def about(maker, other)
            @maker = maker
            @other = other
            mail to: maker.email, subject: "About"
          end
        end
      RUBY
      "app/views/demo_mailer/hello.html.erb" => "Hi <%= @maker.name %>",
      "app/views/demo_mailer/about.html.erb" => "Hi <%= @maker.name %>, <%= @other.maker.name %> is waiting"
    )

    assert_equal :recipient, result.findings.find { |finding| finding.file.end_with?("hello.html.erb") }.status
    about = result.findings.select { |finding| finding.file.end_with?("about.html.erb") }
    assert_equal %i[ recipient exposed ], about.map(&:status)
    assert_equal [ "@other.maker.name" ], result.violations.map(&:code)
  end

  test "a namespaced mailer finds its templates" do
    result = analyze(
      "app/mailers/makers/digest_mailer.rb" => "module Makers\n  class DigestMailer < ApplicationMailer\n    def daily(maker)\n      @maker = maker\n      mail to: maker.email\n    end\n  end\nend\n",
      "app/views/makers/digest_mailer/daily.text.erb" => "Hi <%= @maker.name %>"
    )

    assert_empty result.violations
  end

  test "an allowlist entry clears a read, and goes stale when the read goes" do
    files = { "app/views/reviews/_demo.html.erb" => "<%= review.user_name %>" }
    entry = { "file" => "app/views/reviews/_demo.html.erb", "code" => "review.user_name", "reason" => "public" }

    allowed = analyze(files, allowlist: [ entry ])
    assert_equal :allowed, status_of(allowed, "review.user_name")
    assert_equal "public", allowed.findings.first.reason
    assert allowed.success?

    stale = analyze({ "app/views/reviews/_demo.html.erb" => "<%= 1 %>" }, allowlist: [ entry ])
    assert_equal [ entry ], stale.stale
    assert_not stale.success?
  end

  test "an entry pinned to a name does not clear a read that has become an email" do
    files = { "app/views/reviews/_demo.html.erb" => "<%= review.user.email_address %>" }
    entry = { "file" => "app/views/reviews/_demo.html.erb", "code" => "review.user.email_address", "kind" => "name", "reason" => "public" }

    result = analyze(files, allowlist: [ entry ])

    assert_equal :exposed, status_of(result, "review.user.email_address")
    assert_equal [ entry ], result.stale
  end

  test "a template that does not parse stops the check instead of being skipped" do
    error = assert_raises(Niji::Error) { analyze("app/views/reviews/_broken.html.erb" => "<% if %>") }
    assert_match "app/views/reviews/_broken.html.erb", error.message
  end

  test "paths match as prefixes, exact paths, globs and regexps" do
    assert Niji.path_match?([ "app/views/admin/" ], "app/views/admin/users/index.html.erb")
    assert Niji.path_match?([ "app/views/admin" ], "app/views/admin/index.html.erb")
    assert_not Niji.path_match?([ "app/views/admin" ], "app/views/administrators/index.html.erb")
    assert Niji.path_match?([ "app/mailers/admin_mailer.rb" ], "app/mailers/admin_mailer.rb")
    assert Niji.path_match?([ "app/views/*/admin_*.erb" ], "app/views/agents/admin_row.erb")
    assert Niji.path_match?([ /ops/ ], "app/views/ops/show.html.erb")
  end
end

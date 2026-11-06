# frozen_string_literal: true

require "test_helper"

# Which controllers serve admins only, read from the controllers themselves.
class AdminScopesTest < ActiveSupport::TestCase
  BASE = "module Staff\n  class BaseController < ApplicationController\n    before_action :require_admin\n  end\nend\n"

  test "a controller that inherits an admin guard serves admins only, a partial does not" do
    result = analyze(
      "app/controllers/staff/base_controller.rb" => BASE,
      "app/controllers/staff/users_controller.rb" => "module Staff\n  class UsersController < BaseController\n  end\nend\n",
      "app/views/staff/users/index.html.erb" => "<%= @maker.name %>",
      "app/views/staff/users/_row.html.erb" => "<%= maker.name %>"
    )

    assert_equal({ "@maker.name" => :admin, "maker.name" => :exposed }, statuses(result))
  end

  test "the guard can come from a compact superclass name, a concern, or a direct call" do
    result = analyze(
      "app/controllers/staff/base_controller.rb" => BASE,
      "app/controllers/staff/reports_controller.rb" => "class Staff::ReportsController < Staff::BaseController\nend\n",
      "app/controllers/concerns/admin_only.rb" => "module AdminOnly\n  extend ActiveSupport::Concern\n  included do\n    before_action :require_admin\n  end\nend\n",
      "app/controllers/payouts_controller.rb" => "class PayoutsController < ApplicationController\n  include AdminOnly\nend\n",
      "app/controllers/exports_controller.rb" => "class ExportsController < ApplicationController\n  require_admin!\nend\n",
      "app/views/staff/reports/show.html.erb" => "<%= a.maker.name %>",
      "app/views/payouts/show.html.erb" => "<%= b.maker.name %>",
      "app/views/exports/show.html.erb" => "<%= c.maker.name %>"
    )

    assert_equal %i[ admin ], result.findings.map(&:status).uniq
  end

  test "a guard on some actions only, or one that is skipped, leaves the controller open" do
    result = analyze(
      "app/controllers/staff/base_controller.rb" => BASE,
      "app/controllers/staff/public_controller.rb" => "module Staff\n  class PublicController < BaseController\n    skip_before_action :require_admin, only: :show\n  end\nend\n",
      "app/controllers/agents_controller.rb" => "class AgentsController < ApplicationController\n  before_action :require_admin, except: :show\nend\n",
      "app/controllers/home_controller.rb" => "class HomeController < ApplicationController\n  def index\n    require_admin!\n  end\nend\n",
      "app/views/staff/public/show.html.erb" => "<%= a.maker.name %>",
      "app/views/agents/show.html.erb" => "<%= b.maker.name %>",
      "app/views/home/index.html.erb" => "<%= c.maker.name %>"
    )

    assert_equal %i[ exposed ], result.findings.map(&:status).uniq
  end

  test "a method the app defines to skip the admin guard lowers it where it is called" do
    authorization = <<~RUBY
      module Authorization
        extend ActiveSupport::Concern
        included do
          before_action :require_admin
        end
        class_methods do
          def allow_non_admin_access(**options)
            skip_before_action :require_admin, **options
          end

          def open_to_makers = allow_non_admin_access
        end
      end
    RUBY
    result = analyze(
      "app/controllers/concerns/authorization.rb" => authorization,
      "app/controllers/application_controller.rb" => "class ApplicationController < ActionController::Base\n  include Authorization\nend\n",
      "app/controllers/makers_controller.rb" => "class MakersController < ApplicationController\nend\n",
      "app/controllers/agents_controller.rb" => "class AgentsController < ApplicationController\n  allow_non_admin_access only: :show\nend\n",
      "app/controllers/studios_controller.rb" => "class StudiosController < ApplicationController\n  open_to_makers\nend\n",
      "app/views/makers/index.html.erb" => "<%= a.maker.email %>",
      "app/views/agents/show.html.erb" => "<%= b.maker.email %>",
      "app/views/studios/show.html.erb" => "<%= c.maker.email %>"
    )

    assert_equal({ "a.maker.email" => :admin, "b.maker.email" => :exposed, "c.maker.email" => :exposed }, statuses(result))
  end

  test "with admin_by_default, a view of a controller that keeps the default is admin only, a partial is not" do
    result = analyze({
      "app/controllers/closed_controller.rb" => "class ClosedController < ApplicationController\nend\n",
      "app/views/closed/show.html.erb" => "<%= @maker.name %>",
      "app/views/closed/_row.html.erb" => "<%= maker.name %>"
    }, config: admin_by_default)

    assert_equal({ "@maker.name" => :admin, "maker.name" => :exposed }, statuses(result))
  end

  test "with admin_by_default, a controller that lowers the guard, directly or through a concern, opens its views" do
    result = analyze({
      "app/controllers/concerns/lowers_guard.rb" => "module LowersGuard\n  def self.included(base) = base.allow_non_admin_access\n  allow_non_admin_access\nend\n",
      "app/controllers/anonymous_controller.rb" => "class AnonymousController < ApplicationController\n  allow_unauthenticated_access\nend\n",
      "app/controllers/viaconcern_controller.rb" => "class ViaconcernController < ApplicationController\n  include LowersGuard\nend\n",
      "app/views/anonymous/show.html.erb" => "<%= @maker.name %>",
      "app/views/viaconcern/show.html.erb" => "<%= @author.name %>"
    }, config: admin_by_default)

    assert_equal %i[ exposed exposed ], result.findings.map(&:status)
  end

  test "without admin_by_default, a plain controller is open" do
    result = analyze(
      "app/controllers/closed_controller.rb" => "class ClosedController < ApplicationController\nend\n",
      "app/views/closed/show.html.erb" => "<%= @maker.name %>"
    )

    assert_equal [ :exposed ], result.findings.map(&:status)
  end
end

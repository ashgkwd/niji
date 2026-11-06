# frozen_string_literal: true

module Niji
  # Every project-specific choice the check makes. The defaults fit a Rails 8.1
  # app made with `bin/rails generate authentication` (User, email_address,
  # Current.user) and an admin area under app/controllers/admin. Change them in
  # config/initializers/niji.rb; docs/configuration.md explains each one.
  class Configuration
    # The models that hold a person. Each lists what identifies a person in a
    # constant (PERSONAL_ATTRIBUTES by default) or in `personal_attributes`.
    attr_accessor :models

    # The constant on each model that lists its personal columns.
    attr_accessor :attributes_constant

    # Model name => columns, for a model that does not declare the constant.
    attr_accessor :personal_attributes

    # Column name => kind label for the report and for `kind:` in the allowlist.
    # Unlisted columns get a label from their name (see Niji.kind_of).
    attr_accessor :kinds

    # Extra names a person travels under that no association reveals
    # (a helper parameter called `reviewer`, a local called `member`).
    attr_accessor :extra_holders

    # Expressions that are the person looking at the page. A read on one of
    # them is the viewer's own data.
    attr_accessor :viewer_expressions

    # Files to scan, as a glob under the app root, and paths to leave out.
    attr_accessor :scanned, :skipped_paths

    # Paths only admins reach: prefixes ending in "/", exact paths, globs or
    # regexps.
    attr_accessor :admin_paths

    # Methods whose truthiness means the viewer is an admin. A branch guarded
    # by one of them (`if admin?`, `if Current.user.admin?`) is admin-only.
    attr_accessor :admin_predicates

    # True when every controller requires an admin unless it lowers the guard
    # (an app where ApplicationController itself requires an admin).
    attr_accessor :admin_by_default

    # Methods that make a controller admin-only when run before every action:
    # `before_action :require_admin` or a class-level `require_admin` call.
    attr_accessor :admin_markers

    # Class-level calls that open a controller to non-admins. Any
    # `skip_before_action` of an admin marker counts too.
    attr_accessor :guard_lowering_methods

    # Files whose methods hand a person's data to whoever calls them. A read on
    # a parameter there is judged at every call site, with the argument given.
    attr_accessor :relay_paths

    # The reviewed exceptions, relative to the app root.
    attr_accessor :allowlist_path

    # The app root. Defaults to Rails.root.
    attr_writer :root

    def initialize
      @models = %w[ User ]
      @attributes_constant = :PERSONAL_ATTRIBUTES
      @personal_attributes = {}
      @kinds = {}
      @extra_holders = []
      @viewer_expressions = [ "Current.user" ]
      @scanned = "app/**/*.{rb,erb,jbuilder,builder}"
      @skipped_paths = %w[ app/models/ app/javascript/ app/assets/ ]
      @admin_paths = %w[ app/controllers/admin/ app/views/admin/ app/mailers/admin_mailer.rb app/views/admin_mailer/ ]
      @admin_predicates = %i[ admin? ]
      @admin_by_default = false
      @admin_markers = %i[ require_admin require_admin! authenticate_admin! ]
      @guard_lowering_methods = %i[ allow_unauthenticated_access ]
      @relay_paths = %w[ app/helpers/ app/services/ ]
      @allowlist_path = "config/pii_exposure.yml"
    end

    def root
      Pathname(@root || Rails.root)
    end
  end
end

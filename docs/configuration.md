# Configuring niji

niji reads most of what it needs from your code: the columns from the model, the holders from the associations, the admin guard from the controllers. The initializer covers the few choices it cannot read. `bin/rails generate niji:install` writes `config/initializers/niji.rb` with the common ones.

```ruby
Niji.configure do |config|
  config.models = %w[ User ]
end
```

## Who is a person

| Option | Default | What it does |
|---|---|---|
| `models` | `%w[ User ]` | The models that hold a person. Add `Customer`, `Member` or any other. |
| `attributes_constant` | `:PERSONAL_ATTRIBUTES` | The constant on each model that lists its personal columns. |
| `personal_attributes` | `{}` | `"Model" => %w[ columns ]`, for a model you would rather not touch. The constant wins when both exist. |
| `kinds` | `{}` | `"column" => :label`, the kind reported for a column. Unlisted columns get `email`, `phone` or `name` from their name, or the column name itself. |
| `extra_holders` | `[]` | Names a person travels under that no association reveals, such as a partial local called `person`. |

Choose the columns by asking whether the value identifies a person or lets someone reach them: names, emails, phone numbers, addresses, dates of birth, IP addresses, external account IDs. Leave out what describes the account only, such as roles or flags.

## Who is looking

| Option | Default | What it does |
|---|---|---|
| `viewer_expressions` | `[ "Current.user" ]` | Expressions that are the signed-in viewer. Add `"current_user"` for Devise, or `"Current.member"`. A read on one of them is `own`. |

## Who is an admin

| Option | Default | What it does |
|---|---|---|
| `admin_markers` | `%i[ require_admin require_admin! authenticate_admin! ]` | Methods that make a controller admin-only when they run before every action. |
| `guard_lowering_methods` | `%i[ allow_unauthenticated_access ]` | Class-level calls that open a controller to people who are not admins. Methods your app defines that call these, or that `skip_before_action` a marker, are found by themselves. |
| `admin_by_default` | `false` | Set it when `ApplicationController` requires an admin and controllers opt out. It is the same as a marker on the root controller. |
| `admin_paths` | `app/controllers/admin/`, `app/views/admin/`, `app/mailers/admin_mailer.rb`, `app/views/admin_mailer/` | Files only admins reach. |
| `admin_predicates` | `%i[ admin? ]` | Methods behind `if admin?` style checks. The branch they guard is admin-only. `admin? || owner?` is not an admin check, and `admin? && ready?` is. |

Paths in `admin_paths`, `relay_paths` and `skipped_paths` can be a prefix ending in `/`, an exact path, a glob (`app/views/*/admin_*.erb`) or a regexp.

Three common setups:

```ruby
# An Admin:: namespace with a base controller (the default)
#   class Admin::BaseController < ApplicationController
#     before_action :require_admin
config.admin_markers = %i[ require_admin ]

# Every controller requires an admin unless it opts out
config.admin_by_default = true
config.guard_lowering_methods = %i[ allow_unauthenticated_access allow_non_admin_access ]

# Devise with an admin flag
config.viewer_expressions = [ "current_user" ]
config.admin_markers = %i[ authenticate_admin! ]
config.admin_predicates = %i[ admin? ]
```

## What is scanned

| Option | Default | What it does |
|---|---|---|
| `scanned` | `"app/**/*.{rb,erb,jbuilder,builder}"` | The files niji reads, as a glob under the app root. |
| `skipped_paths` | `app/models/`, `app/javascript/`, `app/assets/` | Left out. Models are the data layer, and what they hand on is read again where it is printed. |
| `relay_paths` | `app/helpers/`, `app/services/` | Files whose methods hand a person's data to their caller. A read on a parameter there is judged at every call site. Add `app/presenters/` or `app/components/` if you use them. |
| `allowlist_path` | `"config/pii_exposure.yml"` | The reviewed exceptions. |
| `root` | `Rails.root` | The app root. |

## The allowlist

```yaml
- file: app/views/blogs/_details.html.erb   # exactly as reported
  code: "blog.author&.name"                  # exactly as reported
  kind: name                                 # optional: stops matching if the read becomes an email
  reason: A published post names its author on a public page.
```

Group entries under comments that say why a group is safe ("Public by design", "The viewer's own, through an instance variable"). It makes review faster and keeps reasons honest. The `niji` skill has the triage steps agents follow before they write an entry.

## Environment

`bundle exec niji` boots the app with `RAILS_ENV=test` unless `RAILS_ENV` is set. The check reads code and model metadata only. It needs no database rows, and it never writes.

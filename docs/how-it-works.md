# How niji works

niji answers one question for every place a Rails app prints a person's data: does this show the viewer something the page already prints for them in plain text? It answers by tracing from the model outward, because a search that starts at the screen only sees the last hop of a path that often has several.

The code lives in `lib/niji/`. Each section below names the file that does the work.

## 1. Sources: what identifies a person (`sources.rb`, `method_bodies.rb`)

Each person model declares its personal columns once:

```ruby
class User < ApplicationRecord
  PERSONAL_ATTRIBUTES = %w[ name email_address ].freeze
end
```

From that list niji derives the readers, the method names that return personal data:

- the columns themselves;
- their aliases (`alias_attribute :email, :email_address`), read from `User.attribute_aliases`;
- every method of the model and its concerns that calls a reader, repeated until the list stops growing. `name_with_email` calls `name` and `email_address`, so it is a reader. A method that calls `name_with_email` is one too.

Each reader has a kind: `email`, `phone`, `name` or the column name. A reader that reaches several columns takes the most revealing kind, so `name_with_email` is an `email`.

niji then reads the other models in `app/models` for methods that hand a reader's value along, such as `Review#user_name`, which returns `user&.name.presence || "Anonymous"`. Those are derived readers. They are recognised on any receiver, because a model method has no association to type it by.

## 2. Holders: the names a person travels under (`sources.rb`)

A reader only matters when it is called on something that can hold a person. niji loads the app and asks every model's associations which ones point at the person model. In a typical app that gives `user`, `maker`, `author`, `invited_by` and so on. The model's own name (`user`) is a holder too, and `config.extra_holders` adds names no association reveals.

A receiver holds a person when:

- it is a method call, local variable or instance variable named after a holder (`review.user`, `maker`, `@author`);
- it is the block variable of a scope chain that starts at the person model (`User.verified.map { |person| person.name }`, or `it` in Ruby 3.4).

## 3. Reads: every file a viewer can reach (`scanner.rb`)

niji parses every file under `app/` (except `app/models`, `app/javascript` and `app/assets`) with Prism, Ruby's own parser. ERB templates are compiled first by ActionView's own Erubi handler, exactly as Rails compiles them, so an `<% if admin? %>` around a section stays in the syntax tree as a real `if`. Jbuilder and Builder templates are Ruby already.

A read is a call of a reader on a holder. For each read, the scanner records:

- whether the receiver is the viewer (`config.viewer_expressions`, `Current.user` by default);
- whether it sits in an admin-only place: a file under `config.admin_paths`, or a branch guarded by `config.admin_predicates` (`if admin?`, `if Current.user.admin? && ...`, the `else` of `unless admin?`);
- whether it is a mail's addressee: inside `to:`, `cc:` or `bcc:`.

A template that does not parse stops the check. Skipping it would hide its reads.

## 4. Relays: helpers judged where they are called (`niji.rb`)

A helper or service (`config.relay_paths`) that reads a reader from its own parameter is a relay:

```ruby
def avatar_tag(user)
  image_tag "avatar.png", alt: user.name_with_email
end
```

The read inside the helper says nothing about who sees it. So niji reports each call of the helper instead, with the argument it is given. `avatar_tag Current.user` is the viewer's own. `avatar_tag review.user` is exposed. This rule found the leak that started niji.

## 5. Admin-only controllers (`admin_scopes.rb`)

niji reads the controllers to learn which ones serve admins only. A controller is admin-only when:

- it runs one of `config.admin_markers` before every action: `before_action :require_admin` with no `only:`, `except:`, `if:` or `unless:`, or a bare `require_admin` call at class level;
- or it inherits that from its superclass (`Admin::UsersController < Admin::BaseController`), or from an included concern (`included do before_action :require_admin end`);
- or `config.admin_by_default` is on and nothing above it lowers the guard;

and nothing lowers the guard for it. Lowering is any of `config.guard_lowering_methods` (`allow_unauthenticated_access` by default), any `skip_before_action` of a marker (even for one action), and any method your app defines whose body does one of those. That last rule means a concern like this needs no configuration:

```ruby
module Authorization
  extend ActiveSupport::Concern
  included { before_action :require_admin }
  class_methods do
    def allow_non_admin_access(**options) = skip_before_action(:require_admin, **options)
  end
end
```

Every full template in an admin-only controller's view directory is admin-only. A partial is judged on its own reads, because another controller's page can render it.

Where the guard is unsure, niji treats the controller as open, so its reads are reported. A false alarm costs a sentence in the allowlist. A missed leak costs someone's privacy.

## 6. Mail recipients (`scanner.rb`, `niji.rb`)

For each mailer action niji notes who the mail is addressed to: the instance variable in `to: @maker.email_address`, or the one assigned from the expression in `to: maker.email` (`@maker = maker`). In that action's templates, a read on that variable greets the recipient. Everything else in the mail is judged like any other read, which is how niji catches a digest that names a second person.

## 7. The verdict and the allowlist (`niji.rb`)

Each read gets one status: `own`, `recipient`, `admin`, or `exposed`. An exposed read is `allowed` when `config/pii_exposure.yml` has an entry with the same file and the same source code, and the same kind when the entry pins one.

An entry that matches nothing is `stale` and fails the run. An entry needs `file`, `code` and `reason`, and a missing one stops the check with an error.

## What niji leaves to tests

niji follows direct reads, relays and derived model methods. These shapes get past it:

- a value copied into a local variable and printed later (`label = user.email; ...; <%= label %>`);
- a person passed through a variable named after nothing niji knows (`<%= render "card", person: review.user %>` read as `person.name` in the partial, unless you add `person` to `extra_holders`);
- data that leaves through JavaScript, an API client or a log line.

Tests on the surfaces where leaks hide cover these: an avatar's alt text is empty, a review prints a name or "Anonymous", a mail to one person holds only that person's details.

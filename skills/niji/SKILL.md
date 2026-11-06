---
name: niji
description: Keep one person's name, email or other personal data off another person's screen in this Rails app. Use before calling any task done that touched views, mailers, helpers, controllers, services or the person model; when `bundle exec niji` (or `bin/rails niji:check`, or the niji Stop hook) reports EXPOSED or STALE lines; when writing or reviewing an entry in config/pii_exposure.yml; or when adding a column that identifies a person.
---

# niji: personal data stays with its owner

The rule this app follows: a screen, mail, alt text or share image shows another person only what the page already prints in plain text for that viewer.

niji checks the rule. It starts from the columns listed in `PERSONAL_ATTRIBUTES` on the person model (`User` by default, see `config/initializers/niji.rb`), adds their aliases and every method that returns them, and follows them into every view, mailer, helper, controller and service. Each read gets a verdict. A read that nobody has reviewed fails the run.

## Run it

```sh
bundle exec niji                 # what needs review; exit 1 when anything does
bundle exec niji --all           # every read, with its verdict
bundle exec niji --format json   # the same, for tools
bin/rails niji:check             # the same check as a Rake task (ALL=1 for every read)
```

Run it before you report a task as done whenever the change touched a view, mailer, helper, controller, service or the person model. It boots the app in the test environment and takes a few seconds.

## Read the output

```
EXPOSED  email app/views/reviews/_review.html.erb:2  avatar_tag review.user (via avatar_tag)
STALE    app/views/blogs/show.html.erb  @blog.author.name  (no longer a read that needs review, remove it from config/pii_exposure.yml)
-- 212 files scanned: 1 exposed, 38 allowed, 51 admin, 6 recipient, 22 own, 1 stale
```

Each line is a status, the kind of data (`name`, `email`, `phone` or the column name), the file and line, and the exact source of the read. `via avatar_tag` means a helper reads the data from its parameter, and this line is the call that hands it a person.

| Status | Meaning |
|---|---|
| `EXPOSED` | Nobody has reviewed this read. It fails the run. |
| `ALLOWED` | An entry in `config/pii_exposure.yml` explains why it is safe. |
| `ADMIN` | Only admins reach it: an admin path, an admin-only controller, or an `if admin?` branch. |
| `RECIPIENT` | A mail template greets the person the mail is sent to. |
| `OWN` | The viewer's own data (`Current.user` by default). |
| `STALE` | An allowlist entry that no longer matches any read. It fails the run. |

## Triage one EXPOSED line

Work through these questions in order, one finding at a time. Read the code each time, and never decide from the file name.

1. **Who can see this?** Find every way a person reaches the file. For a full template, that is its controller and the guard on it. For a partial, it is every `render` of it (search the views). For a mailer template, it is the mailer action and its `to:`. For a helper or service, it is every caller.
2. **Is it the viewer's own data through a path niji cannot follow?** Examples are `@user = Current.user` in the controller, a partial whose every render site passes `Current.user`, or a record loaded from the viewer's own session. If so, add an entry whose reason names the evidence ("SettingsController#show sets @user to Current.user").
3. **Is it public by design?** Some data is shown to everyone on purpose, like an author's name on a published post or a reviewer's display name on a public review. If the page already prints the same value in plain text for every viewer, add an entry and pin the kind with `kind: name`, so the entry stops matching if the read ever turns into an email.
4. **Is it admin-only in a way niji cannot see?** Prefer making that visible to niji over writing an entry. Wrap the read in `if admin?` (or the app's admin predicate), move the screen under the admin area, or describe the guard in `config/initializers/niji.rb` (`admin_markers`, `admin_paths`). Write an entry only when none of these fit, and name the guard in the reason.
5. **Otherwise it is a leak, so fix it.** The fixes that come up most often:
   - An avatar or profile picture whose `alt` carries a name or email. The name is printed beside it, so the picture is decoration: use `alt: ""`.
   - A fallback chain such as `name.presence || email`. Fall back to a neutral word ("Anonymous", "there") instead.
   - A mail to one person that names another person. Use a generic sentence and keep only what is already public, such as the listing's name.
   - A confirmation, notification or share image that repeats who did something, shown to someone else. Drop the person, or show the public display name only.

When you are unsure whether data is public in this app, stop and ask the user. A guess in either direction is worse than the question.

## Write an allowlist entry

```yaml
- file: app/views/reviews/_review.html.erb
  code: "review.user_name"
  kind: name
  reason: Review#user_name is the reviewer's public display name, or "Anonymous". Every review prints it.
```

- `file` and `code` must match the finding exactly. Copy them from the output.
- `kind` is optional. Add it for names, so a later change to an email needs a fresh review.
- `reason` is one honest sentence a reviewer can check in seconds. It names the evidence, such as the controller that sets the variable, the render sites, or the guard. Generic reasons like "safe", "needed" or "internal" are refused in review.
- Write one entry per finding, after reading that finding. Never generate entries in bulk from the output.
- When a finding's code changes, review the read again before you update its entry.
- Remove every `STALE` entry. It means the read moved or was deleted.

## Never silence the check

These all make the run green while the leak stays. Do not do them, and tell the user if a task seems to need one:

- renaming a variable so it no longer looks like a person (`maker` to `m`);
- moving the read into a model method or a local variable to hide it from the trace;
- removing a column from `PERSONAL_ATTRIBUTES`, or a model from `config.models`;
- widening `admin_paths` or `admin_markers` to cover pages non-admins see;
- adding an entry without a reason you have checked.

## Writing new code

- A new column that identifies a person (phone, address, date of birth, IP address) goes in `PERSONAL_ATTRIBUTES` in the same change.
- Before printing a person's data, ask who will see the page. If it is anyone other than that person or an admin, print only what the page already shows them.
- Test the surfaces where leaks hide. An avatar's alt text should be empty, a review should print a name or "Anonymous", and a mail to one person should hold only that person's details.

## Where niji stops

niji follows direct reads, helpers that relay a parameter, and model methods that hand a value on. A value copied into a local variable and printed later can slip past it, and a partial that several pages share usually needs an entry. Tests on the surfaces above cover the rest.

## Report back

When you finish, tell the user which leaks you fixed, which entries you added (with their reasons), and which findings you were unsure about.

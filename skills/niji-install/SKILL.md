---
name: niji-install
description: Install niji, the personal data (PII) guardrail, into a Rails app and take it from the first run to a green, reviewed check. Use when the user asks to add niji, to set up PII or personal data checks for Claude Code or Codex in a Rails app, or points you at the niji repository.
---

# Install niji in a Rails app

niji follows the columns that identify a person (name, email and so on) from the model to every view, mailer, helper, controller and service, and fails on a read nobody has reviewed. This skill takes an app from nothing to a green check that the team trusts. Plan on one working session, most of it spent reading findings.

Work in the app's repository, on a new branch. Keep the user informed at the two points marked **Ask**.

## 1. Check the app

- It is a Rails app (it has `config/application.rb`) on Rails 8.0 or later and Ruby 3.2 or later. Rails 8.1 gets the best defaults.
- Find the person model. It is usually `User`. Read it, and read `db/schema.rb` (or `db/structure.sql`) for its table.
- Find who the viewer is. Rails' authentication generator uses `Current.user`. Devise uses `current_user`. Search the views for both.
- Find how admins are kept apart. Look for an `admin?` method, a `before_action :require_admin` (or similar), an `Admin::` namespace under `app/controllers`, or an `ApplicationController` that requires an admin and lets controllers opt out.

## 2. Add the gem and run the generator

```sh
bundle add niji --group "development, test"
bin/rails generate niji:install
```

If the gem is not on RubyGems yet, add it from GitHub instead: `bundle add niji --group "development, test" --git https://github.com/ashgkwd/niji`.

The generator takes options. Use them when step 1 found something other than the defaults:

```sh
bin/rails generate niji:install --model Member --attributes full_name email phone --agents claude codex
```

It writes:

- `PERSONAL_ATTRIBUTES` on the model;
- `config/initializers/niji.rb`, where the configuration lives;
- an empty `config/pii_exposure.yml`, the reviewed exceptions;
- `test/niji_test.rb`, so the normal test run fails on a new leak;
- a step in `config/ci.rb` when the app has one;
- the `niji` skill in `.claude/skills/` (Claude Code) and `.agents/skills/` (Codex), a short section in `AGENTS.md`, and a Claude Code Stop hook in `.claude/settings.json`.

Running it again is safe. It leaves alone every file that already mentions niji.

## 3. Declare the personal columns

Open the model and review `PERSONAL_ATTRIBUTES`. List every column of that table that identifies a person or reaches them: name, email, phone, address, date of birth, IP address, external account IDs. Leave out columns that describe the account only (role, created_at, verified flags).

**Ask** the user to confirm the list before you go on. It is the one decision everything else depends on.

If another model also holds people (a `Customer` next to `User`), add it to `config.models` and give it its own constant.

## 4. Tell niji who is looking

Edit `config/initializers/niji.rb` using what you found in step 1. The options are explained in `docs/configuration.md` of the niji repository.

- Viewer: keep `"Current.user"`, and add `"current_user"` for Devise.
- Admin controllers: set `admin_markers` to the method the app runs before admin actions. A controller that runs it before every action, directly, through its superclass or through an included concern, is admin-only. `admin_paths` covers directories only admins reach (`app/views/admin/` is in by default).
- Admin by default: when `ApplicationController` requires an admin and controllers opt out with a class method, set `admin_by_default = true` and list those methods in `guard_lowering_methods`.
- Admin branches: `admin_predicates` lists the methods behind `if admin?` style checks.

## 5. First run and triage

```sh
bundle exec niji
```

The first run lists every read niji cannot prove safe. Expect a few dozen on a mid-sized app. Load the `niji` skill (the generator put it in `.claude/skills/niji/` and `.agents/skills/niji/`) and follow its triage section for each finding, one at a time. Fix the leaks, make admin guards visible to niji where you can, and write a one-sentence reason for each read that is safe.

**Ask** the user about every finding where you cannot tell from the code whether the data is meant to be public. Group those questions into one message.

Keep going until `bundle exec niji` exits 0.

## 6. Watch it fail once

A check you have seen fail is one you can rely on. Make a small temporary change that leaks, for example a display name method on the person model that falls back to the email (`name.presence || email_address`), or an avatar with `alt: user.email_address` in a public view. Run `bundle exec niji` and confirm it reports the read. Then revert the change and confirm the run is green again.

## 7. Finish

- Run the app's full test suite, including `test/niji_test.rb`.
- Commit on the branch with a message that says niji was added, how many leaks were fixed, and how many reads were reviewed.
- Tell the user what you fixed, the entries you added, the questions you asked and the answers, and how niji now runs (test suite, `config/ci.rb`, the Claude Code Stop hook).

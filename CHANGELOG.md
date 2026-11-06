# Changelog

All notable changes to niji are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## Unreleased

## 0.1.0

The first release, extracted from the check that runs on [AI Agents Live](https://aiagentslive.com).

- `bundle exec niji` and `bin/rails niji:check` trace `PERSONAL_ATTRIBUTES` from the model to every view, mailer, helper, controller and service, and fail on an unreviewed read or a stale allowlist entry.
- Readers are derived from columns, aliases and model methods to a fixed point. Holders are derived from associations. Methods on other models that hand a value along are sources too.
- ERB is compiled with ActionView's own Erubi before parsing, so `if admin?` branches are judged as admin-only.
- Helpers and services that read from a parameter are judged at each call site.
- Admin-only controllers are read from `before_action` markers, superclasses, concerns and the app's own guard-lowering methods, or from `admin_by_default`.
- Mail templates that greet the mail's own recipient are recognised.
- The allowlist needs a reason for every entry, can pin the kind of data, and fails on entries that no longer match.
- `--all`, `--format json` and `--hook claude` (a Claude Code Stop hook that blocks once per stop).
- `Niji::Assertions#assert_no_pii_exposure` for Minitest.
- `bin/rails generate niji:install` declares the personal columns from the schema, writes the initializer, the allowlist, a test and a CI step, and sets up Claude Code and Codex with the `niji` skill, an `AGENTS.md` section and a Stop hook.
- Skills: `niji` for daily work and `niji-install` for agents that install niji.

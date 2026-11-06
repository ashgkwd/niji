# AGENTS.md

niji is a Ruby gem that keeps one person's name, email and other personal data off another person's screen in a Rails app. It traces the model's personal columns to every view, mailer, helper, controller and service, and fails on a read nobody has reviewed.

You are here for one of two reasons. Read the matching section.

## You were asked to add niji to a Rails app

Follow [`skills/niji-install/SKILL.md`](skills/niji-install/SKILL.md) step by step, in the user's app (not in this repository). It installs the gem, runs the generator, confirms the personal columns with the user, configures who counts as an admin, works through the first run, and proves the check by breaking it once.

After the install, the app has its own copy of [`skills/niji/SKILL.md`](skills/niji/SKILL.md). That skill covers daily work: running the check, triaging findings, fixing leaks and writing allowlist entries.

Background, if you need it:

- [docs/how-it-works.md](docs/how-it-works.md) explains what niji derives and how it judges each read.
- [docs/configuration.md](docs/configuration.md) lists every option.
- [docs/agents.md](docs/agents.md) covers the Claude Code hook, Codex and JSON output.

## You are working on niji itself

### Layout

| Path | What it is |
|---|---|
| `lib/niji.rb` | Entry point: configuration, `Niji.check`, `analyze`, the verdict and the allowlist. |
| `lib/niji/sources.rb` | Readers, holders and derived readers, from the person model. |
| `lib/niji/method_bodies.rb` | Which model methods call which, to derive readers to a fixed point. |
| `lib/niji/scanner.rb` | The Prism visitor that records reads and calls in one file. |
| `lib/niji/admin_scopes.rb` | Which controllers are admin-only, from markers, superclasses, concerns and lowering methods. |
| `lib/niji/report.rb`, `lib/niji/cli.rb`, `exe/niji` | Output, exit codes, `--hook claude`. |
| `lib/niji/assertions.rb` | `assert_no_pii_exposure` for Minitest. |
| `lib/generators/niji/install/` | `bin/rails generate niji:install` and its templates. |
| `skills/` | The skills shipped to users' agents. The generator copies `skills/niji/`. |
| `test/dummy/` | A small Rails app with both original leaks kept as fixtures. |
| `articles/` | The stories behind niji. They are part of the product. |

### Commands

```sh
bundle install
bundle exec rake test      # the whole suite, about a second
bundle exec rubocop        # rubocop-rails-omakase
```

### Rules

- Every behaviour has a test. A new shape niji should catch starts as a failing test in `test/niji/analyze_test.rb` (strings in, verdicts out), or in `test/dummy` when it needs the real app.
- The two original leaks in `test/dummy` (the digest line in `maker_mailer/daily_reviews_digest.html.erb` and `AvatarsHelper#avatar_tag`) stay red. `test/niji/dummy_app_test.rb` pins them. Never fix them.
- When niji is unsure, it reports. An unsure admin guard leaves the controller open, and an unknown template stops the run. A false alarm costs a sentence in the allowlist. A missed leak costs someone's privacy.
- niji reads code and never writes it. The generator is the only part that writes files, and it leaves alone every file that already mentions niji, so running it twice changes nothing.
- Defaults fit a Rails 8.1 app made with `bin/rails generate authentication`. Anything app-specific is a `Niji::Configuration` option with a documented default, and a new option goes in `docs/configuration.md` and the initializer template in the same change.
- The gem supports Ruby 3.2 and later, so library code uses explicit block parameters rather than `it`.
- Prose (README, docs, skills, articles) uses plain sentences, without dashes as separators or filler words. Say what happens.
- Add a line to `CHANGELOG.md` under "Unreleased" for every change a user would notice.

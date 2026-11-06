# niji

**PII guardrails for Claude Code and Codex, for Rails apps.**

niji follows a person's name and email from your model to every view, mail, helper, controller and service in a Rails app. It gives each read a verdict about who is looking, and it fails the build on any read that nobody has reviewed.

```
$ bundle exec niji
EXPOSED  name  app/views/maker_mailer/daily_reviews_digest.html.erb:3  @spotlight_agent.maker.name
EXPOSED  email app/views/reviews/_review.html.erb:2  avatar_tag review.user (via avatar_tag)
-- 13 files scanned: 2 exposed, 1 allowed, 2 admin, 2 recipient, 4 own, 0 stale
```

Those two exposed lines are real. They are the two leaks that started this project, and niji's test app keeps both of them so they stay red forever.

## The email that named the wrong person

A daily digest email on [AI Agents Live](https://aiagentslive.com) told its reader that a maker was waiting for their review. The name in that sentence belonged to someone else, the owner of a listing the email recommended. One maker's name had been handed to another maker, and neither of them had asked for that.

The fix took a minute. The better question took longer. How many other places print one person's details on another person's screen, and could a machine find them every time instead of me remembering to look?

My first answer was a search for shapes like `maker.name` and `user.email_address`. It found the digest line and missed the real leak. A helper that draws profile pictures used the person's name and email as the alt text, on every public review page. The read happened on a plain parameter called `user`, two hops away from the page. A search that starts at the screen only sees the last hop.

So niji starts at the other end, at the model, and walks outward. The full story is in [The review email that named the wrong person](articles/origin-story.md).

## Why agents need this

Coding agents write code that works and passes its tests. A personal data leak fits inside that description, because it usually arrives as a small act of helpfulness. A display name falls back to the email so the label is never blank. An avatar gets a full description for screen readers. A confirmation repeats who submitted the form, and the confirmation goes to someone else.

niji gives the agent a rule it can check (a screen shows another person only what the page already prints for that viewer) and a command that answers yes or no. A Claude Code hook runs that command when the agent tries to finish, so a leak cannot be the last thing an agent leaves behind. More in [How to stop Claude from leaking personal data into your app](articles/how-to-stop-claude-from-leaking-pii.md).

## Hand it to your coding agent

Open Claude Code or Codex in your Rails app and paste this:

```
Add niji to this app by following
https://github.com/ashgkwd/niji/blob/main/skills/niji-install/SKILL.md
```

The agent installs the gem, runs the generator, asks you to confirm which columns identify a person, works through the first run with you, and breaks the check once on purpose to prove it works. You can also install both skills into your agent with `npx skills add ashgkwd/niji`.

## Install it yourself

```sh
bundle add niji --group "development, test"
bin/rails generate niji:install
bundle exec niji
```

The generator reads your `users` table and writes:

- `PERSONAL_ATTRIBUTES` on the model, the one list everything else is derived from;
- `config/initializers/niji.rb` for the few choices niji cannot read from your code;
- an empty `config/pii_exposure.yml` for reviewed exceptions;
- `test/niji_test.rb`, so the normal test run fails on a new leak;
- a step in `config/ci.rb`;
- the `niji` skill for Claude Code (`.claude/skills/`) and Codex (`.agents/skills/`), a short section in `AGENTS.md`, and a Claude Code Stop hook.

The first run lists every read niji cannot prove safe. On a mid-sized app that took me a few hours to read through, and about forty reads got a one-sentence reason. After that, each new finding is one small, specific question.

## How it works

niji is four guardrails that work together. [docs/how-it-works.md](docs/how-it-works.md) has the details, and [Four guardrails for personal data in agent-written code](articles/guardrails-to-detect-pii-in-agent-generated-code.md) has the design story.

1. **A declared source.** You list the columns that identify a person once, on the model. niji adds their aliases, every model method that returns them (such as `name_with_email`), and methods on other models that hand them along (such as `Review#user_name`).
2. **A trace to every screen.** niji learns from your associations which names a person travels under (`maker`, `author`, `invited_by`). It parses every view the way Rails compiles it, so an `if admin?` stays visible, and it judges a helper that reads from its parameter at every place that calls it.
3. **A verdict about the viewer.** Each read is the viewer's own, admin-only, addressed to a mail's recipient, reviewed with a written reason, or exposed.
4. **Watching it fail.** The original leaks stay in the test suite, the check runs as a test in your app, and the install ends by breaking it on purpose.

## Verdicts

| Status | The read is fine because |
|---|---|
| `OWN` | It shows viewers their own data (`Current.user`). |
| `ADMIN` | Only admins reach it: an admin-only controller, an admin path, or an `if admin?` branch. |
| `RECIPIENT` | A mail template greets the person the mail is sent to. |
| `ALLOWED` | A person wrote down why it is safe in `config/pii_exposure.yml`. |
| `EXPOSED` | Nobody has said why it is safe yet. The run fails. |
| `STALE` | An allowlist entry no longer matches any read. The run fails. |

niji works out which controllers are admin-only from the controllers themselves. A controller that runs `before_action :require_admin` (directly, through its superclass or through a concern) serves admins only, and a method your app defines to skip that guard opens the controller again wherever it is called.

## The allowlist keeps itself honest

```yaml
- file: app/views/reviews/_review.html.erb
  code: "review.user_name"
  kind: name
  reason: Review#user_name is the reviewer's public display name, or "Anonymous". Every review prints it.
```

Every entry needs a reason a reviewer can check in seconds. An entry whose read disappears fails the run until someone removes it, so the list shrinks along with the code. An entry pinned with `kind: name` stops matching when the read turns into an email, which catches the most common regression, a name that gains an email fallback.

## Configuration

The defaults fit a Rails 8.1 app made with `bin/rails generate authentication`: a `User` model, `Current.user` as the viewer, and an admin area under `app/controllers/admin`. Devise apps add `current_user`. Apps where every controller requires an admin unless it opts out set `admin_by_default`. [docs/configuration.md](docs/configuration.md) lists every option.

```ruby
Niji.configure do |config|
  config.models = %w[ User ]
  config.viewer_expressions = [ "Current.user", "current_user" ]
  config.admin_markers = %i[ require_admin ]
  config.admin_paths += %w[ app/views/dashboard/ ]
end
```

## Running it

```sh
bundle exec niji                    # exit 1 when a read needs review
bundle exec niji --all              # every read, with its verdict
bundle exec niji --format json      # for tools
bundle exec niji --hook claude      # the Claude Code Stop hook protocol
bin/rails niji:check                # the same check as a Rake task
```

In tests, `include Niji::Assertions` and call `assert_no_pii_exposure`. [docs/agents.md](docs/agents.md) covers the Claude Code hook, Codex and other agents.

## Where niji stops

niji follows direct reads, helpers that relay a parameter, and model methods that hand a value along. A value copied into a local variable and printed three steps later can slip past it, and a partial shared by several pages usually needs an entry. Those are the cost of a deterministic check. A few tests on the surfaces where leaks hide (avatar alt text, review names, mail bodies) cover the rest, and the `niji` skill tells agents to write them.

niji reads ERB, Jbuilder and Builder templates. The first version is for Rails, because Rails exposes association metadata and a template compiler a script can call. The same four steps carry over to any framework that offers both.

## Stories

- [The review email that named the wrong person](articles/origin-story.md)
- [How to stop Claude from leaking personal data into your app](articles/how-to-stop-claude-from-leaking-pii.md)
- [Four guardrails for personal data in agent-written code](articles/guardrails-to-detect-pii-in-agent-generated-code.md)

## Contributing

A leak niji missed is the most useful thing you can send. Open an issue with the smallest code that leaks, and it becomes a test. False alarms are welcome too. [CONTRIBUTING.md](CONTRIBUTING.md) explains how to work on niji, and [AGENTS.md](AGENTS.md) is the same guide for your coding agent.

## License

MIT. See [LICENSE.txt](LICENSE.txt).

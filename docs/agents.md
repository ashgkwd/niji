# niji and coding agents

An instruction in prose gets forgotten halfway through a long task. A command gets run, and a hook runs whether the agent remembers or not. niji gives agents all three: a one-sentence rule, a command that answers yes or no, and a hook.

## The rule

The generator adds this section to `AGENTS.md`, which Codex and most other agents read at the start of every session (Claude Code reads it through `CLAUDE.md`):

> A screen, mail, alt text or share image shows another person only what the page already prints in plain text for that viewer.

It points at `PERSONAL_ATTRIBUTES` so the agent knows what the sentence covers, and at the command that checks it.

## The skills

niji ships two skills in [`skills/`](../skills), in the shared `SKILL.md` format that Claude Code and Codex both read.

| Skill | Where it lives | Use |
|---|---|---|
| `niji` | copied into your app by the generator | Run the check, triage each finding, fix leaks, write allowlist entries, avoid silencing the check. |
| `niji-install` | read from this repository | Take an app from nothing to a green, reviewed check. |

The generator copies `niji` into `.claude/skills/niji/` for Claude Code and `.agents/skills/niji/` for Codex. Pick agents with `--agents claude codex` (the default) or one of them.

To install both skills into your agent's own skill folder, use the skills CLI:

```sh
npx skills add ashgkwd/niji
```

## Claude Code: the Stop hook

The generator adds this to `.claude/settings.json`, next to anything already there:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "cd \"$CLAUDE_PROJECT_DIR\" && bundle exec niji --hook claude", "timeout": 120 }
        ]
      }
    ]
  }
}
```

When Claude tries to finish, the hook runs the check. A clean run exits 0 and Claude stops. A failing run prints the report on stderr and exits 2, which Claude Code shows to the agent and which keeps it working ([hooks reference](https://code.claude.com/docs/en/hooks)). The hook blocks once per stop: when Claude is already continuing because of a Stop hook (`stop_hook_active`), niji lets it stop, so a leak the agent cannot fix never turns into a loop. The report is still printed, and the test suite and CI catch it from there.

The hook boots the app, which takes a few seconds on each stop. Leave it out with `--no-hook` if that is too slow for you, and rely on the test and CI step.

## Codex

Codex reads `AGENTS.md` and the skills in `.agents/skills/`. The generator writes both. Ask Codex to run `bundle exec niji` before it reports a task as done, or add it to the checks your Codex setup already runs.

## Other agents

Any agent that reads `AGENTS.md` gets the rule and the command. `bundle exec niji --format json` prints a machine-readable report:

```json
{
  "success": false,
  "scanned": 13,
  "findings": [
    { "file": "app/views/reviews/_review.html.erb", "line": 2, "code": "avatar_tag review.user", "kind": "email", "status": "exposed", "via": "avatar_tag" }
  ],
  "stale": []
}
```

## Tests and CI

The generator adds `test/niji_test.rb`:

```ruby
class NijiTest < ActiveSupport::TestCase
  include Niji::Assertions

  test "no person's name or email reaches another person's screen unreviewed" do
    assert_no_pii_exposure
  end
end
```

and a step to `config/ci.rb` (Rails 8.1's `bin/ci`):

```ruby
step "Security: Personal data exposure", "bundle exec niji"
```

For RSpec, the same check is one line:

```ruby
it("leaks no personal data") { expect(Niji.check).to be_success }
```

A leak reaches production through whichever path skips the check, so run it in every place your team checks code before a release.

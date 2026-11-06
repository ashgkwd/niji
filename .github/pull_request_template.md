## What this changes

<!-- The leak niji now catches, the false alarm it no longer raises, or the feature. -->

## The test that shows it

<!-- The test name. A new shape starts as a failing test in test/niji/analyze_test.rb. -->

## Checklist

- [ ] `bundle exec rake test` passes, and the two original leaks in `test/dummy` still fail the check.
- [ ] `bundle exec rubocop` passes.
- [ ] A new option is in `docs/configuration.md` and the initializer template.
- [ ] `CHANGELOG.md` has a line under "Unreleased" if users will notice the change.

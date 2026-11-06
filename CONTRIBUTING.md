# Contributing to niji

Thank you for helping. niji gets better one real leak at a time, so the most useful contribution is a leak it missed.

## Report a leak niji missed

Open an issue with the "A leak niji missed" template. Include the smallest code that leaks: the model lines that declare the data, the view, helper or mailer that prints it, and who sees that page. Remove anything private first. A real email address or name in an issue is the very thing niji exists to prevent.

If you can, write it as a failing test in `test/niji/analyze_test.rb`. Most shapes fit in a few lines there:

```ruby
test "reports a person passed to a partial as a local" do
  result = analyze("app/views/reviews/_card.html.erb" => "<%= person.email %>")

  assert_equal :exposed, status_of(result, "person.email")
end
```

## Report a false alarm

Open an issue with the "A false alarm" template. Show the read, explain who can see it, and say why it is safe. Some false alarms are better solved with an allowlist entry than a change to niji. The issue is a good place to decide which.

## Work on the code

```sh
git clone https://github.com/ashgkwd/niji.git
cd niji
bundle install
bundle exec rake test
bundle exec rubocop
```

[AGENTS.md](AGENTS.md) describes the layout and the rules the code follows. It is written for coding agents, and it works for people too. The short version:

- Every behaviour has a test, and the two original leaks in `test/dummy` stay red.
- When niji is unsure, it reports.
- App-specific choices are configuration options with documented defaults.
- Add a line to `CHANGELOG.md` for every change a user would notice.

Open a pull request against `main`. Describe the leak or the false alarm it addresses, and the test that shows it.

## Code of conduct

Everyone taking part in niji follows the [Code of Conduct](CODE_OF_CONDUCT.md).

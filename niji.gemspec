# frozen_string_literal: true

require_relative "lib/niji/version"

Gem::Specification.new do |spec|
  spec.name = "niji"
  spec.version = Niji::VERSION
  spec.authors = [ "Ash Gaikwad" ]
  spec.email = [ "ash.gkwd@gmail.com" ]

  spec.summary = "PII guardrails for Rails apps built with Claude Code and Codex."
  spec.description = "niji follows a person's name and email from your Rails model to every view, mailer, helper, " \
    "controller and service, judges each read by who is looking, and fails the build on a read nobody has reviewed. " \
    "It ships skills and hooks so coding agents run it before they call a task done."
  spec.homepage = "https://github.com/ashgkwd/niji"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "documentation_uri" => "#{spec.homepage}/tree/main/docs",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "skills/**/*", "docs/**/*", "articles/**/*", "exe/*", "README.md", "LICENSE.txt", "CHANGELOG.md", "AGENTS.md"]
  spec.bindir = "exe"
  spec.executables = [ "niji" ]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "prism", ">= 1.0"
  spec.add_dependency "railties", ">= 8.0"
  spec.add_dependency "activerecord", ">= 8.0"
  spec.add_dependency "actionview", ">= 8.0"
end

# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "generators/niji/install/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests Niji::Generators::InstallGenerator
  destination File.expand_path("../../tmp/generator", __dir__)

  RAILS_CI = <<~RUBY
    CI.run do
      step "Setup", "bin/setup --skip-server"
      step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
      step "Tests: Rails", "bin/rails test"
    end
  RUBY

  SCHEMA = <<~RUBY
    ActiveRecord::Schema[8.1].define(version: 2026_10_20_000000) do
      create_table "users_archive", force: :cascade do |t|
        t.string "nickname"
      end

      create_table "users", force: :cascade do |t|
        t.string "name"
        t.string "email_address", null: false
        t.string "password_digest", null: false
        t.string "phone_number"
        t.string "last_sign_in_ip"
        t.string "company_name"
        t.integer "team_id"
        t.datetime "created_at", null: false
        t.index [ "email_address" ], name: "index_users_on_email_address", unique: true
      end
    end
  RUBY

  setup do
    prepare_destination
    write "app/models/user.rb", "class User < ApplicationRecord\n  has_many :sessions\nend\n"
    write "db/schema.rb", SCHEMA
    write "config/ci.rb", RAILS_CI
    write "test/test_helper.rb", ""
    write "CLAUDE.md", "# Project\n"
    write ".claude/settings.json", %({"permissions":{"allow":["Bash(bin/rails test)"]}}\n)
  end

  test "sets up the model, config, test, CI and both agents" do
    run_generator

    assert_file "app/models/user.rb", /PERSONAL_ATTRIBUTES = %w\[ name email_address phone_number last_sign_in_ip \]\.freeze/
    assert_file "config/initializers/niji.rb", /config\.models = %w\[ User \]/
    assert_file "config/pii_exposure.yml" do |content|
      assert_equal [], YAML.safe_load(content)
    end
    assert_file "test/niji_test.rb", /assert_no_pii_exposure/
    assert_file "config/ci.rb", /Brakeman[^\n]*\n  step "Security: Personal data exposure", "bundle exec niji"\n  step "Tests: Rails"/
    assert_file ".claude/skills/niji/SKILL.md", /^name: niji$/
    assert_file ".agents/skills/niji/SKILL.md", /^name: niji$/
    assert_no_file ".claude/skills/niji-install/SKILL.md"
    assert_file "AGENTS.md", /## Personal data/
    assert_file "CLAUDE.md", /## Personal data/
    assert_file ".claude/settings.json" do |content|
      settings = JSON.parse(content)
      assert_equal [ "Bash(bin/rails test)" ], settings.dig("permissions", "allow")
      assert_match "niji --hook claude", settings.dig("hooks", "Stop", 0, "hooks", 0, "command")
    end
  end

  test "running it twice changes nothing the second time" do
    run_generator
    first = %w[ app/models/user.rb config/ci.rb AGENTS.md CLAUDE.md .claude/settings.json ].to_h { |path| [ path, File.read(File.join(destination_root, path)) ] }

    run_generator

    first.each { |path, content| assert_equal content, File.read(File.join(destination_root, path)), path }
  end

  test "before the first migration has run, the columns come from the migrations" do
    FileUtils.rm(File.join(destination_root, "db/schema.rb"))
    write "db/migrate/20261020000000_create_users.rb", <<~RUBY
      class CreateUsers < ActiveRecord::Migration[8.1]
        def change
          create_table :users do |t|
            t.string :email_address, null: false
            t.string :password_digest, null: false

            t.timestamps
          end
          add_index :users, :email_address, unique: true
        end
      end
    RUBY

    run_generator

    assert_file "app/models/user.rb", /PERSONAL_ATTRIBUTES = %w\[ email_address \]\.freeze/
  end

  test "takes another model, other columns and one agent" do
    write "app/models/member.rb", "class Member < ApplicationRecord\nend\n"
    write "CLAUDE.md", "@AGENTS.md\n"

    run_generator %w[ --model Member --attributes full_name email phone --agents claude --no-hook --no-ci ]

    assert_file "app/models/member.rb", /PERSONAL_ATTRIBUTES = %w\[ full_name email phone \]\.freeze/
    assert_file "config/initializers/niji.rb", /%w\[ Member \]/
    assert_file ".claude/skills/niji/SKILL.md"
    assert_no_file ".agents/skills/niji/SKILL.md"
    assert_file "CLAUDE.md", "@AGENTS.md\n"
    assert_file ".claude/settings.json" do |content|
      assert_nil JSON.parse(content)["hooks"]
    end
    assert_file "config/ci.rb", RAILS_CI
  end

  private

  def write(path, content)
    file = File.join(destination_root, path)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, content)
  end
end

# frozen_string_literal: true

require "json"
require "rails/generators"

module Niji
  module Generators
    # bin/rails generate niji:install
    #
    # Declares the personal columns on the model, writes the initializer and an
    # empty allowlist, adds a test and a CI step, and gives Claude Code and
    # Codex the niji skill, a line in AGENTS.md and (Claude Code) a Stop hook.
    # Every step leaves an existing file alone when niji is already in it, so
    # running the generator again is safe.
    class InstallGenerator < Rails::Generators::Base
      SKILLS = File.expand_path("../../../../skills", __dir__)
      # Column names that usually identify or reach a person. The generator
      # proposes the ones the table has; the user confirms the list.
      PERSONAL_COLUMN = /\A(?:.*name|.*email.*|.*phone.*|mobile.*|.*address|date_of_birth|birth_?date|birthday|dob|ssn|.*passport.*|.*tax_id|post_?code|zip(?:_?code)?|.*_handle|username|avatar_url|.*_ip|ip)\z/
      NOT_PERSONAL = /\A(?:.*_id|.*_digest|.*_token|.*_count|type|company_name|.*_at)\z/
      AGENT_SKILL_DIRS = { "claude" => ".claude/skills", "codex" => ".agents/skills" }.freeze
      HOOK_COMMAND = %(cd "$CLAUDE_PROJECT_DIR" && bundle exec niji --hook claude)

      source_root File.expand_path("templates", __dir__)

      class_option :model, type: :string, default: "User", desc: "The model that holds a person"
      class_option :attributes, type: :array, desc: "Its columns that identify a person (default: read from db/schema.rb or the migrations)"
      class_option :agents, type: :array, default: %w[ claude codex ], desc: "Coding agents to set up (claude, codex)"
      class_option :hook, type: :boolean, default: true, desc: "Add a Claude Code Stop hook that runs the check"
      class_option :ci, type: :boolean, default: true, desc: "Add a step to config/ci.rb"
      class_option :test, type: :boolean, default: true, desc: "Add test/niji_test.rb"

      def create_initializer
        template "niji.rb.tt", "config/initializers/niji.rb"
      end

      def create_allowlist
        return say_status(:exist, "config/pii_exposure.yml", :blue) if exist?("config/pii_exposure.yml")

        template "pii_exposure.yml.tt", "config/pii_exposure.yml"
      end

      def declare_personal_attributes
        path = "app/models/#{model.underscore}.rb"
        return say_status(:skip, "#{path} not found: declare #{model}::PERSONAL_ATTRIBUTES yourself", :yellow) unless exist?(path)
        return say_status(:identical, "#{path} already declares PERSONAL_ATTRIBUTES", :blue) if read(path).include?("PERSONAL_ATTRIBUTES")

        inject_into_class path, model.demodulize, <<~RUBY.indent(2)
          # What identifies a person. niji (bin/rails niji:check) starts from these,
          # adds every alias and every method that returns one of them, and follows
          # them to the views, mailers, helpers, controllers and services that print
          # them. Add a column here when it should never reach another person's
          # screen unreviewed.
          PERSONAL_ATTRIBUTES = %w[ #{personal_attributes.join(" ")} ].freeze

        RUBY
      end

      def create_test
        return unless options[:test] && exist?("test")

        template "niji_test.rb.tt", "test/niji_test.rb"
      end

      def add_ci_step
        return unless options[:ci] && exist?("config/ci.rb")
        return if read("config/ci.rb").include?("niji")

        step = %(  step "Security: Personal data exposure", "bundle exec niji"\n)
        if read("config/ci.rb").match?(/^\s*step "Security: Brakeman[^\n]*\n/)
          inject_into_file "config/ci.rb", step, after: /^\s*step "Security: Brakeman[^\n]*\n/
        else
          inject_into_file "config/ci.rb", step, before: /^end\b/
        end
      end

      def add_agent_skills
        agents.each do |agent|
          Dir.glob("*/SKILL.md", base: SKILLS).each do |skill|
            next if File.dirname(skill) == "niji-install"

            copy_file File.join(SKILLS, skill), File.join(AGENT_SKILL_DIRS.fetch(agent), skill)
          end
        end
      end

      def add_agent_instructions
        return if agents.empty?

        section = File.read(File.join(self.class.source_root, "agents_section.md"))
        if !exist?("AGENTS.md")
          create_file "AGENTS.md", section
        elsif !read("AGENTS.md").include?("niji")
          append_to_file "AGENTS.md", "\n#{section}"
        end

        # Claude Code reads CLAUDE.md. It already sees the section when
        # CLAUDE.md imports AGENTS.md.
        if agents.include?("claude") && exist?("CLAUDE.md") && !read("CLAUDE.md").match?(/@AGENTS\.md|niji/)
          append_to_file "CLAUDE.md", "\n#{section}"
        end
      end

      def add_claude_hook
        return unless options[:hook] && agents.include?("claude")

        path = ".claude/settings.json"
        settings = exist?(path) ? JSON.parse(read(path)) : {}
        stop = ((settings["hooks"] ||= {})["Stop"] ||= [])
        return say_status(:identical, "#{path} already runs niji", :blue) if stop.to_json.include?("niji")

        stop << { "hooks" => [ { "type" => "command", "command" => HOOK_COMMAND, "timeout" => 120 } ] }
        create_file path, "#{JSON.pretty_generate(settings)}\n", force: true
      end

      def show_next_steps
        say <<~TEXT

          niji is installed. Next:
            1. Check #{model}::PERSONAL_ATTRIBUTES lists every column that identifies a person.
            2. Tell niji who your admins are in config/initializers/niji.rb.
            3. Run `bin/rails niji:check` and read every finding. Fix the leaks and give
               each safe read a one-sentence reason in config/pii_exposure.yml.
          A coding agent can do steps 2 and 3 with the niji skill: ask it to "run niji".
        TEXT
      end

      private

      def model = options[:model].camelize

      def personal_attributes
        @personal_attributes ||= options[:attributes].presence || detected_columns.presence || %w[ email_address ]
      end

      # The model's columns that look personal, from db/schema.rb or, before the
      # first migration has run, from the migrations that build its table.
      def detected_columns
        table = model.tableize.tr("/", "_")
        texts = exist?("db/schema.rb") ? [ read("db/schema.rb") ] : Dir.glob(File.join(destination_root, "db/migrate/*.rb")).sort.map { |file| File.read(file) }
        columns = texts.flat_map do |text|
          body = text[/create_table[( ]+[:"]#{Regexp.escape(table)}\b"?[^\n]*\n(.*?)^\s*end\b/m, 1].to_s
          body.scan(/^\s*t\.\w+\s+[:"](\w+)/).flatten
        end
        columns.uniq.select { |column| column.match?(PERSONAL_COLUMN) && !column.match?(NOT_PERSONAL) }
      end

      def agents = options[:agents].map(&:downcase) & AGENT_SKILL_DIRS.keys

      def exist?(path) = File.exist?(File.join(destination_root, path))

      def read(path) = File.read(File.join(destination_root, path))
    end
  end
end

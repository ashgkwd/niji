# frozen_string_literal: true

# niji finds the places where one person's name or email can reach another
# person's screen. It starts at the source, the model, and follows the data out
# to the views, mailers, helpers, controllers and services:
#
#   1. Sources. Each model lists the columns that identify a person
#      (User::PERSONAL_ATTRIBUTES). The readers are those columns, their
#      aliases, and every method of the model and its concerns that calls a
#      reader (name_with_email), to a fixed point. Methods on other models that
#      hand a reader's value on (Review#user_name) are sources too.
#   2. Holders. A receiver can hold a person when it is named after an
#      association whose class is the model (maker, user, author, invited_by),
#      after the model itself, or is the block variable of a scope chain on the
#      model (User.verified.map { |user| user.name }). The names come from the
#      real reflections.
#   3. Reads. Every call of a reader on a holder, in the compiled ERB of the
#      views (ActionView's own Erubi, so `if admin?` stays visible) and in Ruby
#      files, parsed with Prism.
#   4. Relays. A helper that reads a reader off its own parameter
#      (avatar_tag(user)) is judged at its call sites, with the argument given.
#   5. Verdict. A read is fine when it is the viewer's own, sits in an
#      admin-only place, greets the person a mail is sent to, or is listed with
#      a reason in config/pii_exposure.yml. Anything else fails. An allowlist
#      entry that no longer matches a read fails too, so the list cannot rot.
#
# Models are not scanned: they are the data layer, and what they pass on is
# read again where it is printed.

require "pathname"
require "prism"
require "yaml"

require_relative "niji/version"
require_relative "niji/configuration"
require_relative "niji/sources"
require_relative "niji/method_bodies"
require_relative "niji/scanner"
require_relative "niji/admin_scopes"
require_relative "niji/report"
require_relative "niji/railtie" if defined?(Rails::Railtie)

module Niji
  Read = Struct.new(:file, :line, :code, :receiver, :kind, :own, :admin, :recipient, :def_name, :takes_args, :param, keyword_init: true)
  Call = Struct.new(:file, :line, :name, :code, :own, :admin, :recipient, keyword_init: true)
  Finding = Struct.new(:file, :line, :code, :kind, :status, :via, :reason, keyword_init: true)
  Result = Struct.new(:findings, :stale, :scanned, keyword_init: true) do
    def violations = findings.select { |finding| finding.status == :exposed }
    def success? = violations.empty? && stale.empty?
  end

  # Every status a finding can have, from "needs a human" to "the viewer's own".
  STATUSES = %i[ exposed allowed admin recipient own ].freeze

  class Error < StandardError; end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_config!
      @config = Configuration.new
    end

    # Runs the whole check on the app: every scanned file, the sources derived
    # from the models, and the reviewed allowlist.
    def check(config: self.config)
      analyze(app_files(config:), sources: sources(config:), allowlist: load_allowlist(config:), config:)
    end

    # One Sources per person model, derived from the loaded app.
    def sources(config: self.config)
      Rails.application.eager_load!
      config.models.map { |name| Sources.new(name.to_s.constantize, config:) }
    end

    # path => text for everything the check reads.
    def app_files(config: self.config)
      root = config.root
      Dir.glob(root.join(config.scanned)).sort.filter_map do |path|
        relative = Pathname(path).relative_path_from(root).to_s
        [ relative, File.read(path) ] unless path_match?(config.skipped_paths, relative)
      end.to_h
    end

    def load_allowlist(config: self.config)
      file = config.root.join(config.allowlist_path)
      entries = file.exist? ? YAML.safe_load_file(file) || [] : []
      raise Error, "#{config.allowlist_path}: expected a list of entries" unless entries.is_a?(Array)

      entries.each do |entry|
        complete = entry.is_a?(Hash) && %w[ file code reason ].all? { |key| entry[key].to_s.strip != "" }
        raise Error, "#{config.allowlist_path}: #{entry.inspect} needs file, code and reason" unless complete
      end
    end

    # Rails compiles a template into a method, so a bare `yield` is legal there.
    # Same first line, so the line numbers of the template survive.
    def ruby_source(path, text)
      return text unless path.end_with?(".erb")

      require "action_view"
      "def __template; #{ActionView::Template::Handlers::ERB::Erubi.new(text).src}\nend"
    end

    def analyze(files, sources:, allowlist: [], config: self.config)
      closed = AdminScopes.from(files, config:)
      scans = files.map do |path, text|
        parsed = Prism.parse(ruby_source(path, text))
        raise Error, "#{path}: #{parsed.errors.map(&:message).first}" if parsed.errors.any?

        # A partial can be rendered by another controller's page, so only a
        # full template in an admin-only controller's directory is admin-only.
        admin_file = closed.key?(path) || (closed.value?(File.dirname(path)) && !File.basename(path).start_with?("_"))
        Scanner.new(path, sources, config:, admin_file:).tap { |scan| parsed.value.accept(scan) }
      end
      reads = scans.flat_map(&:reads)
      mark_mail_recipients(reads, scans)
      calls = scans.flat_map(&:calls).group_by(&:name)

      relay = ->(read) { read.param && read.def_name && path_match?(config.relay_paths, read.file) }
      relays = reads.select { |read| relay.call(read) && !read.admin }.map(&:def_name).uniq.select { |name| calls.key?(name) }
      relayed = ->(read) { relay.call(read) && relays.include?(read.def_name) }

      findings = reads.reject(&relayed).map { |read| judge(read, read.kind) }
      relay_kinds = reads.select(&relayed).group_by(&:def_name).transform_values { |group| strongest(group.map(&:kind)) }
      findings += relays.flat_map { |name| calls[name].map { |call| judge(call, relay_kinds[name], via: name) } }

      apply_allowlist(findings, allowlist, scanned: files.size)
    end

    # A mailer's template greets the person its action mails to.
    def mark_mail_recipients(reads, scans)
      templates = scans.select { |scan| scan.file.start_with?("app/mailers/") }.flat_map do |scan|
        mailer = scan.file.delete_prefix("app/mailers/").delete_suffix(".rb")
        scan.mail_recipients.map { |action, ivars| [ "app/views/#{mailer}/#{action}", ivars ] }
      end.to_h
      reads.each do |read|
        key = File.join(File.dirname(read.file), File.basename(read.file).split(".").first)
        read.recipient ||= templates.fetch(key, []).include?(read.receiver)
      end
    end

    def judge(site, kind, via: nil)
      status = if site.own then :own elsif site.recipient then :recipient elsif site.admin then :admin else :exposed end
      Finding.new(file: site.file, line: site.line, code: site.code, kind:, status:, via:)
    end

    def apply_allowlist(findings, allowlist, scanned:)
      used = []
      findings.each do |finding|
        next unless finding.status == :exposed

        # An entry may pin the kind (`kind: name`): a read that has since
        # turned into an email is no longer the thing that was reviewed.
        entry = allowlist.find do |candidate|
          candidate["file"] == finding.file && candidate["code"] == finding.code && (candidate["kind"].nil? || candidate["kind"].to_s == finding.kind.to_s)
        end
        next unless entry

        used << entry
        finding.status = :allowed
        finding.reason = entry["reason"]
      end
      Result.new(findings: findings.sort_by { |finding| [ finding.file, finding.line ] }, stale: allowlist - used, scanned:)
    end

    # Matches a path relative to the app root against prefixes ending in "/",
    # exact paths, globs and regexps.
    def path_match?(patterns, path)
      Array(patterns).any? do |pattern|
        case pattern
        when Regexp then pattern.match?(path)
        when /[*?\[{]/ then File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
        when %r{/\z} then path.start_with?(pattern)
        else path == pattern.to_s || path.start_with?("#{pattern}/")
        end
      end
    end

    # The label of a personal column: email, phone, name, or the column itself.
    def kind_of(attribute, config: self.config)
      attribute = attribute.to_s
      label = config.kinds[attribute] || config.kinds[attribute.to_sym]
      return label.to_sym if label

      case attribute
      when /email/ then :email
      when /phone|mobile/ then :phone
      when /name/ then :name
      else attribute.to_sym
      end
    end

    # A read that reaches several columns is reported as the most revealing
    # one: anything beats a name, so `name_with_email` is an email.
    def strongest(kinds)
      kinds = kinds.compact.uniq
      (kinds - [ :name ]).first || kinds.first
    end
  end
end

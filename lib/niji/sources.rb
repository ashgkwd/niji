# frozen_string_literal: true

module Niji
  # The readers of one person model and the names a person travels under,
  # derived from the model and its associations.
  class Sources
    # readers: method name => kind, for the model's columns, their aliases and
    # every model method that returns one of them.
    # holders: receiver names that can hold a person.
    # derived: other models' methods that hand a reader's value on
    # (Review#user_name is user&.name.presence), name => kind. Called on any
    # receiver: a model method has no association to type it by.
    attr_reader :klass, :readers, :holders, :derived

    def initialize(klass, config: Niji.config)
      @klass = klass
      @config = config
      @readers = derive_readers
      @holders = derive_holders
      @derived = {}
      @derived = derive_derived
    end

    def attributes
      @attributes ||= begin
        constant = @config.attributes_constant
        declared = klass.const_get(constant, false) if constant && klass.const_defined?(constant, false)
        declared ||= @config.personal_attributes[klass.name] || @config.personal_attributes[klass.name.to_sym]
        raise Error, "#{klass.name} declares no personal attributes. Add `#{constant} = %w[ name email_address ].freeze` to the model, or set config.personal_attributes[\"#{klass.name}\"] in config/initializers/niji.rb." if declared.nil? || declared.empty?

        declared.map(&:to_sym)
      end
    end

    private

    def models_dir = @config.root.join("app/models")

    def derive_readers
      readers = attributes.to_h { |attribute| [ attribute, Niji.kind_of(attribute, config: @config) ] }
      klass.attribute_aliases.each do |alias_name, target|
        readers[alias_name.to_sym] = readers[target.to_sym] if readers.key?(target.to_sym)
      end

      defs = model_files.flat_map { |file| MethodBodies.new(file).defs }
      loop do
        found = defs.filter_map do |name, called|
          next if readers.key?(name)

          kinds = called.filter_map { |called_name| readers[called_name] }
          [ name, Niji.strongest(kinds) ] if kinds.any?
        end
        break if found.empty?

        readers.merge!(found.to_h)
      end
      readers
    end

    # The class and its concerns, from where Ruby says they are defined.
    def model_files
      klass.ancestors.filter_map do |mod|
        file = mod.name && Object.const_source_location(mod.name)&.first
        file if file&.start_with?(models_dir.to_s)
      end.uniq
    end

    def derive_holders
      from_associations = ActiveRecord::Base.descendants.reject(&:abstract_class?).flat_map do |model|
        model.reflect_on_all_associations.reject { |reflection| reflection.polymorphic? || reflection.collection? }.select { |reflection| reflects?(reflection) }.map { |reflection| reflection.name.to_s }
      end
      (from_associations + [ klass.model_name.element ] + @config.extra_holders.map(&:to_s)).uniq
    end

    def reflects?(reflection)
      reflection.klass <= klass
    rescue NameError, ArgumentError
      false
    end

    def derive_derived
      own_files = model_files
      record_files = Dir.glob(models_dir.join("**/*.rb")).sort.reject { |file| own_files.include?(file) || !record_class?(file) }
      record_files.flat_map do |file|
        scan = Scanner.new(file, [ self ], config: @config)
        Prism.parse_file(file).value.accept(scan)
        reads = scan.reads.select { |read| read.def_name && !read.takes_args && read.def_name.match?(/\A[a-z_][a-z0-9_]*[?!]?\z/) }
        reads.group_by(&:def_name).map { |name, group| [ name.to_sym, Niji.strongest(group.map(&:kind)) ] }
      end.to_h.except(*readers.keys)
    end

    # Records, not service objects that happen to live in app/models.
    def record_class?(file)
      relative = Pathname(file).relative_path_from(models_dir).to_s.delete_suffix(".rb")
      constant = relative.sub(%r{\Aconcerns/}, "").camelize.safe_constantize
      constant.is_a?(Class) && constant < ActiveRecord::Base
    end
  end
end

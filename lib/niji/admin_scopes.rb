# frozen_string_literal: true

module Niji
  # Which controllers serve admins only, and so which view directories only
  # admins see. A controller is admin-only when it inherits that from its
  # superclass (or from `config.admin_by_default` at the root), or runs an
  # admin marker before every action (`before_action :require_admin`, directly
  # or through a concern it includes), and it never lowers the guard
  # (`allow_unauthenticated_access`, `skip_before_action :require_admin`).
  class AdminScopes
    CONTROLLER = %r{\Aapp/controllers/(?!concerns/)(.+)_controller\.rb\z}
    CONCERN = %r{\Aapp/controllers/concerns/}

    # What one controller or concern file says about the admin guard.
    class Facts < Prism::Visitor
      attr_reader :superclass, :marked, :lowered, :included

      def initialize(config, lowering)
        super()
        @config = config
        @lowering = lowering
        @modules = []
        @depth = 0
        @marked = false
        @lowered = false
        @included = []
      end

      # The controller class, or for a concern its innermost module.
      def name = @class_name || @module_name

      def namespace = @namespace || []

      def visit_module_node(node)
        @modules.push(node.constant_path.slice)
        @module_name = @modules.join("::")
        super
      ensure
        @modules.pop
      end

      def visit_class_node(node)
        unless @class_name
          @namespace = @modules.dup
          @class_name = (@modules + [ node.constant_path.slice ]).join("::")
          @superclass = node.superclass&.slice
        end
        super
      end

      # Calls inside a method run when it is called, so they say nothing about
      # this class, with one exception: the `included` and `inherited` hooks
      # run on the class that includes or inherits.
      def visit_def_node(node)
        hook = %i[ included inherited ].include?(node.name)
        @depth += 1 unless hook
        super
      ensure
        @depth -= 1 unless hook
      end

      def visit_call_node(node)
        markers = @config.admin_markers.map(&:to_sym)
        symbols = node.arguments&.arguments&.filter_map { |arg| arg.unescaped.to_sym if arg.is_a?(Prism::SymbolNode) } || []
        options = node.arguments&.arguments&.grep(Prism::KeywordHashNode)&.flat_map { |hash| hash.elements.filter_map { |pair| pair.key.unescaped if pair.is_a?(Prism::AssocNode) && pair.key.is_a?(Prism::SymbolNode) } } || []

        # Lowering counts for any action, marking only for every action: an
        # unsure guard leaves the controller open, so its reads are reported.
        if @depth.zero?
          @lowered = true if @lowering.include?(node.name)
          @lowered = true if node.name == :skip_before_action && symbols.intersect?(markers)
          if (options & %w[ only except if unless ]).empty?
            @marked = true if markers.include?(node.name) && node.receiver.nil?
            @marked = true if %i[ before_action prepend_before_action ].include?(node.name) && symbols.intersect?(markers)
          end
        end
        if node.name == :include && node.receiver.nil? && node.arguments
          @included.concat(node.arguments.arguments.filter_map { |arg| arg.slice if arg.is_a?(Prism::ConstantReadNode) || arg.is_a?(Prism::ConstantPathNode) })
        end
        super
      end
    end

    # The methods a controller or concern defines whose body lowers the guard
    # (`def allow_non_admin_access(**) = skip_before_action :require_admin`).
    # Calling one of them lowers the guard too.
    class LoweringDefs < Prism::Visitor
      attr_reader :names

      def initialize(markers, lowering)
        super()
        @markers = markers
        @lowering = lowering
        @names = []
        @defs = []
      end

      def visit_def_node(node)
        @defs.push(node.name)
        super
      ensure
        @defs.pop
      end

      def visit_call_node(node)
        if @defs.any?
          symbols = node.arguments&.arguments&.filter_map { |arg| arg.unescaped.to_sym if arg.is_a?(Prism::SymbolNode) } || []
          lowers = @lowering.include?(node.name) || (node.name == :skip_before_action && symbols.intersect?(@markers))
          @names |= [ @defs.last ] if lowers && !%i[ included inherited ].include?(@defs.last)
        end
        super
      end
    end

    # controller path => its view directory, for every admin-only controller.
    def self.from(files, config: Niji.config)
      new(files, config).closed
    end

    def initialize(files, config)
      @config = config
      @controllers = {}
      @concerns = {}
      sources = files.select { |path, _| path.match?(CONTROLLER) || path.match?(CONCERN) }.transform_values { |text| Prism.parse(text).value }
      lowering = lowering_methods(sources.values)
      sources.each do |path, tree|
        facts = Facts.new(config, lowering).tap { |visitor| tree.accept(visitor) }
        next unless facts.name

        (path.match?(CONTROLLER) ? @controllers : @concerns)[facts.name] = [ path, facts ]
      end
      @status = {}
    end

    def closed
      @controllers.filter_map do |name, (path, _)|
        match = CONTROLLER.match(path)
        next if match[1] == "application" || !admin?(name)

        [ path, "app/views/#{match[1]}" ]
      end.to_h
    end

    private

    def lowering_methods(trees)
      markers = @config.admin_markers.map(&:to_sym)
      lowering = @config.guard_lowering_methods.map(&:to_sym)
      loop do
        found = trees.flat_map { |tree| LoweringDefs.new(markers, lowering).tap { |visitor| tree.accept(visitor) }.names } - lowering
        return lowering if found.empty?

        lowering |= found
      end
    end

    def admin?(name, seen = [])
      return @status[name] if @status.key?(name)
      return @config.admin_by_default if seen.include?(name)

      _, facts = @controllers.fetch(name)
      parent = resolve(facts.superclass, facts.namespace)
      inherited = parent ? admin?(parent, seen + [ name ]) : @config.admin_by_default
      concerns = facts.included.filter_map { |included| @concerns[resolve_concern(included, facts.namespace)]&.last }
      marked = facts.marked || concerns.any?(&:marked)
      lowered = facts.lowered || concerns.any?(&:lowered)
      @status[name] = (inherited || marked) && !lowered
    end

    # BaseController inside `module Admin` is Admin::BaseController.
    def resolve(constant, namespace)
      return unless constant

      candidates(constant, namespace).find { |candidate| @controllers.key?(candidate) }
    end

    def resolve_concern(constant, namespace)
      candidates(constant, namespace).find { |candidate| @concerns.key?(candidate) }
    end

    def candidates(constant, namespace)
      return [ constant.delete_prefix("::") ] if constant.start_with?("::")

      namespace.length.downto(0).map { |size| (namespace.first(size) + [ constant ]).join("::") }
    end
  end
end

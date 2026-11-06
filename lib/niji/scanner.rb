# frozen_string_literal: true

module Niji
  # Walks one file and records every read of a reader on a holder, and every
  # call that could be a relay, with whether it is the viewer's own, in an
  # admin-only place, or addressed to a mail's recipient.
  class Scanner < Prism::Visitor
    attr_reader :file, :reads, :calls

    def initialize(file, sources, config: Niji.config, admin_file: false)
      super()
      @file = file
      @sources = Array(sources)
      @config = config
      @reads = []
      @calls = []
      @mailed_to = []
      @ivar_sources = []
      @admin = admin_file || Niji.path_match?(config.admin_paths, file) ? 1 : 0
      @recipient = 0
      @defs = []
      @block_names = []
    end

    # Per mailer action, the instance variables that hold the person the mail
    # is sent to: the one in `to: @maker.email_address`, or the one assigned
    # from the expression in `to: maker.email` (`@maker = maker`). A template
    # that greets that variable greets its own recipient.
    def mail_recipients
      @mailed_to.uniq.group_by(&:first).to_h do |action, pairs|
        receivers = pairs.map(&:last)
        assigned = @ivar_sources.select { |name, _, value| name == action && receivers.include?(value) }.map { |entry| entry[1] }
        [ action, (receivers.select { |receiver| receiver.start_with?("@") } + assigned).uniq ]
      end
    end

    def visit_instance_variable_write_node(node)
      @ivar_sources << [ @defs.last&.first, node.name.to_s, node.value.slice ]
      super
    end

    # `to:` is the address a mail goes to: the person being written to, not
    # something printed for somebody else.
    def visit_assoc_node(node)
      recipient = node.key.is_a?(Prism::SymbolNode) && %w[ to cc bcc ].include?(node.key.unescaped)
      @recipient += 1 if recipient
      super
    ensure
      @recipient -= 1 if recipient
    end

    def visit_def_node(node)
      # A class method (def self.call) is never a reader on a record.
      @defs.push([ node.receiver ? "self.#{node.name}" : node.name.to_s, parameter_names(node.parameters) ])
      super
    ensure
      @defs.pop
    end

    def visit_if_node(node)
      visit(node.predicate)
      guarded(admin_predicate?(node.predicate)) { visit(node.statements) }
      visit(node.subsequent)
    end

    def visit_unless_node(node)
      visit(node.predicate)
      visit(node.statements)
      guarded(admin_predicate?(node.predicate)) { visit(node.else_clause) }
    end

    def visit_call_node(node)
      record(node)
      source = node.block.is_a?(Prism::BlockNode) && chain_source(node.receiver)
      if source
        visit(node.receiver)
        visit(node.arguments)
        declared = node.block.parameters
        declared = declared.parameters if declared.is_a?(Prism::BlockParametersNode)
        names = (declared.is_a?(Prism::ParametersNode) ? parameter_names(declared) : []) + %w[ it _1 ]
        @block_names.push([ names, source ])
        visit(node.block)
        @block_names.pop
      else
        super
      end
    end

    private

    def guarded(admin)
      @admin += 1 if admin
      yield
    ensure
      @admin -= 1 if admin
    end

    def admin_predicate?(node)
      case node
      when Prism::CallNode then @config.admin_predicates.include?(node.name)
      when Prism::AndNode then admin_predicate?(node.left) || admin_predicate?(node.right)
      when Prism::ParenthesesNode then node.body.is_a?(Prism::StatementsNode) && node.body.body.size == 1 && admin_predicate?(node.body.body.first)
      else false
      end
    end

    def parameter_names(parameters)
      return [] unless parameters

      parameters.child_nodes.compact.flat_map { |group| group.is_a?(Array) ? group : [ group ] }.filter_map do |param|
        param.name.to_s if param.respond_to?(:name) && param.name
      end
    end

    # The source whose model starts this chain (User.verified.where(...)).
    def chain_source(receiver)
      receiver = receiver.receiver while receiver.is_a?(Prism::CallNode) && receiver.receiver
      return unless receiver.is_a?(Prism::ConstantReadNode) || receiver.is_a?(Prism::ConstantPathNode)

      @sources.find { |source| source.klass.name == receiver.slice.delete_prefix("::") }
    end

    def record(node)
      if node.receiver
        @sources.each do |source|
          if (kind = source.derived[node.name])
            add_read(node, kind, own: false)
            break
          elsif (kind = source.readers[node.name]) && (holder = holder_of(node.receiver, source))
            add_read(node, kind, own: holder == :own)
            break
          end
        end
      end

      first = node.arguments&.arguments&.first
      return unless first

      @calls << Call.new(file: @file, line: node.location.start_line, name: node.name.to_s, code: "#{node.name} #{first.slice}", own: viewer?(first), admin: @admin.positive?, recipient: @recipient.positive?)
    end

    def add_read(node, kind, own:)
      def_name, params = @defs.last
      param = node.receiver.is_a?(Prism::LocalVariableReadNode) && params&.include?(node.receiver.name.to_s)
      @mailed_to << [ def_name, node.receiver.slice ] if @recipient.positive?
      @reads << Read.new(
        file: @file, line: node.location.start_line, code: node.slice, receiver: node.receiver.slice, kind:,
        own:, admin: @admin.positive?, recipient: @recipient.positive?,
        def_name:, takes_args: params&.any? || false, param: !!param
      )
    end

    def viewer?(node) = @config.viewer_expressions.include?(node.slice)

    # :own, :other, or nil when the receiver cannot hold this source's person.
    def holder_of(receiver, source)
      return :own if viewer?(receiver)

      case receiver
      when Prism::CallNode
        :other if source.holders.include?(receiver.name.to_s)
      when Prism::LocalVariableReadNode
        name = receiver.name.to_s
        :other if source.holders.include?(name) || block_names(source).include?(name)
      when Prism::InstanceVariableReadNode
        :other if source.holders.include?(receiver.name.to_s.delete("@"))
      else
        :other if it_variable?(receiver) && block_names(source).include?("it")
      end
    end

    def block_names(source)
      @block_names.select { |_, owner| owner.equal?(source) }.flat_map(&:first)
    end

    def it_variable?(node) = defined?(Prism::ItLocalVariableReadNode) && node.is_a?(Prism::ItLocalVariableReadNode)
  end
end

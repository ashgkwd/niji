# frozen_string_literal: true

module Niji
  # Method names called on self inside each def of a model file, to learn which
  # of its methods hand a reader's value on.
  class MethodBodies < Prism::Visitor
    class Collector < Prism::Visitor
      attr_reader :calls

      def initialize
        super
        @calls = []
      end

      def visit_call_node(node)
        @calls << node.name if node.receiver.nil? || node.receiver.is_a?(Prism::SelfNode)
        super
      end
    end

    def initialize(file)
      super()
      @defs = []
      @file = file
    end

    # [[method name, [names it calls on self]], ...]
    def defs
      Prism.parse_file(@file).value.accept(self)
      @defs
    end

    def visit_def_node(node)
      collector = Collector.new
      node.body&.accept(collector)
      @defs << [ node.name, collector.calls ] unless node.receiver
      super
    end
  end
end

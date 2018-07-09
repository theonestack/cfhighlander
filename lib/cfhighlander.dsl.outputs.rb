require_relative './cfhighlander.dsl.base'

module Cfhighlander

  module Dsl

    class ForwardOutputs < DslBase

      def initialize(model)
        @model = model
      end

      # dsl statements here
      #
    end

    class Output

      attr_reader :name, :value

      def initialize(name, value)
        @name = name
        @value = value
      end

    end

    class ForwardOutputsModel

      @forwardall

      attr_accessor :forwardall

    end

  end
end

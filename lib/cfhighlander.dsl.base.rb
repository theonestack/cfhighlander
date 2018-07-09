module Cfhighlander

  module Dsl
    class DslBase

      def FnGetAtt(resource, property)
        return {
            'Fn::GetAtt' => [resource, property]
        }
      end

      def Ref(resource)
        return {
            'Ref' => resource
        }
      end

      attr_accessor :config

      def initialize(parent)
        @config = parent.config unless parent.nil?
      end

      def method_missing(method, *args)
        if @config.nil?
          raise StandardError, "#{self} no config!"
        end
        # return @config["#{method}"] unless @config["#{method}"].nil?
        raise StandardError, "#{self} Unknown method or variable #{method} in Cfhighlander template"
      end

    end

  end

end


module Cfhighlander

  module Dsl
    class DslBase

      attr_accessor :config


      def GetAtt(resource, property)
        return FnGetAtt(resource, property)
      end

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

      def FnFindInMap(map, key, attr)
        return { 'Fn::FindInMap' => [map, key, attr] }
      end

      def FindInMap(map, key, attr)
        return FnFindInMap(map, key, attr)
      end

      def cfout(resource, output = nil)
        if output.nil?
          parts = resource.split('.')
          if parts.size() != 2
            raise "cfout('#{resource}'): If cfout given single argument cfout('component.OutputName') syntax must be used"
          else
            resource = parts[0]
            output = parts[1]
          end
        end

        return GetAtt(resource, "Outputs.#{output}")
      end


      def cfmap(map, key, attr)
        return FindInMap(map, key, attr)
      end


      def initialize (parent)
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


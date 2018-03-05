require_relative './highlander.dsl.base'

module Highlander

  module Dsl
    class Parameters < DslBase

      attr_accessor :param_list

      def initialize()
        @param_list = []
      end

      def addParam(param)
        existing_param = @param_list.find { |p| p.name == param.name }
        if not existing_param.nil?
          puts "Parameter being overwritten. Updating parameter #{param.name} with new definition..."
          @param_list[@param_list.index(existing_param)] = param
        else
          @param_list << param
        end
      end

      def StackParam(name, defaultValue='', isGlobal: false, noEcho: false)
        param = StackParam.new(name, 'String', defaultValue)
        param.is_global = isGlobal
        param.config = @config
        param.no_echo = noEcho
        addParam param
      end

      def ComponentParam(name, defaultValue='')
        param = ComponentParam.new(name, 'String', defaultValue)
        param.config = @config
        addParam param
      end

      def MappingParam(name, defaultValue='', &block)
        param = MappingParam.new(name, 'String', defaultValue)
        param.config = @config
        param.instance_eval(&block)
        addParam param
      end

      def OutputParam(component:, name:, default: '')
        param = OutputParam.new(component, name, default)
        param.config = @config
        addParam param
      end
    end

    class Parameter < DslBase
      attr_accessor :name, :type, :default_value, :no_echo

      def initialize(name, type, defaultValue, noEcho = false)
        @no_echo = noEcho
        @name = name
        @type = type
        @default_value = defaultValue
      end
    end

    class StackParam < Parameter
      attr_accessor :is_global
    end

    class ComponentParam < Parameter

    end

    class OutputParam < Parameter
      attr_accessor :component

      def initialize(component, name, default)
        @component = component
        @name = name
        @default_value = default
        @type = 'String'
      end
    end

    class MappingParam < Parameter

      attr_accessor :mapName, :mapKey, :mapAttribute

      def method_missing(method, *args)
        smethod = "#{method}"
        if smethod.start_with?('Map')
          puts smethod
        end

        super.method_missing(method)
      end

      def key(map_key)
        @mapKey = map_key
      end

      def attribute(key)
        @mapAttribute = key
      end

      def map(mapName)
        @mapName = mapName
      end

      def mapProvider
        mappings_provider(@mapName)
      end

    end
  end
end

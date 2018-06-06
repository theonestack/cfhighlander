require_relative './cfhighlander.dsl.base'

module Cfhighlander

  module Dsl

    # dsl statements
    class Parameters < DslBase

      attr_accessor :param_list

      def initialize()
        @param_list = []
      end

      def addParam(param)
        existing_param = @param_list.find {|p| p.name == param.name}
        if not existing_param.nil?
          puts "Parameter being overwritten. Updating parameter #{param.name} with new definition..."
          @param_list[@param_list.index(existing_param)] = param
        else
          @param_list << param
        end
      end

      def StackParam(name, defaultValue = '', isGlobal: false, noEcho: false, type: 'String')
        STDERR.puts "DEPRECATED: StackParam #{name} - Use ComponentParam instead"
        ComponentParam(name, defaultValue, isGlobal: isGlobal, noEcho: noEcho, type: type)
      end

      def OutputParam(component:, name:, isGlobal: false, noEcho: false, type: 'String')
        STDERR.puts ("DEPRECATED: OutputParam #{name} - Use ComponentParam instead. Outputut params are " +
            "autorwired by name only, with component disregarded")
        ComponentParam(name, '', isGlobal: isGlobal, noEcho: noEcho, type: type)
      end

      def ComponentParam(name, defaultValue = '', isGlobal: false, noEcho: false, type: 'String', allowedValues: nil)
        param = Parameter.new(name, type, defaultValue, noEcho, isGlobal, allowedValues)
        param.config = @config
        addParam param
      end

      def MappingParam(name, defaultValue = '', &block)
        param = MappingParam.new(name, 'String', defaultValue)
        param.config = @config
        param.instance_eval(&block)
        addParam param
      end


    end

    # model classes
    class Parameter < DslBase
      attr_accessor :name,
          :type,
          :default_value,
          :no_echo,
          :is_global,
          :provided_value,
          :allowed_values

      def initialize(name, type, defaultValue, noEcho = false, isGlobal = false, allowed_values = nil)
        @no_echo = noEcho
        @name = name
        @type = type
        @default_value = defaultValue
        @is_global = isGlobal
        @allowed_values = allowed_values
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

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
        param = ComponentParam(name, '', isGlobal: isGlobal, noEcho: noEcho, type: type)
        param.provided_value = "#{component}.#{name}"
      end

      def ComponentParam(name, defaultValue = '', isGlobal: false, noEcho: false, type: 'String', allowedValues: nil, allowedPattern: nil,
                          maxLength: nil, maxValue: nil, minLength: nil, minValue: nil, description: nil, constraintDescription: nil)
        param = Parameter.new(
          name: name,
          type: type,
          defaultValue: defaultValue,
          noEcho: noEcho,
          isGlobal: isGlobal,
          allowedValues: allowedValues,
          allowedPattern: allowedPattern,
          maxLength: maxLength,
          maxValue: maxValue,
          minLength: minLength,
          minValue: minValue,
          description: description,
          constraintDescription: constraintDescription
        )
        param.config = @config
        addParam param
        return param
      end

      def MappingParam(name, defaultValue = '', &block)
        param = MappingParam.new(
          name: name,
          type: 'String',
          defaultValue: defaultValue
        )
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
          :allowed_values,
          :allowed_pattern,
          :max_length,
          :max_value,
          :min_length,
          :min_value,
          :description,
          :constraint_description

      def initialize(params = {})
        @no_echo = params.fetch(:noEcho, false)
        @name = params.fetch(:name)
        @type = params.fetch(:type)
        @default_value = params.fetch(:defaultValue)
        @is_global = params.fetch(:isGlobal, false)
        @allowed_values = params.fetch(:allowedValues, nil)
        @provided_value = params.fetch(:providedValue, nil)
        @allowed_pattern = params.fetch(:allowedPattern, nil)
        @max_length = params.fetch(:maxLength, nil)
        @max_value = params.fetch(:maxValue, nil)
        @min_length = params.fetch(:minLength, nil)
        @min_value = params.fetch(:minValue, nil)
        @description = params.fetch(:description, nil)
        @constraint_description = params.fetch(:constraintDescription, nil)
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

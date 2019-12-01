require_relative './cfhighlander.helper'
require_relative './cfhighlander.dsl.base'
require_relative './cfhighlander.factory'
require 'cfndsl'

module Cfhighlander

  module Dsl

    class SubcomponentParameter
      attr_accessor :name, :cfndsl_value

      def initialize

      end

    end

    class Subcomponent < DslBase

      attr_accessor :distribution_format,
          :distribution_location,
          :distribution_url,
          :distribution_format,
          :component_loaded,
          :parameters,
          :param_values,
          :component_config_override,
          :export_config

      attr_reader :cfn_name,
          :conditional,
          :parent,
          :name,
          :template,
          :template_version,
          :inlined,
          :dependson,
          :condition
          
      def initialize(parent,
          name,
          template,
          param_values,
          component_sources = [],
          config = {},
          export_config = {},
          conditional = false,
          condition = nil,
          enabled = true,
          dependson = [],
          inline = false,
          distribution_format = 'yaml')

        @parent = parent
        @config = config
        @export_config = export_config
        @component_sources = component_sources
        @conditional = conditional
        @condition = condition
        @dependson = [*dependson]
        @inlined = inline
        
        template_name = template
        template_version = 'latest'
        if template.include?('@') and not (template.start_with? 'git')
          template_name = template.split('@')[0]
          template_version = template.split('@')[1]
        end

        @template = template_name
        @template_version = template_version
        @name = name
        @cfn_name = @name.gsub('-', '').gsub('_', '').gsub(' ', '')
        @param_values = param_values

        # distribution settings
        @distribution_format = distribution_format
        # by default components located at same location as master stack
        @distribution_location = '.'
        build_distribution_url

        # load component
        factory = Cfhighlander::Factory::ComponentFactory.new(@component_sources)
        @component_loaded = factory.loadComponentFromTemplate(
            @template,
            @template_version,
            @name
        )
        @component_loaded.config.extend @config

        @parameters = []

        # add condition to parent if conditonal component
        if @conditional
          condition_name = @condition.nil? ? "Enable#{@cfn_name}" : @condition
          @parent.Condition(condition_name, CfnDsl::Fn.new('Equals', [
              CfnDsl::RefDefinition.new(condition_name),
              'true'
          ]).to_json)
          @parent.Parameters do
            ComponentParam condition_name, enabled.to_s, allowedValues: %w(true false)
          end
        end
      end

      def version=(value)
        @component_loaded.version = value
      end

      def distribute_bucket=(value)
        @component_loaded.distribution_bucket = value
      end

      def distribute_prefix=(value)
        @component_loaded.distribution_prefix = value
      end

      def distribution_format=(value)
        @distribution_format = value
        build_distribution_url
      end

      def build_distribution_url
        @distribution_location = @parent.distribute_url unless @parent.distribute_url.nil?
        @distribution_url = "#{@distribution_location}/#{@name}.compiled.#{@distribution_format}"
      end

      def load(component_config_override = {})
        # Highest priority is DSL defined configuration
        component_config_override.extend @config

        @component_config_override = component_config_override

        @component_loaded.load @component_config_override
      end

      def parameter(name:, value: '', defaultValue: nil, type: nil, noEcho: nil, allowedValues: nil, allowedPattern: nil, 
                    maxLength: nil, maxValue: nil, minLength: nil, minValue: nil)
        existing_params = @component_loaded.highlander_dsl.parameters.param_list
        parameter = existing_params.find { |p| p.name == name}

        if !parameter      
          param_ovr = {}
          param_ovr[:type] = type.nil? ? 'String' : type 
          param_ovr[:noEcho] = noEcho unless noEcho.nil?
          param_ovr[:allowedValues] = allowedValues unless allowedValues.nil?
          param_ovr[:allowedPattern] = allowedPattern unless allowedPattern.nil?
          param_ovr[:maxLength] = maxLength unless maxLength.nil?
          param_ovr[:maxValue] = maxValue unless maxValue.nil?
          param_ovr[:minLength] = minLength unless minLength.nil?
          param_ovr[:minValue] = minValue unless minValue.nil?
          
          @component_loaded.highlander_dsl.Parameters do
            ComponentParam name, value, param_ovr
          end
        else
          parameter.default_value = defaultValue unless defaultValue.nil?
          parameter.type unless type.nil?
          parameter.no_echo = noEcho unless noEcho.nil?
          parameter.allowed_values = allowedValues unless allowedValues.nil?
          parameter.allowed_pattern = allowedPattern unless allowedPattern.nil?
          parameter.max_length = maxLength unless maxLength.nil?
          parameter.max_value = maxValue unless maxValue.nil?
          parameter.min_length = minLength unless minLength.nil?
          parameter.min_value = minValue unless minValue.nil?
        end
        
        @param_values[name] = value
      end

      def config(key = '', value = '')
        @component_loaded.config[key] = value
      end

      def ConfigParameter(config_key:, parameter:, defaultValue: '', type: 'String')
        Parameters do
          ComponentParam parameter, defaultValue, type: type
        end
        config config_key, Ref(parameter)
      end

      ## for all the message received, try and forward them to load component dsl
      def method_missing(method, *args, &block)
        child_dsl = @component_loaded.highlander_dsl
        if child_dsl.respond_to? method
          # child_dsl.method
          child_dsl.send method, *args, &block
        end
      end

      # Parameters should be lazy loaded, that is late-binding should happen once
      # all parameters and mappings are known
      def resolve_parameter_values(available_outputs)
        component_dsl = @component_loaded.highlander_dsl
        component_dsl.parameters.param_list.each do |component_param|
          param = Cfhighlander::Dsl::SubcomponentParameter.new
          param.name = component_param.name
          param.cfndsl_value = SubcomponentParamValueResolver.resolveValue(
              @parent,
              self,
              component_param,
              available_outputs)
          @parameters << param
        end
      end

    end

    class SubcomponentParamValueResolver
      def self.resolveValue(component, sub_component, param, available_outputs)

        puts("INFO Resolving parameter #{component.name} -> #{sub_component.name}.#{param.name}: ")

        # rule 0: this rule is here for legacy reasons and OutputParam. It should be deprecated
        # once all hl-components- repos remove any references to OutputParam
        if not param.provided_value.nil?
          component_name = param.provided_value.split('.')[0]
          output_name = param.provided_value.split('.')[1]
          source_component = component.subcomponents.find {|c| c.name == component_name}
          if source_component.nil?
            source_component = component.subcomponents.find {|c| c.component_loaded.template.template_name == component_name}
          end
          return CfnDsl::Fn.new('GetAtt', [
              source_component.name,
              "Outputs.#{output_name}"
          ]).to_json
        end

        # rule 1: check if there are values defined on component itself
        if sub_component.param_values.key?(param.name)
          puts " parameter value provided "

          param_value = sub_component.param_values[param.name]
          if param_value.is_a? String and param_value.include? '.'
            source_component_name = param_value.split('.')[0]
            source_output = param_value.split('.')[1]
            source_component = component.subcomponents.find {|sc| sc.name == source_component_name}
            # if source component exists
            if not source_component.nil?
              if source_component_name == sub_component.name
                STDERR.puts "WARNING: Parameter value on component #{source_component_name} references component itself: #{param_value}"
              else
                return CfnDsl::Fn.new('GetAtt', [
                    source_component_name,
                    "Outputs.#{source_output}"
                ]).to_json
              end
            else
              return Cfhighlander::Helper.parameter_cfndsl_value(param_value)
            end
          else
            return Cfhighlander::Helper.parameter_cfndsl_value(sub_component.param_values[param.name])
          end
        end

        # rule 1.1 mapping parameters are handled differently.
        # TODO wire mapping parameters outside of component
        if param.class == Cfhighlander::Dsl::MappingParam
          puts " mapping parameter"
          mapping_param_value = self.resolveMappingParamValue(component, sub_component, param)

          # if mapping param is not resolved, e.g. mapping not provided
          # parameters will bubble to parent component if not matched by outputs from
          # other components
          return mapping_param_value unless mapping_param_value.nil?
        end

        # rule #2: match output values from other components
        #          by parameter name
        if available_outputs.key? param.name
          component_name = available_outputs[param.name].component.name
          puts " resolved as output of #{component_name}"
          return CfnDsl::Fn.new('GetAtt', [
              component_name,
              "Outputs.#{param.name}"
          ]).to_json
        end

        # by default bubble parameter and resolve as reference on upper level
        propagated_param = param.clone
        propagated_param.name = "#{sub_component.cfn_name}#{param.name}" unless param.is_global
        component.parameters.addParam propagated_param
        puts " no autowiring candidates, propagate parameter to parent"
        return CfnDsl::RefDefinition.new(propagated_param.name).to_json

      end

      def self.resolveMappingParamValue(component, sub_component, param)

        # determine map name

        provider = nil

        mappings_name = param.mapName
        actual_map_name = mappings_name

        key_name = nil

        # priority 0: stack-level parameter of map name
        stack_param_mapname = component.parameters.param_list.find {|p| p.name == mappings_name}
        unless stack_param_mapname.nil?
          key_name = "Ref('#{mappings_name}')"
        end

        # priority 1 mapping provider keyName - used as lowest priority
        if key_name.nil?
          provider = mappings_provider(mappings_name)
          if ((not provider.nil?) and (provider.respond_to?('getDefaultKey')))
            key_name = provider.getDefaultKey
          end
        end

        # priority 2: dsl defined key name
        if key_name.nil?
          key_name = param.mapKey
          # could still be nil after this line
        end

        value = mapping_value(component: component,
            provider_name: mappings_name,
            value_name: param.mapAttribute,
            key_name: key_name
        )

        return value
      end

    end

  end
end
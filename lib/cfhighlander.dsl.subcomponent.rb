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
          :template_version

      def initialize(parent,
          name,
          template,
          param_values,
          component_sources = [],
          config = {},
          export_config = {},
          conditional = false,
          enabled = true,
          distribution_format = 'yaml')

        @parent = parent
        @config = config
        @export_config = export_config
        @component_sources = component_sources
        @conditional = conditional

        template_name = template
        template_version = 'latest'
        if template.include?('@') and not (template.start_with? 'git')
          template_name = template.split('@')[0]
          template_version = template.split('@')[1]
        end

        @template = template_name
        @template_version = template_version
        @name = name
        @cfn_name = @name.gsub('-','').gsub('_','').gsub(' ','')
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
          condition_param_name = "Enable#{@cfn_name}"
          @parent.Condition(condition_param_name, CfnDsl::Fn.new('Equals', [
              CfnDsl::RefDefinition.new(condition_param_name),
              'true'
          ]).to_json)
          @parent.Parameters do
            ComponentParam condition_param_name, enabled.to_s, allowedValues: %w(true false)
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

      def parameter(name:, value:)
        @param_values[name] = value
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

        print("INFO Resolving parameter #{component.name} -> #{sub_component.name}.#{param.name}: ")

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
          return self.resolveMappingParamValue(component, sub_component, param)
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

        if value.nil?
          return "'#{param.default_value}'" unless param.default_value.empty?
          return "''"
        end

        return value
      end

    end

  end
end
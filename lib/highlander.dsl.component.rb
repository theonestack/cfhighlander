require_relative './highlander.helper'
require_relative './highlander.dsl.base'
require_relative './highlander.factory'

module Highlander

  module Dsl

    class SubcomponentParameter
      attr_accessor :name, :cfndsl_value

      def initialize

      end

    end


    class Component < DslBase

      attr_accessor :name,
          :template,
          :template_version,
          :distribution_format,
          :distribution_location,
          :distribution_url,
          :distribution_format,
          :component_loaded,
          :parameters,
          :param_values,
          :parent,
          :component_config_override,
          :export_config

      def initialize(parent,
          name,
          template,
          param_values,
          component_sources = [],
          config = {},
          export_config = {},
          distribution_format = 'yaml')

        @parent = parent
        @config = config
        @export_config = export_config
        @component_sources = component_sources

        template_name = template
        template_version = 'latest'
        if template.include?('@') and not (template.start_with? 'git')
          template_name = template.split('@')[0]
          template_version = template.split('@')[1]
        end

        @template = template_name
        @template_version = template_version
        @name = name
        @param_values = param_values

        # distribution settings
        @distribution_format = distribution_format
        # by default components located at same location as master stack
        @distribution_location = '.'
        build_distribution_url

        # load component
        factory = Highlander::Factory::ComponentFactory.new(@component_sources)
        @component_loaded = factory.loadComponentFromTemplate(
            @template,
            @template_version,
            @name
        )
        @component_loaded.config.extend @config

        @parameters = []
        # load_parameters
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
        # check for component config on parent
        parent = @parent

        # Highest priority is DSL defined configuration
        component_config_override.extend @config

        @component_config_override = component_config_override

        @component_loaded.load @component_config_override
      end

      # Parameters should be lazy loaded, that is late-binding should happen once
      # all parameters and mappings are known
      def load_parameters
        component_dsl = @component_loaded.highlander_dsl
        component_dsl.parameters.param_list.each do |component_param|
          param = Highlander::Dsl::SubcomponentParameter.new
          param.name = component_param.name
          param.cfndsl_value = SubcomponentParamValueResolver.resolveValue(
              @parent,
              self,
              component_param)
          @parameters << param
        end
      end

    end

    class SubcomponentParamValueResolver
      def self.resolveValue(component, sub_component, param)

        puts("Resolving parameter #{component.name} -> #{sub_component.name}.#{param.name}")

        # check if there are values defined on component itself
        if sub_component.param_values.key?(param.name)
          return Highlander::Helper.parameter_cfndsl_value(sub_component.param_values[param.name])
        end

        if param.class == Highlander::Dsl::StackParam
          return self.resolveStackParamValue(component, sub_component, param)
        elsif param.class == Highlander::Dsl::ComponentParam
          return self.resolveComponentParamValue(component, sub_component, param)
        elsif param.class == Highlander::Dsl::MappingParam
          return self.resolveMappingParamValue(component, sub_component, param)
        elsif param.class == Highlander::Dsl::OutputParam
          return self.resolveOutputParamValue(component, sub_component, param)
        else
          raise "#{param.class} not resolvable to parameter value"
        end
      end

      def self.resolveStackParamValue(component, sub_component, param)
        param_name = param.is_global ? param.name : "#{sub_component.name}#{param.name}"
        return "Ref('#{param_name}')"
      end

      def self.resolveComponentParamValue(component, sub_component, param)
        # check component config for param value
        # TODO
        # check stack config for param value
        # TODO
        # return default value
        return "'#{param.default_value}'"
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


        return value
      end

      def self.resolveOutputParamValue(component, sub_component, param)
        component_name = param.component
        resource_name = nil
        if not sub_component.export_config.nil?
          if sub_component.export_config.key? component_name
            resource_name = sub_component.export_config[component_name]
          end
        end

        if resource_name.nil?
          # find by component
          resource = component.components.find {|c| c.name == component_name}
          resource_name = resource.name unless resource.nil?
          if resource_name.nil?
            resource = component.components.find {|c| c.template == component_name}
            resource_name = resource.name unless resource.nil?
          end
        end

        if resource_name.nil?
          raise "#{sub_component.name}.Params.#{param.name}: Failed to resolve OutputParam '#{param.name}' with source '#{component_name}'. Component not found!"
        end

        return "FnGetAtt('#{resource_name}','Outputs.#{param.name}')"
      end
    end

  end
end
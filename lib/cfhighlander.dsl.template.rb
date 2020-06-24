# require all extensions

extensions_folder = "#{File.dirname(__FILE__)}/../hl_ext"

Dir["#{extensions_folder}/*.rb"].each { |f|
  require f
}

# require libraries

require_relative './cfhighlander.dsl.base'
require_relative './cfhighlander.dsl.params'
require_relative './cfhighlander.dsl.subcomponent'
require_relative './cfhighlander.config.loader'

module Cfhighlander

  module Dsl
    class Condition < DslBase

      attr_reader :name, :expression

      def initialize(name, expression)
        @name = name
        @expression = expression
      end
    end
    class HighlanderTemplate < DslBase

      attr_accessor :mappings,
          :parameters,
          :name,
          :version,
          :distribute_url,
          :distribution_bucket,
          :distribution_prefix,
          :lambda_functions_keys,
          :description,
          :dependson_components,
          :template_dir,
          :template_timeout

      attr_reader :conditions,
          :subcomponents,
          :config_overrides,
          :extended_template

      def initialize
        @mappings = []
        @subcomponents = []
        @config = { 'mappings' => {}, 'component_version' => 'latest' }
        @component_configs = {}
        @version = 'latest'
        @distribute_url = nil
        @distribution_prefix = ''
        @component_sources = []
        @parameters = Parameters.new
        @lambda_functions_keys = []
        @dependson_components_templates = []
        @dependson_components = []
        @template_timeout = nil
        @conditions = []
        @config_overrides = {}
        @extended_template = nil
        # execution blocks for subcomponents
        @subcomponents_exec = {}
        @template_dir = nil
      end

      # DSL statements

      def addMapping(name, map)
        @mappings << name
        @config['mappings'] = {} unless @config.key?('mappings')
        @config['mappings'][name] = map
      end

      def Name(name)
        # nested components always have their name dictated by parent
        # component, defaulting to template name
        if (not @config.key? 'nested_component')
          @name = name
          @config['component_name'] = name
        end
      end

      def Description(description)
        @description = description
        @config['description'] = description
      end

      def template_dir=(value)
        @template_dir = value
        @config['template_dir'] = value
      end

      def Parameters(&block)
        @parameters.config = @config
        @parameters.instance_eval(&block) unless block.nil?
      end

      # def ComponentParam(argc*, argv)
      #   @parameters.ComponentParam(argc, argv)
      # end

      def Condition(name, expression)
        @conditions << Condition.new(name, expression)
      end

      def DynamicMappings(providerName)
        maps = mappings_provider_maps(providerName, self.config)
        maps.each { |name, map| addMapping(name, map) } unless maps.nil?
      end

      def DependsOn(template)
        @dependson_components_templates << template
      end

      def Extends(template)
        @extended_template = template
      end

      def Component(template_arg = nil, template: nil,
          name: template,
          param_values: {},
          config: {},
          export_config: {},
          conditional: false,
          condition: nil,
          enabled: true,
          dependson: [],
          timeout: nil,
          render: Cfhighlander::Model::Component::Substack,
          &block)
        puts "INFO: Requested subcomponent #{name} with template #{template}"
        if ((not template_arg.nil?) and template.nil?)
          template = template_arg
        elsif (template_arg.nil? and template.nil?)
          raise 'Component must be defined with template name at minimum,' +
              ' passed as first argument, or template: named arguent'
        end

        name = template if name.nil?

        # load component
        component = Cfhighlander::Dsl::Subcomponent.new(self,
            name,
            template,
            param_values,
            @component_sources,
            config,
            export_config,
            conditional,
            condition,
            enabled,
            dependson,
            timeout,
            render == Cfhighlander::Model::Component::Inline
        )
        # component.instance_eval(&block) unless block.nil?
        @subcomponents_exec[name] = block unless block.nil?
        component.distribute_bucket = @distribution_bucket unless @distribution_bucket.nil?
        component.distribute_prefix = @distribution_prefix unless @distribution_prefix.nil?
        component.version = @version unless @version.nil?
        @component_configs[name] = config
        @subcomponents << component
      end

      def ComponentVersion(version)
        @version = version
        @config['component_version'] = version
        build_distribution_url
      end

      def DistributionPrefix(prefix)
        @distribution_prefix = prefix
        build_distribution_url
      end

      def DistributionBucket(bucket_name)
        @distribution_bucket = bucket_name
        build_distribution_url
      end

      def ComponentDistribution(s3_url)
        if s3_url.start_with? 's3://'
          if s3_url.split('/').length < 4
            raise 'Unrecognised distribution url, only supporting s3://bucket/prefix urls'
          end
          parts = s3_url.split('/')
          @distribution_bucket = parts[2]
          @distribution_prefix = parts[3]
          i = 4
          while i < parts.size()
            @distribution_prefix += "/#{parts[i]}"
            i += 1
          end
          @distribution_prefix = @distribution_prefix.chomp('/')

          build_distribution_url
        else
          raise 'Unrecognised distribution url, only supporting s3://bucket/prefix urls'
        end
      end

      def ComponentSources(sources_array)
        @component_sources = sources_array
      end

      def LambdaFunctions(config_key)
        @lambda_functions_keys << config_key
      end

      # Internal and interface functions

      def loadComponents

        # empty config overrides to start with
        @config_overrides = Hash[@subcomponents.collect { |c| [c.name, { 'nested_component' => true }] }]
        @named_components = Hash[@subcomponents.collect { |c| [c.name, c] }]

        # populate overrides with master config defined overrides
        load_configfile_component_config

        # populate overrides with config defined explictily
        load_explicit_component_config

        # apply configuration exports
        apply_config_overrides
        apply_config_exports


        # component exports may have overriden some of explicit / configfile configuration, reapply
        load_configfile_component_config
        load_explicit_component_config

        # apply extension exports
        load_extension_exports


        # load components and extract parent stack parameters and mappings
        @subcomponents.each do |component|

          component.load @config_overrides[component.name]

          # add all of it's stack parameters unless same template has been already processed
          component
              .component_loaded
              .highlander_dsl
              .parameters
              .param_list.each do |param|

            # for map parameters add maps
            if param.class == Cfhighlander::Dsl::MappingParam
              if not param.mapProvider.nil?
                maps = param.mapProvider.getMaps(component.component_loaded.config)
                maps.each do |name, map|
                  if not @mappings.include? name
                    #1. add mapping name to model
                    @mappings << name
                    #2. add mapping to config to be rendered via cfndsl
                    @config['mappings'] = {} if @config['mappings'].nil?
                    @config['mappings'][name] = map
                  end
                end unless maps.nil?
              end
            end

          end
          if @subcomponents_exec.key? component.name
            component.instance_eval &@subcomponents_exec[component.name]
          end
          component.component_loaded.eval_cfndsl
        end

        # in 2nd pass, load parameters
        # 2nd pass is required as all of cfndsl models need to be populated
        available_outputs = {}
        @subcomponents.each do |c|
          c.component_loaded.outputs.each do |out|
            available_outputs[out.name] = out
          end
        end

        @subcomponents.each do |component|
          component.resolve_parameter_values available_outputs
        end

        @dependson_components_templates.each do |template|
          component = Cfhighlander::Dsl::Subcomponent.new(self,
              template,
              template,
              {},
              @component_sources
          )
          component.load
          @dependson_components << component
        end
      end

      def load_extension_exports
        @subcomponents.each do |c|
          component = c.component_loaded
          config = component.config
          if ((config.key? 'lib_export') and (config['lib_export'].key? 'global'))

            global_export_config = config['lib_export']['global']
            if global_export_config.key? 'cfndsl'
              global_export_config['cfndsl'].each do |exported_extension|
                extension_file_path = "#{component.component_dir}/ext/cfndsl/#{exported_extension}.rb"
                @subcomponents.each do |cr|
                  cr.component_loaded.cfndsl_ext_files << extension_file_path unless cr == c
                end
              end
            end

          end
        end
      end

      def apply_config_overrides
        @config_overrides.each { |component_name, component_override|
          @named_components[component_name].component_loaded.config.extend(component_override)
        }
      end

      def load_configfile_component_config
        if (@config.key? 'components')
          @config['components'].each { |component_name, component_config|
            if component_config.key?('config')
              if @config_overrides.key? component_name
                @config_overrides[component_name].extend(component_config['config'])
              else
                STDERR.puts("WARN: Overriding config for non-existing component #{component_name}")
              end
            end
          }
        end
      end

      def apply_config_exports
        # first export from master to all children
        if ((@config.key? 'config_export') and (@config['config_export']['global']))
          @config['config_export']['global'].each { |global_export_key|
            if @config.key? global_export_key
              @config_overrides.each { |cname, co|
                co[global_export_key] = @config[global_export_key]
              }
            end
          }
        end

        @subcomponents.each { |component|
          cl = component.component_loaded
          if ((not cl.config.nil?) and (cl.config.key? 'config_export'))

            # global config
            if cl.config['config_export'].key? 'global'
              cl.config['config_export']['global'].each { |global_export_key|

                # global config is exported to parent and every component
                if cl.config.key? global_export_key

                  # cname is for component name, co for component override
                  @config_overrides.each { |cname, co|

                    # if templates are different e.g don't export from vpc to vpc
                    config_receiver_component = @named_components[cname]
                    if config_receiver_component.template != component.template
                      if (not config_receiver_component.export_config.nil?) and (config_receiver_component.export_config.key? component.template)
                        allow_from_component_name = config_receiver_component.export_config[component.template]
                        if allow_from_component_name == component.name
                          puts("INFO: Exporting key #{global_export_key} from component #{component.name} to #{cname}")
                          co[global_export_key] = cl.config[global_export_key]
                        end
                      else
                        puts("INFO: Exporting key #{global_export_key} from component #{component.name} to #{cname}")
                        co[global_export_key] = cl.config[global_export_key]
                      end
                    end
                  }


                else
                  STDERR.puts("Trying to export non-existent configuration key #{global_export_key}")
                end
              }
            end

            if cl.config['config_export'].key? 'component'
              cl.config['config_export']['component'].each { |component_name, export_keys|
                # check if there is configuration of export from this component
                # and if there is export configuration for given component name

                if (not component.export_config.nil?) and (component.export_config.key? component_name)
                  # if there is component with such name
                  if @config_overrides.key? component.export_config[component_name]
                    # override the config
                    real_component_name = component.export_config[component_name]
                    export_keys.each { |export_component_key|
                      puts("Exporting config for key=#{export_component_key} from #{component.name} to #{real_component_name}")
                      if not @config_overrides[real_component_name].key? export_component_key
                        @config_overrides[real_component_name][export_component_key] = {}
                      end
                      @config_overrides[real_component_name][export_component_key].extend(cl.config[export_component_key])
                    }
                  else
                    STDERR.puts("Trying to export configuration for non-existant component #{component.export_config[component_name]}")
                  end
                elsif @config_overrides.key? component_name
                  export_keys.each { |export_component_key|
                    puts("Exporting config for key=#{export_component_key} from #{component.name} to #{component_name}")
                    if not @config_overrides[component_name].key? export_component_key
                      @config_overrides[component_name][export_component_key] = {}
                    end
                    @config_overrides[component_name][export_component_key].extend(cl.config[export_component_key])
                  }
                else
                  STDERR.puts("Trying to export configuration for non-existant component #{component_name}")
                end
              }
            end
            # component config
            # loop over keys
            # check if there
          end
        }
      end

      def load_explicit_component_config
        @component_configs.each { |component_name, component_config|
          @config_overrides[component_name].extend(component_config)
        }

      end

      def distribute_bucket=(value)
        @distribution_bucket = value
        build_distribution_url
      end

      def distribute_prefix=(value)
        @distribution_prefix = value
        build_distribution_url
      end

      # def name=(value)
      #   self.Name(value)
      # end

      def build_distribution_url
        if not (@distribution_bucket.nil? or @distribution_prefix.nil?)
          @distribute_url = "https://#{@distribution_bucket}.s3.amazonaws.com/#{@distribution_prefix}"
          @distribute_url = "#{@distribute_url}/#{@version}" unless @version.nil?
          @subcomponents.each { |component|
            component.distribute_bucket = @distribution_bucket unless @distribution_bucket.nil?
            component.distribute_prefix = @distribution_prefix unless @distribution_prefix.nil?
            component.version = @version unless @version.nil?
            component.build_distribution_url
          }
        end
      end


    end
  end

end

def CfhighlanderTemplate(&block)

  if @parent_dsl.nil?
    instance = Cfhighlander::Dsl::HighlanderTemplate.new
    puts "Processing higlander component #{@name}\n\tLocation:#{@highlander_dsl_path}" +
        "\n\tConfig:#{@config}"
  else
    instance = @parent_dsl
    puts "Processing higlander component #{@name}\n\tLocation:#{@highlander_dsl_path}" +
        "\n\tConfig:#{@config}\n\tParent: #{@parent_template}"
  end

  instance.config = @config

  @mappings.each do |key, val|
    instance.addMapping(key, val)
  end

  unless @version.nil?
    instance.version = @version
    instance.config['component_version'] = @version
  end


  instance.name = @template.template_name
  instance.template_dir = @template.template_location
  instance.instance_eval(&block)

  unless @distribution_bucket.nil?
    instance.DistributionBucket(@distribution_bucket)
  end
  unless @distribution_prefix.nil?
    instance.DistributionPrefix(@distribution_prefix)
  end

  # process convention over configuration componentname.config.yaml files
  config_loader = Cfhighlander::Config::Loader.new

  @potential_subcomponent_overrides.each do |name, config|

    # if there is component with given file name
    first_component = name.split('.').first
    if (not instance.subcomponents.find { |s| s.name == first_component }.nil?)
      instance.config['components'] = {} unless instance.config.key? 'components'
      instance.config['components'][name] = {} unless instance.config['components'].key? name
      instance.config['components'][name]['config'] = {} unless instance.config['components'][name].key? 'config'

      # prevention of infinite recursion when applied to legacy configurations
      if config.key? 'components'
        if config['components'].key? name
          if config['components'][name].key? 'config'
            # old legacy format takes priority, but these can be mixed
            config.extend config['components'][name]['config']
          end
        end
      end
      instance.config.extend(config_loader.get_nested_config(name, config))
    end
  end

  # load sub-components
  instance.loadComponents

  return instance
end

def CfhighlanderComponent(&block)
  STDERR.puts("DEPRECATED: #{@template.template_name}: use CfhighlanderTemplate instead of CfhighlanderComponent")
  CfhighlanderTemplate(&block)
end

def HighlanderComponent(&block)
  STDERR.puts("DEPRECATED: #{@template.template_name}: use CfhighlanderTemplate instead of HighlanderComponent")
  CfhighlanderTemplate(&block)
end

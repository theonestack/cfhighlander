require 'yaml'

module Cfhighlander

  module Model

    class Component

      Inline = 'inline'
      Substack = 'substack'

      attr_accessor :component_dir,
          :config,
          :highlander_dsl_path,
          :cfndsl_path,
          :highlander_dsl,
          :cfndsl_content,
          :mappings,
          :name,
          :template,
          :version,
          :distribution_bucket,
          :distribution_prefix,
          :component_files,
          :cfndsl_ext_files,
          :lambda_src_files,
          :parent_template,
          :template_finder,
          :factory,
          :extended_component,
          :is_parent_component
      attr_reader :outputs,
          :factory,
          :extended_component,
          :potential_subcomponent_overrides,
          :cfn_model,
          :cfn_model_raw


      def initialize(template_meta, component_name, factory)
        @template = template_meta
        @name = component_name
        @component_dir = template_meta.template_location
        @mappings = {}
        @version = template_meta.template_version
        @distribution_bucket = nil
        @distribution_prefix = nil
        @component_files = []
        @cfndsl_ext_files = []
        @lambda_src_files = []
        @factory = factory
        @extended_component = nil
        @parent_dsl = nil
        @potential_subcomponent_overrides = {}
        @is_parent_component = false
      end

      def distribution_bucket=(value)
        if not @highlander_dsl.nil?
          @highlander_dsl.DistributionBucket(value)
        end
        @distribution_bucket = value
      end

      def distribution_prefix=(value)
        if not @highlander_dsl.nil?
          @highlander_dsl.DistributionPrefix(value)
        end
        @distribution_prefix = value
      end

      # load component configuration files
      def load_config()
        @config = {} if @config.nil?
        Dir["#{@component_dir}/*.config.yaml"].each do |config_file|
          puts "INFO Loading config for #{@name}: read file:#{config_file} "
          partial_config = YAML.load(File.read(config_file))
          if (not partial_config)
            STDERR.puts "WARNING: Configuration file #{config_file} could not be loaded"
            next
          end
          unless (partial_config.nil? or partial_config.key? 'subcomponent_config_file')
            @config.extend(partial_config)
            @component_files << config_file
          end
          fname = File.basename(config_file)
          potential_component_name = fname.gsub('.config.yaml', '')
          @potential_subcomponent_overrides[potential_component_name] = partial_config
        end
      end

      # load extensions
      def loadDepandantExt()
        @highlander_dsl.dependson_components.each do |requirement|
          requirement.component_loaded.cfndsl_ext_files.each do |file|
            @cfndsl_ext_files << file
          end
        end
      end

      # evaluate components template
      # @param [Hash] config_override
      def load(config_override = nil)
        if @component_dir.start_with? 'http'
          raise StandardError, 'http(s) sources not supported yet'
        end

        legacy_cfhighlander_path = "#{@component_dir}/#{@template.template_name}.highlander.rb"
        if File.exist? legacy_cfhighlander_path
          STDERR.puts "DEPRECATED: #{legacy_cfhighlander_path} - Use *.cfhighlander.rb"
          @highlander_dsl_path = legacy_cfhighlander_path
        else
          @highlander_dsl_path = "#{@component_dir}/#{@template.template_name}.cfhighlander.rb"
        end

        @cfndsl_path = "#{@component_dir}/#{@template.template_name}.cfndsl.rb"
        candidate_mappings_path = "#{@component_dir}/*.mappings.yaml"
        candidate_dynamic_mappings_path = "#{@component_dir}/#{@template.template_name}.mappings.rb"

        @cfndsl_ext_files += Dir["#{@component_dir}/ext/cfndsl/*.rb"]
        @lambda_src_files += Dir["#{@component_dir}/lambdas/**/*"].find_all { |p| not File.directory? p }
        @component_files += @cfndsl_ext_files
        @component_files += @lambda_src_files

        @config = {} if @config.nil?

        @config.extend config_override unless config_override.nil?
        @config['component_version'] = @version unless @version.nil?
        @config['component_name'] = @name
        @config['template_name'] = @template.template_name
        @config['template_version'] = @template.template_version

        Dir[candidate_mappings_path].each do |mapping_file|
          mappings = YAML.load(File.read(mapping_file))
          @component_files << mapping_file
          mappings.each do |name, map|
            @mappings[name] = map
          end unless mappings.nil?
        end

        if File.exist? candidate_dynamic_mappings_path
          require candidate_dynamic_mappings_path
          @component_files << candidate_dynamic_mappings_path
        end

        @component_files << @highlander_dsl_path


        # evaluate template file and load parent if defined
        evaluateHiglanderTemplate

        # set version if not defined
        @highlander_dsl.ComponentVersion(@version) unless @version.nil?


        if @highlander_dsl.description.nil?
          if template.template_name == @name
            description = "#{@name}@#{template.template_version} - v#{@highlander_dsl.version}"
          else
            description = "#{@name} - v#{@highlander_dsl.version}"
            description += " (#{template.template_name}@#{template.template_version})"
          end

          @highlander_dsl.Description(description)
        end unless @is_parent_component

        # set (override) distribution options
        @highlander_dsl.DistributionBucket(@distribution_bucket) unless @distribution_bucket.nil?
        @highlander_dsl.DistributionPrefix(@distribution_prefix) unless @distribution_prefix.nil?


        loadDepandantExt()
      end

      def inheritParentTemplate
        if not @parent_template.nil?
          extended_component = @factory.loadComponentFromTemplate(@parent_template)
          extended_component.is_parent_component = true
          extended_component.load(@config)

          @config = extended_component.config.extend(@config)
          @mappings = extended_component.mappings.extend(@mappings)
          @cfndsl_ext_files += extended_component.cfndsl_ext_files
          @lambda_src_files += extended_component.lambda_src_files
          @extended_component = extended_component

          # extend cfndsl, first comes parent, than child
          # this allows for child component to shadow parent component
          # defined resources
          @cfndsl_content = extended_component.cfndsl_content + @cfndsl_content

          @parent_dsl = extended_component.highlander_dsl

        end
      end

      def loadCfndslContent
        if File.exist? @cfndsl_path
          @component_files << @cfndsl_path
          @cfndsl_content = File.read(@cfndsl_path)
          @cfndsl_content.strip!
          # if there is CloudFormation do [content] end extract only contents
          ### Regex \s is whitespace
          match_data = /^CloudFormation do\s(.*)end\s?$/m.match(@cfndsl_content)
          if not match_data.nil?
            @cfndsl_content = match_data[1]
          end

        else
          @cfndsl_content = ''
        end
      end

      def evaluateHiglanderTemplate
        loadCfndslContent

        cfhl_script = ''
        @config.each do |key, val|
          cfhl_script += ("\n#{key} = #{val.inspect}\n")
        end
        cfhl_script += File.read(@highlander_dsl_path)

        cfhl_dsl = eval(cfhl_script, binding)
        if not cfhl_dsl.extended_template.nil?
          @parent_template = cfhl_dsl.extended_template
          inheritParentTemplate
          puts "INFO: #{@template} extends #{@parent_template}, loading parent definition..."
          # 2nd pass, template instance is already created from parent
          @highlander_dsl = eval(cfhl_script, binding)
        else
          @highlander_dsl = cfhl_dsl
        end
      end

      # evaluates cfndsl with current config
      def set_cfndsl_model(value)
        @cfn_model = value.as_json
        @cfn_model_raw = JSON.parse(@cfn_model.to_json)
      end
      def eval_cfndsl
        compiler = Cfhighlander::Compiler::ComponentCompiler.new self
        # there is no need for processing lambda source code during cloudformation evaluation,
        # this version never gets published
        compiler.process_lambdas = false
        @cfn_model = compiler.evaluateCloudFormation().as_json
        @cfn_model_raw = JSON.parse(@cfn_model.to_json)
        @outputs = (
        if @cfn_model.key? 'Outputs'
        then
          @cfn_model['Outputs'].map { |k, v| ComponentOutput.new self, k, v }
        else
          []
        end
        )
      end
    end

    class ComponentOutput

      attr_reader :component, :name, :value

      def initialize(component, name, value)
        @component = component
        @name = name
        @value = value
      end
    end

  end

end


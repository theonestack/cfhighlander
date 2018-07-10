require 'yaml'

module Cfhighlander

  module Model

    class Component

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
          :lambda_src_files

      attr_reader :cfn_model,
          :outputs,
          :potential_subcomponent_overrides

      def initialize(template_meta, component_name)
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
        @potential_subcomponent_overrides = {}
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
          unless (partial_config.nil? or partial_config.key? 'subcomponent_config_file')
            @config.extend(partial_config)
            @component_files << config_file
          end
          fname = File.basename(config_file)
          potential_component_name = fname.gsub('.config.yaml','')
          @potential_subcomponent_overrides[potential_component_name] = partial_config
        end
      end

      # load extensions
      def loadDepandantExt()
        @highlander_dsl.dependson_components.each do |requirement|
          requirement.component_loaded.cfndsl_ext_files.each do |file|
            cfndsl_ext_files << file
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
        @lambda_src_files += Dir["#{@component_dir}/lambdas/**/*"].find_all {|p| not File.directory? p}
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

        # 1st pass - parse the file
        @component_files << @highlander_dsl_path

        cfhl_script = ''
        @config.each do |key, val|
          cfhl_script += ("\n#{key} = #{val.inspect}\n")
        end
        cfhl_script += File.read(@highlander_dsl_path)

        @highlander_dsl = eval(cfhl_script, binding)

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
        end

        # set (override) distribution options
        @highlander_dsl.DistributionBucket(@distribution_bucket) unless @distribution_bucket.nil?
        @highlander_dsl.DistributionPrefix(@distribution_prefix) unless @distribution_prefix.nil?

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

        loadDepandantExt()
      end

      # evaluates cfndsl with current config
      def eval_cfndsl
        compiler = Cfhighlander::Compiler::ComponentCompiler.new self
        # there is no need for processing lambda source code during cloudformation evaluation,
        # this version never gets published
        compiler.process_lambdas = false
        @cfn_model = compiler.evaluateCloudFormation().as_json
        @outputs = (
        if @cfn_model.key? 'Outputs'
        then
          @cfn_model['Outputs'].map {|k, v| ComponentOutput.new self, k, v}
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


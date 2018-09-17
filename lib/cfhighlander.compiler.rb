require 'cfndsl'
require 'erb'
require 'fileutils'
require 'cfndsl/globals'
require 'cfndsl/version'
require 'json'
require 'yaml'
require 'open-uri'
require 'net/http'
require 'net/https'
require 'highline/import'
require 'zip'
require_relative './util/zip.util'

module Cfhighlander

  module Compiler

    class ComponentCompiler

      @@global_extensions_paths = []

      attr_accessor :workdir,
          :component,
          :compiled_subcomponents,
          :component_name,
          :config_output_location,
          :dsl_output_location,
          :cfn_output_location,
          :cfn_template_paths,
          :silent_mode,
          :lambda_src_paths,
          :process_lambdas

      def initialize(component)

        @workdir = ENV['CFHIGHLANDER_WORKDIR']
        @component = component
        @sub_components = []
        @component_name = component.highlander_dsl.name.downcase
        @cfndsl_compiled = false
        @config_compiled = false
        @cfn_template_paths = []
        @lambdas_processed = false
        @silent_mode = false
        @lambda_src_paths = []
        @config_yaml_path = nil
        @cfn_model = nil
        @process_lambdas = true

        if @@global_extensions_paths.empty?
          global_extensions_folder = "#{File.dirname(__FILE__)}/../cfndsl_ext"
          Dir["#{global_extensions_folder}/*.rb"].each {|f| @@global_extensions_paths << f}
        end

        @component.highlander_dsl.subcomponents.each do |sub_component|
          sub_component_compiler = Cfhighlander::Compiler::ComponentCompiler.new(sub_component.component_loaded)
          sub_component_compiler.component_name = sub_component.name
          @sub_components << sub_component_compiler
        end
      end

      def process_lambdas=(value)
        @process_lambdas = value
        @sub_components.each {|scc| scc.process_lambdas = value}
      end

      def silent_mode=(value)
        @silent_mode = value
        @sub_components.each {|scc| scc.silent_mode = value}
      end

      def compileCfnDsl(out_format)
        processLambdas unless @lambdas_processed
        writeConfig unless @config_written
        dsl = @component.highlander_dsl
        component_cfndsl = @component.cfndsl_content

        @component.highlander_dsl.subcomponents.each {|sc|
          sc.distribution_format = out_format
        }

        # indent component cfndsl
        component_cfndsl.gsub!("\n", "\n\t")
        component_cfndsl.gsub!("\r\n", "\r\n\t")
        # render cfndsl
        renderer = ERB.new(File.read("#{__dir__}/../templates/cfndsl.component.template.erb"), nil, '-')
        cfn_template = renderer.result(OpenStruct.new({
            'dsl' => dsl,
            'component_cfndsl' => component_cfndsl,
            'component_requires' => (@@global_extensions_paths + @component.cfndsl_ext_files)
        }).instance_eval {binding})

        # write to output file
        output_dir = "#{@workdir}/out/cfndsl"
        @dsl_output_location = output_dir
        output_path = "#{output_dir}/#{@component_name}.compiled.cfndsl.rb"
        FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)
        File.write(output_path, cfn_template)
        puts "cfndsl template for #{dsl.name} written to #{output_path}"
        @cfndsl_compiled_path = output_path

        @sub_components.each {|subcomponent_compiler|
          puts "Rendering sub-component cfndsl: #{subcomponent_compiler.component_name}"
          subcomponent_compiler.compileCfnDsl out_format
        }

        @cfndsl_compiled = true

      end

      def evaluateCloudFormation(format = 'yaml')
        #compile cfndsl templates first
        compileCfnDsl format unless @cfndsl_compiled

        # write config
        cfndsl_opts = []
        cfndsl_opts.push([:yaml, @config_yaml_path])

        # grab cfndsl model
        model = CfnDsl.eval_file_with_extras(@cfndsl_compiled_path, cfndsl_opts, false)
        @cfn_model = model
        return model
      end

      def compileCloudFormation(format = 'yaml')

        dsl = @component.highlander_dsl

        # create out dir if not there
        @cfn_output_location = "#{@workdir}/out/#{format}"
        output_dir = @cfn_output_location
        FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)


        # compile templates
        output_path = "#{output_dir}/#{@component_name}.compiled.#{format}"
        @cfn_template_paths << output_path
        # configure cfndsl


        # grab cfndsl model
        model = evaluateCloudFormation

        # write resulting cloud formation template
        if format == 'json'
          output_content = JSON.pretty_generate(model)
        elsif format == 'yaml'
          output_content = JSON.parse(model.to_json).to_yaml
        else
          raise StandardError, "#{format} not supported for cfn generation"
        end

        File.write(output_path, output_content)
        # `cfndsl #{@cfndsl_compiled_path} -p -f #{format} -o #{output_path} --disable-binding`
        puts "CloudFormation #{format.upcase} template for #{dsl.name} written to #{output_path}"

        # compile sub-component templates
        @sub_components.each do |sub_component|
          sub_component.compileCloudFormation format
          @cfn_template_paths += sub_component.cfn_template_paths
          @lambda_src_paths += sub_component.lambda_src_paths
        end

      end

      def writeConfig(write_subcomponents_config = false)
        @config_output_location = "#{@workdir}/out/config"
        config_yaml_path = "#{@config_output_location}/#{@component_name}.config.yaml"
        FileUtils.mkdir_p(@config_output_location) unless Dir.exist?(@config_output_location)

        File.write(config_yaml_path, @component.config.to_yaml)
        puts "Config for #{@component.highlander_dsl.name} written to #{config_yaml_path}"

        if write_subcomponents_config
          # compile sub-component templates
          @sub_components.each do |sub_component|
            sub_component.writeConfig write_subcomponents_config
          end
        end
        @config_written = true
        @config_yaml_path = config_yaml_path
        return @config_yaml_path
      end

      def processLambdas()
        @component.highlander_dsl.lambda_functions_keys.each do |lfk|
          resolver = LambdaResolver.new(@component,
              lfk,
              @workdir,
              (not @silent_mode)
          )
          @lambda_src_paths += resolver.generateSourceArchives if @process_lambdas
          resolver.mergeComponentConfig
        end

        @lambdas_processed = true

      end

    end


    class LambdaResolver

      def initialize(component, lambda_key, workdir, confirm_code_execution = true)
        @component = component
        @lambda_config = @component.config[lambda_key]
        @component_dir = @component.component_dir
        @workdir = workdir
        @metadata = {
            'path' => {},
            'sha256' => {},
            'version' => {}
        }
        @confirm_code_execution = confirm_code_execution
      end

      def generateSourceArchives

        # Clear previous packages
        FileUtils.rmtree "#{@workdir}/output/lambdas"

        archive_paths = []

        # Cached downloads map
        cached_downloads = {}
        @lambda_config['functions'].each do |name, lambda_config|
          # create folder
          out_folder = "#{@workdir}/out/lambdas/"
          timestamp = Time.now.utc.to_i.to_s
          file_name = "#{name}.#{@component.name}.#{@component.version}.#{timestamp}.zip"
          @metadata['path'][name] = file_name
          full_destination_path = "#{out_folder}#{file_name}"
          info_path = "#{out_folder}#{file_name}.info.yaml"
          archive_paths << full_destination_path
          FileUtils.mkdir_p out_folder
          File.write(info_path, {
              'component' => @component.name,
              'function' => name,
              'packagedAt' => timestamp,
              'config' => lambda_config
          }.to_yaml)

          # clear destination if already there
          FileUtils.remove full_destination_path if File.exist? full_destination_path

          # download file if code remote archive
          puts "INFO | Lambda #{name} | Start package process"
          puts "INFO | Lambda #{name} | Destination is #{full_destination_path}"

          md5 = Digest::MD5.new
          md5.update lambda_config['code']
          hash = md5.hexdigest
          cached_location = "#{ENV['HOME']}/cfhighlander/.cache/lambdas/#{hash}"
          if cached_downloads.key? lambda_config['code']
            puts "INFO | Lambda #{name} | Using already downloaded archive #{lambda_config['code']}"
            FileUtils.copy(cached_downloads[lambda_config['code']], full_destination_path)
          elsif File.file? cached_location
            puts "INFO | Lambda #{name} | Using cache from #{cached_location}"
            FileUtils.copy(cached_location, full_destination_path)
          else
            if lambda_config['code'].include? 'http'
              puts "INFO | Lambda #{name} |  Downloading source from #{lambda_config['code']}"
              download = open(lambda_config['code'])
              IO.copy_stream(download, "#{out_folder}/src.zip")
              FileUtils.mkdir_p("#{ENV['HOME']}/cfhighlander/.cache/lambdas")
              FileUtils.copy("#{out_folder}/src.zip", cached_location)
              FileUtils.copy("#{out_folder}/src.zip", full_destination_path)
              puts "INFO | Lambda #{name} | source cached to #{cached_location}"
              cached_downloads[lambda_config['code']] = cached_location
            elsif lambda_config['code'].include? 's3://'
              parts = lambda_config['code'].split('/')
              if parts.size < 4
                STDERR.puts "ERROR | Lambda #{name} |  Lambda function source code from s3 should be in s3://bucket/path format"
                exit -8
              end
              bucket = parts[2]
              key = parts.drop(3).join('/')
              s3 = Aws::S3::Client.new({ region: s3_bucket_region(bucket) })
              puts "INFO | Lambda #{name} | Downloading source from #{lambda_config['code']}"
              s3.get_object({ bucket: bucket, key: key, response_target: cached_location })
              puts "INFO | Lambda #{name} | source cached to #{cached_location}"
              FileUtils.copy(cached_location, full_destination_path)
              cached_downloads[lambda_config['code']] = cached_location
            else
              # zip local code
              component = @component
              component_dir = component.template.template_location
              full_path = "#{component_dir}/lambdas/#{lambda_config['code']}"

              until (File.exist? full_path or component_dir.nil?)
                parent_exists = (not component.extended_component.nil?)
                component = component.extended_component if parent_exists
                component_dir = component.template.template_location if parent_exists
                full_path = "#{component_dir}/lambdas/#{lambda_config['code']}" if parent_exists
                component_dir = nil unless parent_exists
              end
              if component_dir.nil?
                STDERR.puts "ERROR | Lambda #{name} | Could not find source code directory in component #{@component.name}"
                exit -9
              end

              # lambda source can be either path to file or directory within that file
              # optionally, lambda source code
              lambda_source_dir = File.dirname(full_path)
              lambda_source_dir = full_path if Pathname.new(full_path).directory?

              # executing package command can generate files. We DO NOT want this file in source directory,
              # but rather in intermediate directory
              tmp_source_dir = "#{@workdir}/out/lambdas/tmp/#{name}"
              FileUtils.rmtree(File.dirname(tmp_source_dir)) if File.exist? tmp_source_dir
              FileUtils.mkpath(File.dirname(tmp_source_dir))
              FileUtils.copy_entry(lambda_source_dir, tmp_source_dir)
              lambda_source_dir = tmp_source_dir

              # Lambda function source code allows pre-processing (e.g. install code dependencies)
              unless lambda_config['package_cmd'].nil?
                puts "INFO | Lambda #{name} | Following code will be executed to generate lambda function #{name}:\n\n#{lambda_config['package_cmd']}\n\n"

                if @confirm_code_execution
                  exit -7 unless HighLine.agree('Proceed (y/n)?')
                end

                package_cmd = "cd #{lambda_source_dir} && #{lambda_config['package_cmd']}"
                puts 'Processing package command...'
                package_result = system(package_cmd)
                unless package_result
                  puts "ERROR | Lambda #{name} | create package - following command failed\n\n#{package_cmd}\n\n"
                  exit -4
                end
              end
              File.delete full_destination_path if File.exist? full_destination_path
              zip_generator = Cfhighlander::Util::ZipFileGenerator.new(lambda_source_dir, full_destination_path)
              zip_generator.write

            end
          end
          # add version information to avoid same package ever deployed 2 times
          Zip::File.open(full_destination_path) do |zipfile|
            zipfile.add 'hlpackage_info.txt', info_path
          end
          sha256 = Digest::SHA256.file full_destination_path
          sha256 = sha256.base64digest
          puts "INFO | Lambda #{name} | Created zip package #{full_destination_path} with digest #{sha256}"
          @metadata['sha256'][name] = sha256
          @metadata['version'][name] = timestamp
        end

        return archive_paths
      end

      def mergeComponentConfig
        @component.config['lambda_metadata'] = @metadata
      end

    end

  end
end

require_relative './highlander.dsl'
require 'fileutils'
require 'git'

LOCAL_HIGHLANDER_CACHE_LOCATION = "#{ENV['HOME']}/.highlander/components"

module Highlander

  module Factory

    class Component

      attr_accessor :component_dir,
          :config,
          :highlander_dsl_path,
          :cfndsl_path,
          :highlander_dsl,
          :cfndsl_content,
          :mappings,
          :name,
          :version,
          :distribution_bucket,
          :distribution_prefix,
          :component_files,
          :cfndsl_ext_files,
          :lambda_src_files

      def initialize(component_name, component_dir)
        @name = component_name
        @component_dir = component_dir
        @mappings = {}
        @version = nil
        @distribution_bucket = nil
        @distribution_prefix = nil
        @component_files = []
        @cfndsl_ext_files = []
        @lambda_src_files = []
      end

      def load_config()
        @config = {} if @config.nil?
        Dir["#{@component_dir}/*.config.yaml"].each do |config_file|
          puts "Loading config for #{@name}:\n\tread #{config_file} "
          partial_config = YAML.load(File.read(config_file))
          unless partial_config.nil?
            @config.extend(partial_config)
            @component_files << config_file
          end
        end
      end


      def loadDepandantExt()
        @highlander_dsl.dependson_components.each do |requirement|
          requirement.component_loaded.cfndsl_ext_files.each do |file|
            cfndsl_ext_files << file
          end
        end
      end

      # @param [Hash] config_override
      def load(config_override = nil)
        if @component_dir.start_with? 'http'
          raise StandardError, 'http(s) sources not supported yet'
        end


        @highlander_dsl_path = "#{@component_dir}/#{@name}.highlander.rb"
        @cfndsl_path = "#{@component_dir}/#{@name}.cfndsl.rb"
        candidate_config_path = "#{@component_dir}/#{@name}.config.yaml"
        candidate_mappings_path = "#{@component_dir}/*.mappings.yaml"
        candidate_dynamic_mappings_path = "#{@component_dir}/#{@name}.mappings.rb"

        @cfndsl_ext_files += Dir["#{@component_dir}/ext/cfndsl/*.rb"]
        @lambda_src_files += Dir["#{@component_dir}/lambdas/**/*"].find_all {|p| not File.directory? p}
        @component_files += @cfndsl_ext_files
        @component_files += @lambda_src_files

        @config = {} if @config.nil?

        @config.extend config_override unless config_override.nil?
        @config['component_version'] = @version unless @version.nil?
        # allow override of components
        # config_override.each do |key, value|
        #   @config[key] = value
        # end unless config_override.nil?

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
        @highlander_dsl = eval(File.read(@highlander_dsl_path), binding)

        # set version if not defined
        @highlander_dsl.ComponentVersion(@version) unless @version.nil?


        # Handle name and description defaults if they are not specified
        # in template itself
        if @highlander_dsl.name.nil?
          @highlander_dsl.name = @name
        end

        if @highlander_dsl.description.nil?
          @highlander_dsl.Description("#{@highlander_dsl.name} - #{@highlander_dsl.version}")
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
    end

    class ComponentFactory

      attr_accessor :component_sources


      def initialize(component_sources = [])
        ## First look in local $PWD/components folder
        ## Then search for cached $HOME/.highlander/components
        ## Then search in sources given by dsl
        default_locations = [
            LOCAL_HIGHLANDER_CACHE_LOCATION,
            File.expand_path('components'),
            File.expand_path('.')
        ]
        default_locations.each do |predefined_path|
          component_sources.unshift(predefined_path)
        end

        @component_sources = component_sources
      end

      def findComponentDefault(component_name, component_version)
        default_lookup_url = 'https://github.com/theonestack'
        default_lookup_url = ENV['HIGHLANDER_DEFAULT_COMPONENT_GIT_LOOKUP'] if ENV.key? 'HIGHLANDER_DEFAULT_COMPONENT_GIT_LOOKUP'

        git_url = "#{default_lookup_url}/hl-component-#{component_name}"

        if component_version.nil? or component_version.empty? or component_version == 'latest'
          branch = 'master'
        else
          branch = component_version
        end
        local_path = "#{LOCAL_HIGHLANDER_CACHE_LOCATION}/#{component_name}/#{component_version}"
        return findComponentGit(local_path, component_name, component_version, git_url, branch)

      end

      def findComponentGit(local_path, component_name, component_version, git_url, branch)
        begin
          local_path = "#{local_path}/" unless local_path.end_with? '/'
          # if this is snapshot, clean local cache
          if branch.end_with? '.snapshot'
            branch = branch.gsub('.snapshot', '')
            FileUtils.rmtree local_path if File.exist? local_path and File.directory? local_path
          end

          # if local cache exists, return from cache
          if not Dir.glob("#{local_path}*.highlander.rb").empty?
            # if cache exists, just return from cache
            component_name = Dir.glob("#{local_path}*.highlander.rb")[0].gsub(local_path, '').gsub('.highlander.rb','')
            return component_name, local_path
          end

          # shallow clone
          puts "Trying to load #{component_name}/#{component_version} from #{git_url}##{branch} ... "
          clone_opts = { depth: 1 }
          clone_opts[:branch] = branch if not (branch.nil? or branch.empty?)
          Git.clone git_url, local_path, clone_opts
          puts "\t .. cached in #{local_path}\n"
          # return from cache once it's cloned
          return findComponentGit(local_path, component_name, component_version, git_url, branch)
        rescue Exception => e
          STDERR.puts "Failed to resolve component #{component_name}@#{component_version} from #{git_url}"
          STDERR.puts e
          return nil
        end
      end

      def findComponentS3(s3_location, component_name, component_version)
        parts = s3_location.split('/')
        bucket = parts[2]
        prefix = parts[3]
        s3_key = "#{prefix}/#{component_name}/#{component_version}/#{component_name}.highlander.rb"
        s3_prefix = "#{prefix}/#{component_name}/#{component_version}/"
        local_destination = "#{LOCAL_HIGHLANDER_CACHE_LOCATION}/#{component_name}/#{component_version}"
        begin
          s3 = Aws::S3::Client.new({ region: s3_bucket_region(bucket) })
          FileUtils.mkdir_p local_destination unless Dir.exist? local_destination

          hl_content = s3.get_object({ bucket: bucket,
              key: s3_key,
              response_target: "#{local_destination}/#{component_name}.highlander.rb"
          })
          # if code execution got so far we consider file exists and download it locally
          component_files = s3.list_objects_v2({ bucket: bucket, prefix: s3_prefix })
          component_files.contents.each {|s3_object|
            file_name = s3_object.key.gsub(s3_prefix, '')
            destination_file = "#{local_destination}/#{file_name}"
            destination_dir = File.dirname(destination_file)
            print "Caching #{file_name} of #{component_name}@#{component_version} in #{destination_dir} ... "

            FileUtils.mkpath(destination_dir) unless File.exists?(destination_dir)
            s3.get_object({ bucket: bucket, key: s3_object.key, response_target: destination_file })
            print " [OK] \n"
          }
          return local_destination
        rescue => e
          # this handles both nonexisting key and bucket
          puts("#{component_name} not found in s3://#{bucket}/#{prefix}")
          STDERR.puts(e.to_s) unless e.message.include? 'does not exist'
          return nil
        end
      end

      def findComponentGitTemplate(component_name, component_version)
        if component_name.include? '#'
          parts = component_name.split('#')
          component_name = parts[0]
          component_version = parts[1]
        end

        # avoid any nres
        component_version = '' if component_version.nil?

        # if empty or latest branch is empty
        if component_version.empty? or component_version == 'latest' or component_version == 'latest.snapshot'
          branch = ''
        else
          # otherwise component version is actual branch
          branch = component_version
        end


        git_url = nil
        if component_name.start_with? 'git:'
          git_url = component_name.gsub('git:', '')
        elsif component_name.start_with? 'github:'
          git_url = "https://github.com/#{component_name.gsub('github:', '')}"
        elsif component_name.start_with? 'github.com:'
          git_url = "https://github.com/#{component_name.gsub('github.com:', '')}"
        end

        local_path = "#{LOCAL_HIGHLANDER_CACHE_LOCATION}/#{component_name}/#{component_version}"

        if not git_url.nil?
          component_name, location = findComponentGit(local_path, component_name, component_version, git_url, branch)
          if location.nil?
            raise "Could not resolve component #{component_name}@#{component_version}"
          else
            return component_name, location
          end
        end

        return nil
      end

      # Find component and given list of sources
      # @return [Highlander::Factory::Component]
      def findComponent(component_name, component_version = nil)

        component_version_s = component_version.nil? ? 'latest' : component_version
        component_version = nil if component_version == 'latest'

        if component_name.include? '@' and (not component_name.start_with? 'git')
          parts = component_name.split('@')
          component_name = parts[0]
          component_version = parts[1]
        end

        # if component specified as git location
        new_name, candidate_git = findComponentGitTemplate(component_name, component_version_s)
        return buildComponent(new_name, candidate_git) unless candidate_git.nil?

        # if not git but has .snapshot lookup in default
        if (not component_version.nil?) and component_version.end_with? '.snapshot'
          new_name, default_candidate = findComponentDefault(component_name, component_version_s)
          return buildComponent(new_name, default_candidate) unless default_candidate.nil?
        end

        # try in all of the component source
        @component_sources.each do |source|
          component_full_name = "#{component_name}@#{component_version.nil? ? 'latest' : component_version}"
          # TODO handle http(s) sources and their download to local
          if source.start_with?('http')
            raise StandardError, 'http(s) sources not supported yet'
          elsif source.start_with?('s3://')
            # s3 candidate

            s3_candidate = findComponentS3(source, component_name, component_version_s)
            if not s3_candidate.nil?
              # at this point all component files are download to local file system and consumed from there
              return buildComponent(component_name, s3_candidate)
            end

          else
            # file system candidate
            candidate = "#{source}/#{component_name}"
            candidate = "#{candidate}/#{component_version}" unless component_version.nil?
            candidate_hl_path = "#{candidate}/#{component_name}.highlander.rb"
            candidate2_hl_path = "#{source}/#{component_name}.highlander.rb"
            puts "Trying to load #{component_full_name} from #{candidate} ... "
            if File.exist?(candidate_hl_path)
              return buildComponent(component_name, candidate)
            end
            puts "Trying to load #{component_full_name} from #{source} ... "
            if File.exist?(candidate2_hl_path)
              return buildComponent(component_name, source)
            end unless component_version_s != 'latest'
          end
        end

        # try default component source on github
        component_name, default_candidate = findComponentDefault(component_name, component_version_s)
        return buildComponent(component_name, default_candidate) unless default_candidate.nil?

        raise StandardError, "highlander template #{component_name}@#{component_version_s} not located" +
            " in sources #{@component_sources}"
      end

      def buildComponent(component_name, component_dir)
        component = Component.new(component_name, component_dir)
        component.load_config
        return component
      end

    end
  end

end

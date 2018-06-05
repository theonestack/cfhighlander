LOCAL_HIGHLANDER_CACHE_LOCATION = "#{ENV['HOME']}/.cfhighlander/components"

require_relative './highlander.template.metadata'

module Highlander

  module Template

    class TemplateFinder

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

      def findTemplateDefault(template_name, component_version)
        default_lookup_url = 'https://github.com/theonestack'
        default_lookup_url = ENV['HIGHLANDER_DEFAULT_COMPONENT_GIT_LOOKUP'] if ENV.key? 'HIGHLANDER_DEFAULT_COMPONENT_GIT_LOOKUP'

        git_url = "#{default_lookup_url}/hl-component-#{template_name}"

        if component_version.nil? or component_version.empty? or component_version == 'latest'
          branch = 'master'
        else
          branch = component_version
        end
        local_path = "#{LOCAL_HIGHLANDER_CACHE_LOCATION}/#{template_name}/#{component_version}"
        return findTemplateGit(local_path, template_name, component_version, git_url, branch)

      end

      def findTemplateGit(cache_path, component_name, component_version, git_url, branch)
        begin
          cache_path = "#{cache_path}/" unless cache_path.end_with? '/'
          # if this is snapshot, clean local cache
          if branch.end_with? '.snapshot'
            branch = branch.gsub('.snapshot', '')
            FileUtils.rmtree cache_path if File.exist? cache_path and File.directory? cache_path
          end

          # if local cache exists, return from cache
          if not Dir.glob("#{cache_path}*.highlander.rb").empty?
            # if cache exists, just return from cache
            component_name = Dir.glob("#{cache_path}*.highlander.rb")[0].gsub(cache_path, '').gsub('.highlander.rb', '')
            return component_name, cache_path
          end

          # shallow clone
          puts "Trying to load #{component_name}/#{component_version} from #{git_url}##{branch} ... "
          clone_opts = { depth: 1 }
          clone_opts[:branch] = branch if not (branch.nil? or branch.empty?)
          Git.clone git_url, cache_path, clone_opts
          puts "\t .. cached in #{cache_path}\n"
          # return from cache once it's cloned
          return findTemplateGit(cache_path, component_name, component_version, git_url, branch)
        rescue Exception => e
          STDERR.puts "Failed to resolve component #{component_name}@#{component_version} from #{git_url}"
          STDERR.puts e
          return nil
        end
      end

      def findTemplateS3(s3_location, component_name, component_version)
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

      # will try and locate template based on git template location
      # if template location is not git repo, returns nil
      def tryFindTemplateGit(template_location, template_version)

        # avoid any nres
        template_version = '' if template_version.nil?

        # if empty or latest branch is empty
        if template_version.empty? or template_version == 'latest' or template_version == 'latest.snapshot'
          branch = ''
        else
          # otherwise component version is actual branch
          branch = template_version
        end


        git_url = nil
        if template_location.start_with? 'git:'
          git_url = template_location.gsub('git:', '')
        elsif template_location.start_with? 'github:'
          git_url = "https://github.com/#{template_location.gsub('github:', '')}"
        elsif template_location.start_with? 'github.com:'
          git_url = "https://github.com/#{template_location.gsub('github.com:', '')}"
        end


        if not git_url.nil?
          local_path = "#{LOCAL_HIGHLANDER_CACHE_LOCATION}/#{template_location.gsub(':','_').gsub(/\/+/,'/')}/#{template_version}"
          template_name, location = findTemplateGit(local_path, template_location, template_version, git_url, branch)
          if location.nil?
            raise "Could not resolve component #{template_location}@#{template_version}"
          else
            return template_name, template_version, location
          end
        end

        return nil
      end

      def findTemplate(template_name, template_version)
        template_version_s = template_version.nil? ? 'latest' : template_version
        template_version = nil if template_version == 'latest'
        is_git_template = template_name.start_with? 'git'

        if template_name.include? '@' and (not template_name.start_with? 'git')
          parts = template_name.split('@')
          template_name = parts[0]
          template_version = parts[1]
          template_version_s = template_version
        end

        if template_name.include? '#' and (is_git_template)
          parts = template_name.split('#')
          template_name = parts[0]
          template_version = parts[1]
          template_version_s = template_version
        end

        # if component specified as git location
        if is_git_template
          new_template_name, new_version, candidate_git = tryFindTemplateGit(template_name, template_version_s)
          return TemplateMetadata.new(
              template_name: new_template_name,
              template_version: new_version,
              template_location: candidate_git) unless candidate_git.nil?
        end

        # if not git but has .snapshot lookup in default, it is allowed to reference default
        # snapshots
        if (not template_version.nil?) and template_version.end_with? '.snapshot'
          new_template_name, snapshot_candidate_location = findTemplateDefault(template_name, template_version_s)
          return TemplateMetadata.new(
              template_name: new_template_name,
              template_version: template_version,
              template_location: snapshot_candidate_location) unless snapshot_candidate_location.nil?
        end

        # try in all of the component sources
        @component_sources.each do |source|
          template_full_name = "#{template_name}@#{template_version.nil? ? 'latest' : template_version}"
          # TODO handle http(s) sources and their download to local
          if source.start_with?('http')
            raise StandardError, 'http(s) sources not supported yet'
          elsif source.start_with?('s3://')
            # s3 candidate

            s3_candidate = findTemplateS3(source, template_name, template_version_s)
            # at this point all component files are download to local file system and consumed from there
            return TemplateMetadata.new(
                template_name: template_name,
                template_version: template_version,
                template_location: s3_candidate) unless s3_candidate.nil?

          else
            # file system candidate
            candidate = "#{source}/#{template_name}"
            candidate = "#{candidate}/#{template_version}" unless template_version.nil?
            candidate_hl_path = "#{candidate}/#{template_name}.highlander.rb"
            candidate2_hl_path = "#{source}/#{template_name}.highlander.rb"
            puts "TRACE: Trying to load #{template_full_name} from #{candidate} ... "
            if File.exist?(candidate_hl_path)
              return TemplateMetadata.new(
                  template_name: template_name,
                  template_version: template_version,
                  template_location: candidate
              )
            end
            puts "TRACE: Trying to load #{template_full_name} from #{source} ... "
            # if component version is latest it is allowed to search in path
            # with no version component in it
            if File.exist?(candidate2_hl_path)
              return TemplateMetadata.new(
                  template_name: template_name,
                  template_version: 'latest',
                  template_location: source
              )
            end unless template_version_s != 'latest'
          end
        end

        # try default component source on github
        template_name, default_candidate = findTemplateDefault(template_name, template_version_s)
        return TemplateMetadata.new(
            template_name: template_name,
            template_version: template_version_s,
            template_location: default_candidate
        ) unless default_candidate.nil?

        return nil
      end

    end

  end

end
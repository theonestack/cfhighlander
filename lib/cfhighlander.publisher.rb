require_relative './cfhighlander.compiler'
require 'aws-sdk-s3'
require 'uri'
module Cfhighlander

  module Publisher

    class ComponentPublisher

      def initialize(component, cleanup, template_format)
        @component = component
        @cleanup_destination = cleanup
        @template_format = template_format
      end

      def publishComponent
        bucket = @component.highlander_dsl.distribution_bucket
        prefix = @component.highlander_dsl.distribution_prefix
        version = @component.highlander_dsl.version

        s3_create_bucket_if_not_exists(bucket)

        s3 = Aws::S3::Client.new({ region: s3_bucket_region(bucket) })

        existing_objects = s3.list_objects_v2({bucket: bucket, prefix: "#{prefix}/#{@component.name}/#{version}"})
        existing_objects.contents.each do |s3obj|
          print "Deleting previously published #{s3obj.key} ..."
          s3.delete_object(bucket: bucket, key: s3obj.key)
          print " [OK] \n"
        end if @cleanup_destination

        @component.component_files.each do |file_path|
          File.open(file_path, 'rb') do |file|
            file_path = file_path.gsub(@component.component_dir, '')[1..-1]
            s3_key = "#{prefix}/#{@component.name}/#{version}/#{file_path}"
            print "Publish component file #{file_path} to s3://#{bucket}/#{s3_key} ... "
            s3.put_object(bucket: bucket, key: s3_key, body: file)
            print " [OK] \n"
          end
        end

      end

      def getTemplateUrl
        template_url = "https://#{@component.highlander_dsl.distribution_bucket}.s3.amazonaws.com/"
        template_url += @component.highlander_dsl.distribution_prefix + "/"
        template_url += @component.highlander_dsl.version
        template_url += "/#{@component.name}.compiled.#{@template_format}"
        return template_url
      end

      def getLaunchStackUrl
        template_url = getTemplateUrl
        region = s3_bucket_region(@component.highlander_dsl.distribution_bucket)
        return "https://console.aws.amazon.com/cloudformation/home?region=#{region}#/stacks/create/review?filter=active&templateURL=" +
            "#{URI::encode(template_url)}&stackName=#{@component.name}"
      end

      def publishFiles(file_list)
        bucket = @component.highlander_dsl.distribution_bucket
        prefix = @component.highlander_dsl.distribution_prefix
        version = @component.highlander_dsl.version

        s3_create_bucket_if_not_exists(bucket)
        s3 = Aws::S3::Client.new({ region: s3_bucket_region(bucket) })

        s3.list_objects_v2(bucket: bucket, prefix: "#{prefix}/#{version}").contents.each do |s3obj|
          print "\nDeleting previously published #{s3obj.key} ..."
          s3.delete_object(bucket: bucket, key: s3obj.key)
          print ' [OK]'
        end if @cleanup_destination

        file_list.each do |file|
          file_name = File.basename file
          s3_key = "#{prefix}/#{version}/#{file_name}"
          print "\nPublishing #{file} to s3://#{bucket}/#{s3_key} ..."
          s3.put_object({
              body: File.read(file),
              bucket: bucket,
              key: s3_key
          })
          print ' [OK] '
        end
        print "\n"

      end

    end

  end
end

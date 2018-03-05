require 'aws-sdk-cloudformation'
require 'aws-sdk-s3'
require 'digest/md5'

module Highlander

  module Cloudformation


    class Validator

      def initialize(component)
        @component = component
      end

      def validate(destination_template_locations, format)
        destination_template_locations.each do |file|

          # validate cloudformation template
          file_size_bytes = File.size(file)

          #:template_body (String) — Structure containing the template body with a minimum length of
          # 1 byte and a maximum length of 51,200 bytes. For more information,
          # go to Template Anatomy in the AWS CloudFormation User Guide.

          if file_size_bytes > 51200
            validate_s3 (file)
          else
            validate_local(file)
          end

        end

      end

      def validate_local(path)
        puts "Validate template #{path} locally"
        template = File.read path
        awscfn = Aws::CloudFormation::Client.new
        response = awscfn.validate_template({
            template_body: template
        })
        puts 'SUCCESS'
      end

      def validate_s3(path)
        template = File.read path
        bucket = @component.highlander_dsl.distribution_bucket
        prefix = @component.highlander_dsl.distribution_prefix
        md5 = Digest::MD5.hexdigest template
        s3_key = "#{prefix}/highlander/validate/#{md5}"
        s3 = Aws::S3::Client.new({region: s3_bucket_region(bucket)})

        puts "Upload #{path} to s3://#{bucket}/#{s3_key}"
        s3.put_object({ body: template, bucket: bucket, key: s3_key })
        awscfn = Aws::CloudFormation::Client.new

        puts "Validate s3://#{bucket}/#{s3_key}"
        response = awscfn.validate_template({
            template_url: "https://#{bucket}.s3.amazonaws.com/#{s3_key}"
        })
        puts "Delete s3://#{bucket}/#{s3_key}"
        s3.delete_object({ bucket: bucket, key: s3_key })
        puts 'SUCCESS'

      end

    end

  end

end
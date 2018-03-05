require 'aws-sdk-s3'

def aws_credentials
  # TODO implement credentials e.g. for environment create/update/delete
end

def s3_bucket_region(bucket)
  s3 = Aws::S3::Client.new
  location = s3.get_bucket_location({ bucket: bucket }).location_constraint
  location = 'us-east-1' if location == ''
  location = 'eu-west-1' if location == 'EU'
  location
end
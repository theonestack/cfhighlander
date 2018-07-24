require 'aws-sdk-s3'
require 'aws-sdk-ec2'

def aws_credentials
  # TODO implement credentials e.g. for environment create/update/delete
end

def aws_account_id()
  sts = Aws::STS::Client.new
  account = sts.get_caller_identity().account
  return account
end

def aws_current_region()
  region = Aws::EC2::Client.new.describe_availability_zones().availability_zones[0].region_name
  return region
end

def s3_bucket_region(bucket)
  s3 = Aws::S3::Client.new
  location = s3.get_bucket_location({ bucket: bucket }).location_constraint
  location = 'us-east-1' if location == ''
  location = 'eu-west-1' if location == 'EU'
  location
end

def s3_create_bucket_if_not_exists(bucket)
  s3 = Aws::S3::Client.new
  begin
    s3.head_bucket(bucket: bucket)
  rescue
    puts(" INFO: Creating bucket #{bucket} ")
    s3.create_bucket(bucket: bucket)
  end
end
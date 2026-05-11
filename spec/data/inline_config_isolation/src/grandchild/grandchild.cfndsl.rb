CloudFormation do

  S3_Bucket(:ConfigBucket) do
    BucketName bucket_prefix
  end

end

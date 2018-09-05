CloudFormation do

  S3_Bucket(:Bucket) do

  end

  S3_Bucket(:c1NamedBucket) do
    BucketName FnFindInMap('bucketnames', 'default', 'name')
  end

  Output(:c1OutParam) do
    Value(Ref(:Bucket))
  end

end
CloudFormation do


  S3_Bucket(:Bucket) do

    BucketName FnJoin('', [Ref('c1OutParam'), '-c2'])

  end

end
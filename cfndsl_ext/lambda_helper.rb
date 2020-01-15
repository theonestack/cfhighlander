require_relative './iam_helper'

def render_lambda_functions(cfndsl, lambdas, lambda_metadata, distribution)

  custom_policies = (lambdas.key? 'custom_policies') ? lambdas['custom_policies'] : {}
  lambdas['roles'].each do |lambda_role, role_config|
    cfndsl.IAM_Role("LambdaRole#{lambda_role}") do
      AssumeRolePolicyDocument service_role_assume_policy('lambda')
      Path '/'
      unless role_config['policies_inline'].nil?
        Policies(
            IAMPolicies.new(custom_policies).create_policies(role_config['policies_inline'])
        )
      end

      unless role_config['policies_managed'].nil?
        ManagedPolicyArns(role_config['policies_managed'])
      end
    end
  end

  lambdas['functions'].each do |key, lambda_config|
    name = key
    environment = lambda_config['environment'] || {}

    # Create Lambda function
    function_name = name
    Lambda_Function(function_name) do
      Code({
          S3Bucket: distribution['bucket'],
          S3Key: "#{distribution['prefix']}/#{distribution['version']}/#{lambda_metadata['path'][key]}"
      })

      Environment(Variables: Hash[environment.collect { |k, v| [k, v] }])

      Handler(lambda_config['handler'] || 'index.handler')
      MemorySize(lambda_config['memory'] || 128)
      Role(FnGetAtt("LambdaRole#{lambda_config['role']}", 'Arn'))
      Runtime(lambda_config['runtime'])
      Timeout(lambda_config['timeout'] || 10)
      if !lambda_config['vpc'].nil? && lambda_config['vpc']
        # TODO implement VPC config
      end

      if !lambda_config['named'].nil? && lambda_config['named']
        if lambda_config['function_name'].nil?
          FunctionName(name)
        else
          FunctionName(lambda_config['function_name'])
        end
      end
    end
    
    puts "\n\nI AM HERE\n\n"
    
    Lambda_Version("#{name}Version#{lambda_metadata['version'][key]}") do
      DeletionPolicy('Retain')
      FunctionName(Ref(name))
      CodeSha256(lambda_metadata['sha256'][key])
    end

    # Scheduled triggering of lambda function
    if lambda_config.key?('schedules')
      lambda_config['schedules'].each_with_index do |schedule, index|
        Events_Rule("Lambda#{name}Schedule#{index}") do
          if schedule['cronExpression'].include?('rate')
          then
            expression = schedule['cronExpression']
          else
            expression = "cron(#{schedule['cronExpression']})"
          end
          ScheduleExpression(FnSub(expression))
          Name schedule['name'] if schedule.has_key?('name')
          State('ENABLED')
          target = {
              'Arn' => FnGetAtt(name, 'Arn'), 'Id' => "lambda#{name}",
          }
          target['Input'] = schedule['payload'] if schedule.key?('payload')
          Targets([target])
        end
        Lambda_Permission("Lambda#{name}Schedule#{index}Permission") do
          FunctionName(Ref(name))
          Action('lambda:InvokeFunction')
          Principal('events.amazonaws.com')
          SourceArn FnGetAtt("Lambda#{name}Schedule#{index}", 'Arn')
        end
      end
    end

    # Generate lambda function Policy
    unless lambda_config['allowed_sources'].nil?
      i = 1
      lambda_config['allowed_sources'].each do |source|
        Lambda_Permission("#{name}Permissions#{i}") do
          FunctionName(Ref(name))
          Action('lambda:InvokeFunction')
          Principal(source['principal'])
          if source.key? 'source_arn'
            SourceArn source['source_arn']
          end
        end
        i += 1
      end
    end

    if lambda_config.has_key?('log_retention')
      Logs_LogGroup("#{name}LogGroup") do
        LogGroupName "/aws/lambda/#{name}"
        RetentionInDays lambda_config['log_retention'].to_i
      end
    end
    
  end
end

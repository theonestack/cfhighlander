CfhighlanderTemplate do

  # explicit configuration for vpc component
  vpc_config = { 'maximum_availability_zones' => 5 }

  hosted_zone = FnJoin('.',[Ref('AWS::Region'), Ref('AWS::AccountId'), 'cfhighlander.info'])
  vpc_template = 'github:toshke/hl-component-vpc#inline_poc'
  bastion_template = 'github:toshke/hl-component-bastion#inline_poc'
  ecs_template = 'github:toshke/hl-component-ecs#inline_poc'

  # use this to swtich substacks / all in one stack mode

  Component template: bastion_template,
      name:'bastion',
      render: Inline do
    parameter name: 'KeyName', value: ''
    parameter name: 'InstanceType', value: 't2.micro'
    parameter name: 'DnsDomain', value: hosted_zone
  end

  # declare vpc component, and pass some parameters
  # to it
  Component template: vpc_template,
      name: 'vpc',
      render: Inline,
      config: vpc_config do
    parameter name: 'StackMask', value: '16'
    parameter name: 'DnsDomain', value: hosted_zone
  end

  # Compiled cloudformation template will
  # pass Compute subnets from VPC into ECS Cluster
  Component template: ecs_template,
      name: 'ecs',
      render: Inline do
    parameter name: 'InstanceType', value: 't2.large'
    parameter name: 'KeyName', value: ''
    parameter name: 'SecurityGroupLoadBalancer', value: cfout('vpc','SecurityGroupBackplane')
    parameter name: 'DnsDomain', value: hosted_zone
  end

end

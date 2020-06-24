[![Build Status](https://travis-ci.org/theonestack/cfhighlander.svg?branch=develop)](https://travis-ci.org/theonestack/cfhighlander) [![Join the chat at https://gitter.im/theonestack/cfhighlander](https://badges.gitter.im/theonestack/cfhighlander.svg)](https://gitter.im/theonestack/cfhighlander?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

# Intro

Cfhighlander is a feature rich tool and DSL for infrastructure
coders working with CloudFormation templates.

It was designed to

-  Abstract AWS resources or sets of resources as
   **components** by describing them using Cfhighlander
   DSL and [cfndsl](https://github.com/cfndsl/cfndsl).

- Produce, validate and publish CloudFormation templates
  from those components

- Enable infrastructure coders to use concepts of **inheritance**
  and **composition** when designing components. In other words
  allowing components to be *extended*, and allowing components
  to be built from other components.

- Allow for easy **discovery** and consumption of components from
  different sources (git repository, file system, S3 buckets)

 - Allow component developers and consumers to take
   more **descriptive** approach using DSL, compared to
   instructional approach.

# Installation

```
gem install cfhighlander
```

# Example

Passing output value from one substack to another substack within root stack
has to be done manually - either if you build JSON/YAML templates by hand,
or if using `Cfndsl`. With cfhighlander, this code is automatically generated for you

```ruby
## place contents below in file name application.cfhighlander.rb
CfhighlanderTemplate do

  # explicit configuration for vpc component
  vpc_config = { 'maximum_availability_zones' => 2 }

  # declare vpc component, and pass some parameters
  # to it
  Component name: 'vpc',
        template: 'vpc@master.snapshot',
        config: vpc_config do
    parameter name: 'Az0', value: FnSelect(0,FnGetAZs())
    parameter name: 'Az1', value: FnSelect(1,FnGetAZs())
    parameter name: 'DnsDomain', value: 'example.com'
    parameter name: 'StackMask', value: '16'
  end

  # Compiled cloudformation template will
  # pass Compute subnets from VPC into ECS Cluster
  Component name: 'ecs', template:'ecs@master.snapshot' do
    parameter name: 'DnsDomain', value: 'example.com'
  end

  # feed mapping maparameters to components
  addMapping('EnvironmentType',{
    'development' => {
      'MaxNatGateways'=>'1',
      'EcsAsgMin' => 1,
      'EcsAsgMax' => 1,
      'KeyName' => 'default',
      'InstanceType' => 't2.large',
      'SingleNatGateway' => true
    }
  })
end

```

... compile the template with ...

```shell
cfcompile application
```

... and check how the subnets are being passed around ..

```shell
$ cat out/yaml/application.compiled.yaml | grep  -A3 SubnetCompute0
          SubnetCompute0:
            Fn::GetAtt:
            - vpc
            - Outputs.SubnetCompute0
          SubnetCompute1:
            Fn::GetAtt:
            - vpc

```



# Component library

As part of [theonestack org](https://github.com/theonestack/), there are many publicly available components.

- [vpc](https://github.com/theonestack/hl-component-vpc) - Has separation of public
   and private subnets, configurable number of NAT Gateways (per AZ or single for all
  subnets), lays out default subnets (private - compute, storage and cache, public), as well as their route tables

- [ecs](https://github.com/theonestack/hl-component-ecs) - ECS Cluster deployed in VPC Compute Subnets
- [bastion](https://github.com/theonestack/hl-component-bastion) - Deployed into VPC Public subnets
  Subnets, with configuration for whitelisting IP addresses to access port 22
- [ecs-service](https://github.com/theonestack/hl-component-ecs-service) - Deploy containerised apps running on ECS Clusters
- [loadbalancer](https://github.com/theonestack/hl-component-loadbalancer) - ALB, ELB or NLB
- [sns](https://github.com/theonestack/hl-component-sns) - SNS Topics, with implemented
Lambda function to post Slack messages
- [efs](https://github.com/theonestack/hl-component-efs) - Elastic File System, can be
used in conjuction with ECS Cluster
- [rds-mysql](https://github.com/theonestack/hl-component-rds-mysql) - RDS Component for MySQL engine
- [rds-postgres](https://github.com/theonestack/hl-component-rds-postgres) - RDS Component for Postgres engine
- [aurora-mysql](https://github.com/theonestack/hl-component-aurora-mysql) - Aurora component for MySQL engine
- [aurora-postgres](https://github.com/theonestack/hl-component-aurora-postgres) - Aurora component for Postgres engine
- [elasticache-memcache](https://github.com/theonestack/hl-component-elasticache-memcache) - Aws Elasticache - Memcache engine
- [elasticache-memcache](https://github.com/theonestack/hl-component-elasticache-redis) - Aws Elasticache - Redis engine
- [asg](https://github.com/theonestack/hl-component-asg) - AutoScalingGroup component
- [cognito](https://github.com/theonestack/hl-component-cognito) - Cognito user pools, custom domain names and clients

You can easily test any of these. Automatic component resolver will default
to 'https://github.com/theonestack/hl-component-$name' location if component
is not found in local sources.

From shell, command below will generate cloudformation for given component in `out` folder
```shell
cfcompile component_name
```

Or from outer cfhighlander template, just pull component using `Component` DSL statement

```ruby
CfhighlanderTemplate do
  Component component_name
end
```


# How it works ?

Highlander DSL produces CloudFormation templates in 4 phases

- Processing referenced component's configuration and resolving configuration exports
- Wiring parameters from components to their inner components
- Producing [CfnDsl](https://github.com/cfndsl/cfndsl) templates for all components and subcomponents as intermediary
  step
- Producing resulting CloudFormation templates using configuration and templates generated in two previous phases.

Each phase (aside from parameter wiring) above is executable as stand-alone through CLI, making development of Highlander templates easier by enabling
debugging of produced configuration and cfndsl templates.


## Highlander components

Highlander component is located on local file system or S3 location with following
files defining them

- Highlander DSL file (`$componentname.highlander.rb`)
- *(Optional)* Configuration files (`*.config.yaml`)
- *(Optional)* CfnDSL file (`componentname.cfnds.rb`)
- *(Optional)* Mappings YAML files `*.mappings.yaml` -
this file defines map used within component itself
- *(Optional)* Mappings extension file `componentname.mappings.rb` - see more under Mappings section
- *(Optional)* Ruby extensions consumed by cfndsl templates - placed in `ext/cfndsl/*.rb` - see more under
 Extensions section

## Terminology

**Component** is basic building block of highlander systems. Components have following roles

- Define (include) other components
- Provide values for their inner component parameters
- Define how their configuration affects other components
- Define sources of their inner components
- Define publish location for both component source code and compiled CloudFormation templates
- Define cfndsl template used for building CloudFormation resources


**Outer component** is component that defines other component via cfhighlander dsl `Component` statement. Defined component
is called **inner component**. Components defined under same outer component are **sibling components**

## Usage

You can either pull highlander classes in your own code, or more commonly use it via command line interface (cli).
For both ways, highlander is distributed as ruby gem


```bash
$ gem install cfhighlander
$ cfhighlander help
cfhighlander commands:
  cfhighlander cfcompile component[@version] -f, --format=FORMAT   # Compile Highlander component to CloudFormation templates
  cfhighlander cfpublish component[@version] -f, --format=FORMAT   # Publish CloudFormation template for component, and it' referenced subcomponents
  cfhighlander configcompile component[@version]                   # Compile Highlander components configuration
  cfhighlander dslcompile component[@version] -f, --format=FORMAT  # Compile Highlander component configuration and create cfndsl templates
  cfhighlander help [COMMAND]                                      # Describe available commands or one specific command
  cfhighlander publish component[@version] [-v published_version]  # Publish CloudFormation template for component, and it' referenced subcomponents

```
### Working directory

All templates and configuration generated are placed in `$WORKDIR/out` directory. Optionally, you can alter working directory
via `CFHIGHLANDER_WORKDIR` environment variable.

### Commands

To get full list of options for any of cli commands use `highlander help command_name` syntax

```bash
$ cfhighlander help publish
Usage:
  cfhighlander publish component[@version] [-v published_version]

Options:
      [--dstbucket=DSTBUCKET]  # Distribution S3 bucket
      [--dstprefix=DSTPREFIX]  # Distribution S3 prefix
  -v, [--version=VERSION]      # Distribution component version, defaults to latest

Publish CloudFormation template for component,
            and it's referenced subcomponents

```

#### Silent mode

Cfhighlander DSL processor has built-in support for packaging and deploying AWS Lambda functions. Some of these lambda
functions may require shell command to be executed (e.g. pulling library dependencies) prior their packaging in ZIP archive format.
Such commands are potential security risk, as they allow execution of arbitrary code, so for this reason user agreement is required
e.g:

```bash
Packaging AWS Lambda function logMessage...
Following code will be executed to generate lambda function logMessage:

pip install requests -t lib

Proceed (y/n)?
```

In order to avoid user prompt pass `-q` or `--quiet` switch to CLI for commands that require Lambda packaging
(`dslcompile`, `cfcompile`, `cfpublish`)


#### cfcompile

*cfcompile* will produce cloudformation templates in specified format (defaults to yaml). You can optionally validate
produced template via `--validate` switch. Resulting templates will be placed in `$WORKDIR/out/$format`


#### cfpublish

*cfcompile* will produce cloudformation templates in specified format (defaults to yaml), and publish them to S3 location.
You can optionally validate produced template via `--validate` switch. Resulting templates will be placed in `$WORKDIR/out/$format`, and
published to `s3://$distributionBucket/$distributionPrefix/$distributionVersion`. All S3 path components can be controlled
via CLI (`--dstbucket`, `--dstprefix`, `-v`). Default distribution bucket and prefix can be also be controlled via DSL using
`DistributionBucket`, `DistributionBucket`, `DistributionPrefix` or `ComponentDistribution` statements. Check DSL specification
for more details on this statements. Version defaults to `latest` if not explicitly given using `-v` switch

If no distribution options is given using mentioned CLI options or DSL statements,
bucket will be automatically created for you. Bucket name defaults to
`$ACCOUNT.$REGION.cfhighlander.templates`, with `/published-templates`
prefix.

*cfpublish* command will give you quick launch CloudFirmation stack URL to assist
you in creating your stack:

```bash
$ cfpublish vpc@1.2.0
...
...
...

Use following url to launch CloudFormation stack

https://console.aws.amazon.com/cloudformation/home#/stacks/create/review?filter=active&templateURL=https://123456789012.ap-southeast-2.cfhighlander.templates.s3.amazonaws.com/published-templates/vpc/1.2.0/vpc.compiled.yaml&stackName=vpc

```


#### configcompile

*configcompile* produces configuration yamls that are passed as external configuration when processing
cfndsl templates. Check component configuration section for more details.

#### dslcompile

*dslcompile* will produce intermediary cfndsl templates. This is useful for debugging cfhighlander components

#### publish

*publish* command publishes cfhighlander components source code to s3 location (compared to *cfpublish* which is publishing
compiled cloudformation templates). Same CLI / DSL options apply as for *cfpublish* command. Version defaults to `latest`


## Component configuration

### Default configuration values

Within each template, following configuration values are available by default in both cfhl and cfndsl templates

- `template_name` - Name of the cfhighlander template
- `template_verison` - Version of the cfhighlander component template used
- `template_dir` - Disk location of the cfhighlander template. Can be used to reference local files within component, and does work with component inheritance

### Defining and overriding configuration

There are 4 levels of component configuration

- Component local config file `component.config.yaml` (lowest priority)
- Outer component configuration file, under `components` key, like


```yaml

# some configuration values

components:
  vpc:
    config:
      maximum_availibility_zones: 2

```
This configuration level overrides component's own config file.
Alternatively, to keep things less nested in configuration hierarchy, creating config file `vpc.config.yaml`
for component named `vpc` works just as well:

```yaml

# contents of vpc.config.yaml in outer component, defining vpc component

# line below prevents component configuration file being merged with outer component configuration
subcomponent_config_file:  

# there is no need for components/vpc/config structure, it is implied by file name
maximum_availibility_zones: 3


```


- Outer component explicit configuration. You can pass `config` named parameter to `Component` statement, such as

```ruby
CfhighlanderTemplate do

# ...
# some dsl code
# ...

   Component template:'vpc@latest',config: {'maximum_availibility_zones' => 2}

end
```
Configuration done this way will override any outer component config coming from configuration file


- Exported configuration from other components. If any component exports configuration using `config_export` configuration
  key, it may alter configuration of other components. Globally exported configuration is defined under `global`, while
  component-oriented configuration is exported under `component` key. E.g. following configuration will export global
  configuration defining name of ecs cluster, and targeted to vpc component configuration, defining subnets

```yaml
ecs_cluster_name: ApplicationCluster

subnets:
  ecs_cluster:
    name: ECSCluster
    type: private
    allocation: 20

config_export:  
  global:
    - ecs_cluster_name

  component:
    vpc:
      - subnets
```

Configuration is exported **AFTER** component local config, and outer component configurations are loaded.
Outer component configuration takes priority over exported configuration, as this configuration is loaded once
more once component exported conifgurations are applied to appropriate components.  

To change *NAME* of targeted component (e.g. from `vpc` to `vpc1`), you can use `export_config` named parameter on `Component` dsl method
In addition to configuration in inner component above, wiring of targeted component for export would be done like

```ruby
Component name: 'vpc1', template: 'vpc'
Component name: 'ecs_cluster', template: 'ecs_cluster@latest', export_config: {'vpc' => 'vpc1'}
```
## CloudFormation mappings

[CloudFormation Mappings](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/mappings-section-structure.html)
section matches a key to a corresponding set of named values. Highlander allows you to define this mappings in two ways

1. By using static maps defined through YAML files. Place `*.mappings.yaml` file alongside with highlander
template to define mappings this way. Mappings defined in a static way are automatically rendered withing CloudFormation
template E.g.

```yaml
# Master component mappings
# envtype.mappings.yaml
EnvironmentType:
  dev:
    InstanceType: t2.medium
  prod:
    InstanceType: m4.medium
```

2. By defining mappings dynamically through Ruby code. Alongside with mappings, you can define default map name, and default
map key to be used when looking up value within this map. This mappings are usually rendered in outer component when inner
components pulls mapping value as parameter via `MappingParam` statement. Optionally, this mappings can be rendered within
component that defines them using `DynamicMappings` DSL statement.

## Extensions

### Cfndsl extensions

In order to make template more DRY, template developer may reuse ruby functions. It is possible to place
such functions in separate files. Any ruby files placed within `ext/cfndsl` directory will get automatically
included via Ruby `require` function in compiled Cfndsl template.

## Component DSL

### Inner components or subcomponents

Inner components or subcomponents are defined via `Component` DSL statement

```ruby
CfhighlanderTemplate do

  # Example1 : Include component by template name only
  Component 'vpc'

  # Example2 : Include component by template name, version and give it a name
  Component template: 'ecs@master.snapshot'

end

```

**Conditional components** - If you want to add top level paramater as feature toggle for one of the inner
components, just mark it as conditional, using `conditional:` named parameter. In addition to this, default
value for feature toggle can be supplied using `enabled:` named parameter. Autogenerated parameter will be named
`Enable$COMPONENTNAME`, defaulting to `[true,false]` as set of allowed values. Autogenerated condition will 
be named same as parameter, and checking if the parameter value equlas `true` 


```ruby

# Include vpc and 2 ecs clusters with feature flags
CfhighlanderTemplate do

  # vpc component
  Component 'vpc'

  # Ecs Cluster 1 has feature toggle, enabled by default
  Component name: 'ecs1', template: 'ecs', conditional: true

  # Ecs Cluster 2 has feature toggle, and is explicitly disabled by default
  Component name: 'ec2', template: 'ecs', conditional: true, enabled: false

end

```

**Override default behaviour** - If you have more than 1 stack you want to control with a single parameter, or you want to change
parameter name, you can supply the `condition:` option with a string value on each component you want to control with the condition.
Autogenerated condition can be overriden as well, by defining your own condition with the same name on the highlander 
template, as in example below. 


```ruby
CfhighlanderTemplate do
  
  # [Optional - Define your own condition, instead of default true/false one]
  Condition 'EnableDevelopmentResources', FnEquals(Ref(:EnvironmentName),'dev')

  # Components always required
  Component 'vpc'
  Component name: 'ecs', template: 'ecs'
  
  # Components only required in development environments with common condition name
  Component name: 'linux-bastion', template: 'bastion', conditional: true, condition: 'EnableDevelopmentResources', enabled: false
  Component name: 'windows-bastion', template: 'bastion', conditional: true, condition: 'EnableDevelopmentResources', enabled: false


end
```

**Nested Stack Timeout** - If you ant set a timeout on your nested cloudformation stack you can set this with the `timeout: int` option on the component.

```ruby
CfhighlanderTemplate do
  
  # sets a timeout for 10 minutes on the nested VPC stack, if the stack is not created or updated within 10 minutes the stack rolls back.
  Component name: 'vpc', template: 'vpc-v2', timeout: 10
  
end
```

**Convert config value to parameter** - In case of inner component having configuration value
you wish to expose as runtime parameter, it is possible to do so with limitation that configuration
value is only used in *resource declarations*, as property value. If configuration value is being used
to control the dsl flow, taking part in any control structure statements, and such gets evaluated at
**compile** time, there is no sense of making CloudFormation stack parameter out of it.

Below example demonstrate use of `ConfigParameter` statement on simple S3 Bucket component -
it assumes that `s3bucket` template exists with `bucketName` as configuration value for it.


```ruby
CfhighlanderTemplate do

    Component template: 's3bucket', name: 'parameterizedBucket' do
        ConfigParameter config_key: 'bucketName', parameter_name: '', type: 'String'
    end

end


```

### Parameters

Parameters block is used to define CloudFormation template parameters, and metadata on how they
are wired with outer or sibling components.

```ruby
CfhighlanderTemplate do
  Parameters do
    ##
    ##  parameter definitions here
    ##
  end
end
```

Parameter block supports following parameters

#### ComponentParam

`ComponentParam` - Component parameter exposes parameter to be wired from outer component. Cfhighlander's
autowiring mechanism will try and find any stack outputs from other components defined by outer components with name
matching. If there is no explicit value provided, or autowired from outputs, parameter will be propagated to outer component.

Propagated parameter will be prefixed with component name **if it is not defined as global parameter**. Otherwise,
parameter name is kept in full.

Example below demonstrates 3 different ways of providing parameter values from outer to inner component.

- Provide value explicitly
- Provide value explicitly as output of another component     
- Autowire value from output of another component with the same name
- Propagate parameter to outer component

```ruby

# Inner Component 1
CfhighlanderTemplate do
  Name 's3'
  Parameters do
     ComponentParam 'BucketName','highlander.example.com.au'
     ComponentParam 'BucketName2',''
     ComponentParam 'BucketName3',''
     ComponentParam 'BucketName4','', isGlobal: false # default value is false
     ComponentParam 'BucketName5','', isGlobal: true
  end

end

```

```ruby
# Inner Component 2
CfhighlanderTemplate do
  Name 'nameproducer'

  # has output 'bucket name defined in cfdnsl
end


# -- contents of cfndsl
CloudFormation do

    Condition 'AlwaysFalse', FnEquals('true','false')
    S3_Bucket :resourcetovalidateproperly do
      Condition 'AlwaysFalse'
    end

    Output('BucketName') do
        Value('highlanderbucketautowired.example.com.au')
    end
end


```

```ruby
# Outer component
CfhighlanderTemplate do
    Component 'nameproducer'
    Component 's3' do
      parameter name: 'BucketName2', value: 'nameproducer.BucketName'
      parameter name: 'BucketName3', value: 'mybucket.example.cfhighlander.org'
    end
end

```


Example above translates to following wiring of parameters in cfndsl template
```ruby
CloudFormation do

     # Parameter that was propagated
    Parameter('s3BucketName4') do
      Type 'String'
      Default ''
      NoEcho false
    end

    Parameter('BucketName5') do
      Type 'String'
      Default ''
      NoEcho false
    end

   CloudFormation_Stack('s3') do
       TemplateURL './s3.compiled.yaml'
       Parameters ({

          # Paramater that was auto-wired
           'BucketName' => {"Fn::GetAtt":["nameproducer","Outputs.BucketName"]},

          # Parameter that was explicitly wired as output param from another component
           'BucketName2' => {"Fn::GetAtt":["nameproducer","Outputs.BucketName"]},

          # Paramater that was explicitly provided
           'BucketName3' => 'mybucket.example.cfhighlander.org',

          # Reference to parameter that was propagated. isGlobal: false when defining
          # parameter, so parameter name is prefixed with component name
           'BucketName4' => {"Ref":"s3BucketName4"},

          # Reference to parameter that was propagated. isGlobal: true when defining
          # parameter, so parameter name is not prefixed, but rather propagated as-is
          'BucketName5' => {"Ref":"BucketName5"},

       })
   end
end

```

#### Overriding Parameter Properties

Components have pre defined parameters with properties such as Type, AllowedValues, NoEcho etc.
These properties can be overridden on the parent component.

```ruby
CfhighlanderTemplate do
    
    Paramater do
      ComponentParam 'EnvironmentType', 'development', allowedValues: ['development','alpha','production']
    end
    
    Component 'ecs' do
      parameter name: 'EnvironmentType', allowedValues: ['development','alpha','production']
      parameter name: 'Ami', value: '/ssm/path/Ami', type: 'AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>'
    end
    
end
```


#### MappingParam

`MappingParam` - Mapping parameters value is passed as CloudFormation mapping lookup from outer component.
This DSL statements takes a full body, as Mapping name, Map key, and value key need to be specified. `key`,
 `attribute` and `map` methods are used to specify these properties. Mapping parameters involve ruby code execution



 ```ruby
# Inner component
CfhighlanderTemplate do
  Name 's3'
  Parameters do
    MappingParam 'BucketName' do
      map 'AccountId'
      attribute 'DnsDomain'
    end
  end
end
 ```


### DependsOn

`DependsOn` - this will include any globally exported libraries from given
template. E.g.

 ```ruby
CfhighlanderTemplate do
  Name 's3'
  DependsOn 'vpc@1.0.3'
end
 ```

Will include any cfndsl libraries present and exported in vpc template
so extension methods can be consumed within cfndsl template.

### Component dependson

If you require dependencies between nest stacks, this can be defined in the component by using the `dependson` attribute with the value of the depend component names. This will take an array of component names or a string with a single component name. This adds the cloudformation `DependsOn` property to the stack resource in the master template.

```ruby
CfhighlanderTemplate do
  Name 'test'
  Component name: 'vpc', template: 'vpc'
  Component name: 'bastion', template: 'bastion'
  Component name: 'ecs', template: 'ecs', dependson: ['vpc','bastion']
end
```

### LambdaFunctions


Cfhighlander supports following in terms of lambda source code management

- Package and deploy lambda that has source code published to s3 as zip archive
- Package and deploy lambda that has source code published to http(s) url
- Package and deploy lambda with absolute source code location, or relative to component
  root directory
- When extending certain highlander component, of
- Execute arbitrary 'package command' before creating final archive. This allows for downloading
code dependencies

#### Configuration and rendering

Lambda functions are defined in cfhighlander templates using `LambdaFunctions` DSL statement:

```ruby
CfhighlanderTemplate do
    Name 'my_app'
    LambdaFunctions 'highlanderdocoexample'
end
```

In example above, `lambdas` - value passed to `LambdaFunctions` dsl statement is actually
cfhighlander component configuration key, under which lambda functions, and their respective
IAM roles are defined. Consider configuration below - all keys are commented with explanation

```yaml
highlanderdocoexample:

  # custom policies can be referenced in roles
  custom_policies:
    cognito:
      action:
        - cognito-idp:*
      resource: '*'

  # at least one role must be defined
  roles:
    default:
      # using one of the default policies, or custom policies defined above
      # defined at https://github.com/theonestack/cfhighlander/blob/develop/cfndsl_ext/config/managed_policies.yaml
      policies_inline:
        - cloudwatch-logs
        - cognito

      # managed IAM policies are supported as well
      policies_managed:
        - arn:aws:iam::aws:policy/IAMReadOnlyAccess
        - Fn::Sub: 'arn:aws:iam::${AWS::AccountId}:policy/my_app_policy'

  # you can have multiple functions defined, each as key under 'functions'
  functions:
    myapp:

      # link to a role key above defined - mandatory
      role: default

      # code location. Can be file, archive, s3://url or http(s)://url.
      # mandatory configuration option
      code: src/app.py

      # lambda runtime
      runtime: python3.6

      # functions that are not named are having their name auto generated via cloudformation
      # this key defaults to false if not given
      named: true

      # if function is named, either top level key (myapp) will be used, or explicit name
      # this key is optional, and used only if named: is set to true
      function_name:
        Fn::Sub: '${EnvironmentName}-myapp-${EnvironmentVersion}'

      # function timeout (defaults to 30)
      timeout: 30

      # lambda function entrypoint
      handler: app.index

      # command to install any dependencies (optional)
      # if you don't want to get prompted for every command execution use -q (quiet) option
      package_cmd: 'pip3 install -r requirements.txt -t .'

      # creates a log group with cloudformation and sets the retention period in days
      # if not set lambda will create the log group with a unlimited retention
      # note that if lambda has already created a log group, it will need to be deleted
      # before this can be updated.
      log_retention: 30

      # (optional) allowed source. e.g. invocation using SNS
      # for every allowed source, source_arn can be provided optionally
      allowed_sources:
       -
         principal: sns.amazonaws.com
       -
         principal: sns.amazonaws.com
         source_arn: arn:aws:sns:us-east-2:123456789012:my-topic

      # (optional) invoke function on a schedule, with optional payload
      schedules:
       - cronExpression: 'rate(1 minute)'
         payload: '{ "message": "ping" }'
```


#### Packaging and publishing

During cfhighlander compilation process, every defined lambda functio goes through process
of packaging:

- If s3 URI or http(s) uri is given as function code, it is being downloaded
- Temporary packaging directory is created
- If `package_cmd` key is given, this command is being executed in temporary directory
- Whole temporary directory is compressed and moved to `out/lambdas/$function.$timestamp.zip`
- Sha256 hash is calculated for given file and rendered into cloudformation as function
  version
- Packaging information is rendered into `out/lambdas/$function.$timestamp.zip.info.yaml`
  and added to final archive

Any archive with `*.zip` extension will be uploaded to s3 with `cfpublish` command


#### Referencing

As all of the lambda functions are rendered as cloudformation resources, they can be
referenced in other blocks. E.g. with example above, application component could have
following output defined in component's cfndsl file

```ruby
# myapp.cfndsl.rb
CloudFormation do

    Output('MyAppFunctionName') do
        Value(Ref('myapp'))
    end

end


```

## Finding templates and creating components


Templates are located by default in following locations

- `$WD`
- `$WD/$componentname`
- `$WD/components/$componentname`
- `~/.cfhighlander/components/componentname/componentversion`
- `https://github.com/cfhighlander/theonestack/hl-component-$componentname` on `master` branch

Location of component templates can be given as git/github repo:

```ruby

CfhighlanderTemplate do

      # pulls directly from master branch of https://github.com/theonestack/hl-component-vpc
      Component name: 'vpc0', template: 'vpc'

      # specify branch github.com: or github: work. You specify branch with hash
      Component name: 'vpc1', template: 'github:theonestack/hl-component-vpc#master'

      # you can use git over ssh
      # Component name: 'vpc2', template: 'git:git@github.com:theonestack/hl-component-vpc.git'

      # use git over https
      Component name: 'vpc3', template: 'git:https://github.com/theonestack/hl-component-sns.git'

      # specify .snapshot to always clone fresh copy
      Component name: 'vpc4', template: 'git:https://github.com/theonestack/hl-component-sns.git#master.snapshot'

      # by default, if not found locally, highlander will search for https://github.com/theonestack/component-$componentname
      # in v${version} branch (or tag for that matter)
      Component name: 'vpc5', template: 'vpc@1.0.4'

end

```
## Render mode for components

Rendering component resources in resulting cloudformation stack is available in 2 modes. These modes
are controlled using `render` keyword of `Component` DSL statement

`Substack` - creates additional substack for cfhighlander component and points to it using [CloudFormation
Stack](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-stack.html) resource type
This is also default render mode - if no render mode is specified `Substack` will be used

`Inline` - places all defined resources from inner component in outer component cloudformation template. Resources,
Outputs, Conditions, Parameters and Mappings are all inlined - please note that some of the template elements may be renamed in this
process in order to assure unique names.

There are some limitations when using inline components - Inlined component parameters, having values as outputs from another component (inlined or not)
can't be referenced in component conditions. However, conditions referencing mapping values or parameters passed as mapping values,
are allowed.

**`SIDE EFFECTS`** Side effect of moving from substack based to fully inlined stack may be revealing some of the implicit dependencies within an environment

*Example:* Component A defines Hosted Zone, while component B defines Record Set for given hosted zone. Record set is defined
by referencing Zone Name (rather than ZoneId), meaning there is no explicit dependency between the resources. When both components
are rendered as substack, implicit dependency is created if there is at least one output from component A passed as parameter
to component B. Rendering components inlined removes this implicitly defined dependency, as a consequence stack deletion or creation
may be halted, as record set is being created/deleted before prior the record set.

**`WARNING`** Be aware of [resource, condition, parameter, output and mapping limits](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cloudformation-limits.html) on a single template
when rendering inner components inlined.

**`EXAMPLE`** All of the VPC resources will be rendered in outer component template, while bastion
will be referenced as substack in example below.

```ruby
CfhighlanderTemplate do

    Component template:'vpc@1.5.0', name: 'vpc', render: Inline
    Component template:'bastion@1.2.0', name: 'bastion', render: Substack

end
```



## Rendering CloudFormation templates


```bash
$ cfhighlander cfcompile [component] [-v distributedversion]
```

## Global Extensions

Any extensions placed within `cfndsl_ext` folder in core library code are
available in cfndsl templates of all components. Any extensions placed within `hl_ext` in core library code are
available in cfhighlander templates of all components.


## Environment variables

`CFHIGHLANDER_WORKDIR` - defaults to $PWD, determines location of 'out' folder where all of the
generated files are placed

`CFHIGHLANDER_AWS_RETRY_LIMIT` - defaults to 10. Number of retries for AWS SDK before giving up.
AWS SDK uses exponential backoff to make the API calls



## Testing components

Tests are designed for testing different configuration options on components.
They can be defined as `my_test.test.yaml` files in the `tests/` directory.
Each test file represents a single test configuration which is then compiled
and validated against AWS cloudformation api.

### Metadata

test metadata needs to defined as bellow with at least a `name:`. Other key:values are for documentation.

```yaml
test_metadata:
  type: config
  name: queues with config overrides
  description: Create 2 queues with name and override available config
```

### Test Paramaters

If you want to test a component with a parameter input you can specify the `test-parameters:` key with key:value pairs of parameters

```yaml
# Define the test parameter
test_parameters:
  SecurityGroupId: sg-123456789

# Test configuration
security_group_rules:
  -
    from: 22
    protocol: tcp
    security_group_id:
      # use the parameter within our test
      Ref: SecurityGroupId
    desc: ssh access from another security group
```

### Running Test

```bash
$ cfhighlander cftest [component] [options]
```

```bash
Usage:
  cfhighlander cftest component[@version] -f, --format=FORMAT

Options:
  -d, [--directory=DIRECTORY]        # Tests directory
                                     # Default: tests
  -t, [--tests=one two three]        # Point to specific test files using the relative path
      [--dstbucket=DSTBUCKET]        # Distribution S3 bucket
      [--dstprefix=DSTPREFIX]        # Distribution S3 prefix
  -f, --format=FORMAT                # CloudFormation templates output format
                                     # Default: yaml
                                     # Possible values: yaml, json
      [--validate], [--no-validate]  # Optionally validate template
                                     # Default: true
  -q, [--quiet], [--no-quiet]        # Silently agree on user prompts (e.g. Package lambda command)
                                     # Default: true
  -r, [--report=REPORT]              # report output format in reports directory
                                     # Possible values: json, xml

Test Highlander component with test case config
```

### Reports

By default test will print the output to stdout. You can output to a file with a format of xml or json using the `-r` option

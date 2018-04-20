# Highlander

Highlander is DSL processor that enables composition and orchestration of Amazon CloudFormation templates 
written using [CfnDsl](https://github.com/cfndsl/cfndsl) in an abstract way. It tries to tackle problem of merging multiple templates into master
template in an elegant way, so higher degree of template reuse can be achieved. It does so by formalising commonly
used patterns via DSL statements. For an example, passing output of one stack into other stack is achieved using 
`OutputParam` highlander DSL statement, rather than wiring this parameters manually in cfndsl templates. For this example to 
work, parent component will have to pull in both component rendering output values, and component pulling them in
as parameters. It also enables it's user to build component library, where components can be distributed to s3, and 
consequentially references to them resolved. 

Highlander DSL produces CloudFormation templates in 3 phases

- Processing referenced component's configuration and resolving configuration exports
- Producing [CfnDsl](https://github.com/cfndsl/cfndsl) templates for all components and subcomponents as intermediary
  step
- Producing resulting CloudFormation templates using configuration and templates generated in two previous phases.

Each phase above is executable as stand-alone through CLI, making development of Highlander templates easier by enabling
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
- Define how their parameters are wired with other components (sibling and outer components)
- Define how their configuration affects other components
- Define sources of their inner components
- Define publish location for both component source code and compiled CloudFormation templates
- Define cfndsl template used for building CloudFormation resources


**Outer component** is component that defines other component via higlander dsl `Component` statement. Defined component
is called **inner component**. Components defined under same outer component are **sibling components**

## Usage

You can either pull highlander classes in your own code, or more commonly use it via command line interface (cli).
For both ways, highlander is distributed as ruby gem


```bash
$ gem install highlander
$ highlander help
highlander commands:
  highlander cfcompile component[@version] -f, --format=FORMAT   # Compile Highlander component to CloudFormation templates
  highlander cfpublish component[@version] -f, --format=FORMAT   # Publish CloudFormation template for component, and it' referenced subcomponents
  highlander configcompile component[@version]                   # Compile Highlander components configuration
  highlander dslcompile component[@version] -f, --format=FORMAT  # Compile Highlander component configuration and create cfndsl templates
  highlander help [COMMAND]                                      # Describe available commands or one specific command
  highlander publish component[@version] [-v published_version]  # Publish CloudFormation template for component, and it' referenced subcomponents

```
### Working directory

All templates and configuration generated are placed in `$WORKDIR/out` directory. Optionally, you can alter working directory
via `HIGHLANDER_WORKDIR` environment variable. 

### Commands

To get full list of options for any of cli commands use `highlander help command_name` syntax

```bash
$ highlander help publish
Usage:
  highlander publish component[@version] [-v published_version]

Options:
      [--dstbucket=DSTBUCKET]  # Distribution S3 bucket
      [--dstprefix=DSTPREFIX]  # Distribution S3 prefix
  -v, [--version=VERSION]      # Distribution component version, defaults to latest

Publish CloudFormation template for component,
            and it' referenced subcomponents

```

#### Silent mode

Highlander DSL processor has built-in support for packaging and deploying AWS Lambda functions. Some of these lambda
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


#### configcompile

*configcompile* produces configuration yamls that are passed as external configuration when processing
cfndsl templates. Check component configuration section for more details.

#### dslcompile

*dslcompile* will produce intermediary cfndsl templates. This is useful for debugging highlander components

#### publish

*publish* command publishes highlander components source code to s3 location (compared to *cfpublish* which is publishing
compiled cloudformation templates). Same CLI / DSL options apply as for *cfpublish* command. Version defaults to `latest`



## Component configuration

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


- Outer component explicit configuration. You can pass `config` named parameter to `Component` statement, such as

```ruby
HighlanderComponent do

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


### Parameters

Parameters block is used to define CloudFormation template parameters, and metadata on how they 
are wired with outer or sibling components. 

```ruby
HighlanderComponent do
  Parameters do
    ##
    ##  parameter definitions here
    ##
  end
end
```

Parameter block supports following parameters

#### ComponentParam

`ComponentParam` - Component parameter takes name and default value. It defines component parameter
that is not auto-wired in any way with outer component. This parameter will either use default value, or value
explicitly passed from outer component. 

```ruby

# Inner Component
HighlanderComponent do
  Name 's3'
  Parameters do
     ComponentParam 'BucketName','highlander.example.com.au'
  end
end
```

```ruby
# Outer component
HighlanderComponent do
  # instantiate inner component with name and template
  Component template:'s3',
            name:'s3', 
            parameters:{'BucketName' => 'outer.example.com.au'}
end
```

#### StackParam

`StackParam` - Stack parameter bubbles up to it's outer component. Outer component will either define top level parameter
with same name as inner component parameter (if parameter is defined as global), or it will be prefixed with inner component name.


```ruby
# Outer component
HighlanderComponent do
  Component template:'s3',name:'s3' 
end
```

```ruby
# Inner component
HighlanderComponent do
  Name 's3'
  Parameters do
    StackParam 'EnvironmentName','dev', isGlobal:true
    StackParam 'BucketName','highlander.example.com.au', isGlobal:false
  end
end
```


Example above translates to following cfndsl template in outer component
```ruby
CloudFormation do

    Parameter('EnvironmentName') do
    Type 'String'
    Default ''
    end

    Parameter('s3BucketName') do
    Type 'String'
    Default 'highlander.example.com.au'
    end
  
    CloudFormation_Stack('s3') do
      TemplateURL 'https://distributionbucket/dist/latest/s3.yaml'
      Parameters ({
      
        'EnvironmentName' => Ref('EnvironmentName'),
      
        'BucketName' => Ref('s3BucketName'),
      
      })
    end
end
```


#### MappingParam

`MappingParam` - Mapping parameters value is passed as CloudFormation mapping lookup from outer component.
This DSL statements takes a full body, as Mapping name, Map key, and value key need to be specified. `key`,
 `attribute` and `map` methods are used to specify these properties. Mapping parameters involve ruby code execution
 
 
 
 ```ruby
# Inner component
HighlanderComponent do
  Name 's3'
  Parameters do
    MappingParam 'BucketName' do
      map 'AccountId'
      attribute 'DnsDomain' 
    end
  end
end
 ```


#### OutputParam

TBD

### DependsOn

`DependsOn` - this will include any globally exported libraries from given 
template. E.g.

 ```ruby
HighlanderComponent do
  Name 's3'
  DependsOn 'vpc@1.0.3'
end
 ```
 
Will include any cfndsl libraries present and exported in vpc template 
so extension methods can be consumed within cfndsl template.

### LambdaFunctions

#### Packaging and publishing

#### Rendering

#### Referencing


## Finding and loading components

## Rendering CloudFormation templates



## Global Extensions

Any extensions placed within `cfndsl_ext` folder will be 
available in cfndsl templates of all components. Any extensions placed within `hl_ext` folder are 
available in highlander templates of all components. 

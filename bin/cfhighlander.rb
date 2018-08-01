####
####  highlander publish  [component_dir:-$PWD]  (defaults to current dir) -  (publishes highlander component)
####  highlander compile  [component_dir:-$PWD]  [--format json] - compile component to cloudformation template
####  highlander env create --name [stack_name]  [component_name@version:-$PWD] create environment out of component (compile, deploy to s3, update)
####  highlander env update --name [stack_name]  [component_name@version]       update environment to component version (compile,deploy to s3, update)
####  highlander env delete --name [stack_name]
####


require 'thor'
require 'rubygems'
require_relative '../lib/cfhighlander.compiler'
require_relative '../lib/cfhighlander.factory'
require_relative '../lib/cfhighlander.publisher'
require_relative '../lib/cfhighlander.validator'
require_relative '../hl_ext/aws_helper'

class HighlanderCli < Thor

  package_name "cfhighlander"

  desc 'configcompile component[@version]', 'Compile Highlander components configuration'

  def configcompile(template_name)

    # find and load component
    component_loader = Cfhighlander::Factory::ComponentFactory.new
    component = component_loader.loadComponentFromTemplate(template_name)
    component.load

    # compile cfndsl template
    component_compiler = Cfhighlander::Compiler::ComponentCompiler.new(component)
    component_compiler.writeConfig(true)
  end

  desc 'dslcompile component[@version]', 'Compile Highlander component configuration and create cfndsl templates'
  method_option :version, :type => :string, :required => false, :default => nil, :aliases => '-v',
      :desc => 'Version to compile by which subcomponents are referenced'
  method_option :dstbucket, :type => :string, :required => false, :default => nil,
      :desc => 'Distribution S3 bucket'
  method_option :dstprefix, :type => :string, :required => false, :default => nil,
      :desc => 'Distribution S3 prefix'
  method_option :format, :type => :string, :required => true, :default => 'yaml', :aliases => "-f",
      :enum => %w(yaml json), :desc => 'CloudFormation templates output format'
  method_option :quiet, :type => :boolean, :default => false, :aliases => '-q',
      :desc => 'Silently agree on user prompts (e.g. Package lambda command)'

  def dslcompile(component_name)
    component = build_component(options, component_name)

    # compile cfndsl template
    component_compiler = Cfhighlander::Compiler::ComponentCompiler.new(component)
    component_compiler.silent_mode = options[:quiet]
    out_format = options[:format]
    component_compiler.compileCfnDsl out_format
  end


  desc 'cfcompile component[@version]', 'Compile Highlander component to CloudFormation templates'
  method_option :version, :type => :string, :required => false, :default => nil, :aliases => '-v',
      :desc => 'Version to compile by which subcomponents are referenced'
  method_option :dstbucket, :type => :string, :required => false, :default => nil,
      :desc => 'Distribution S3 bucket'
  method_option :dstprefix, :type => :string, :required => false, :default => nil,
      :desc => 'Distribution S3 prefix'
  method_option :format, :type => :string, :required => true, :default => 'yaml', :aliases => "-f",
      :enum => %w(yaml json), :desc => 'CloudFormation templates output format'
  method_option :validate, :type => :boolean, :default => false,
      :desc => 'Optionally validate template'
  method_option :quiet, :type => :boolean, :default => false, :aliases => '-q',
      :desc => 'Silently agree on user prompts (e.g. Package lambda command)'

  def cfcompile(component_name = nil, autogenerate_dist = false)

    if component_name.nil?
      candidates = Dir["*.cfhighlander.rb"]
      if candidates.size == 0
        self.help('cfcompile')
        exit -1
      else
        component_name = candidates[0].gsub('.cfhighlander.rb','')
      end
    end

    component = build_component(options, component_name)

    if component.highlander_dsl.distribution_bucket.nil? or component.highlander_dsl.distribution_prefix.nil?
      component.distribution_bucket="#{aws_account_id()}.#{aws_current_region()}.cfhighlander.templates" if component.distribution_bucket.nil?
      component.distribution_prefix="published-templates/#{component.name}" if component.distribution_prefix.nil?
      puts "INFO: Reloading component, as auto-generated distribution settings  are being applied..."
      component.load
    end if autogenerate_dist

    # compile cloud formation
    component_compiler = Cfhighlander::Compiler::ComponentCompiler.new(component)
    component_compiler.silent_mode = options[:quiet]
    out_format = options[:format]
    component_compiler.compileCloudFormation out_format
    if options[:validate]
      component_validator = Cfhighlander::Cloudformation::Validator.new(component)
      component_validator.validate(component_compiler.cfn_template_paths, out_format)
    end
    component_compiler
  end

  desc 'cfpublish component[@version]', 'Publish CloudFormation template for component,
            and it\' referenced subcomponents'
  method_option :version, :type => :string, :required => false, :default => nil, :aliases => '-v',
      :desc => 'Version to compile by which subcomponents are referenced'
  method_option :dstbucket, :type => :string, :required => false, :default => nil,
      :desc => 'Distribution S3 bucket'
  method_option :dstprefix, :type => :string, :required => false, :default => nil,
      :desc => 'Distribution S3 prefix'
  method_option :format, :type => :string, :required => true, :default => 'yaml', :aliases => "-f",
      :enum => %w(yaml json), :desc => 'CloudFormation templates output format'
  method_option :validate, :type => :boolean, :default => false,
      :desc => 'Optionally validate template'
  method_option :quiet, :type => :boolean, :default => false, :aliases => '-q',
      :desc => 'Silently agree on user prompts (e.g. Package lambda command)'

  def cfpublish(component_name)
    compiler = cfcompile(component_name, true)
    publisher = Cfhighlander::Publisher::ComponentPublisher.new(compiler.component, false)
    publisher.publishFiles(compiler.cfn_template_paths + compiler.lambda_src_paths)

    puts "\n\nUse following url to launch CloudFormation stack\n\n#{publisher.getLaunchStackUrl}\n\n"

  end


  desc 'publish component[@version] [-v published_version]', 'Publish CloudFormation template for component,
            and it\'s referenced subcomponents'
  method_option :dstbucket, :type => :string, :required => false, :default => nil,
      :desc => 'Distribution S3 bucket'
  method_option :dstprefix, :type => :string, :required => false, :default => nil,
      :desc => 'Distribution S3 prefix'
  method_option :version, :type => :string, :required => false, :default => nil, :aliases => '-v',
      :desc => 'Distribution component version, defaults to latest'

  def publish(template_name)
    component_version = options[:version]
    distribution_bucket = options[:dstbucket]
    distribution_prefix = options[:dstprefix]

    # find and load component
    component_loader = Cfhighlander::Factory::ComponentFactory.new
    component = component_loader.loadComponentFromTemplate(template_name)
    component.version = component_version
    component.distribution_bucket = distribution_bucket unless distribution_bucket.nil?
    component.distribution_prefix = distribution_prefix unless distribution_prefix.nil?
    component.load

    publisher = Cfhighlander::Publisher::ComponentPublisher.new(component, true)
    publisher.publishComponent
  end

end

# build component from passed cli options
def build_component(options, template_name)

  component_version = options[:version]
  distribution_bucket = options[:dstbucket]
  distribution_prefix = options[:dstprefix]

  # find and load component
  component_loader = Cfhighlander::Factory::ComponentFactory.new
  component = component_loader.loadComponentFromTemplate(template_name)
  component.version = component_version unless component_version.nil?
  component.distribution_bucket = distribution_bucket unless distribution_bucket.nil?
  component.distribution_prefix = distribution_prefix unless distribution_prefix.nil?
  component.load
  component
end

if ENV['CFHIGHLANDER_WORKDIR'].nil?
  ENV['CFHIGHLANDER_WORKDIR'] = Dir.pwd
end
if ENV['HIGHLANDER_WORKDIR'].nil?
  ENV['HIGHLANDER_WORKDIR'] = Dir.pwd
end

HighlanderCli.start

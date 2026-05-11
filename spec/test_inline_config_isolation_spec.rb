require_relative '../bin/cfhighlander'
require_relative '../lib/util/cloudformation.util'
require 'rspec'
require 'yaml'
require 'fileutils'

RSpec.describe Cfhighlander::Compiler::ComponentCompiler, "inline config isolation" do

  context "when two inline instances of the same template have different configs" do
    it "each instance compiles with its own config" do

      src_dir = "#{File.dirname(__FILE__)}/data/inline_config_isolation/src"
      ENV['CFHIGHLANDER_WORKDIR'] = src_dir

      factory = Cfhighlander::Factory::ComponentFactory.new
      component = factory.loadComponentFromTemplate('p')
      component.load
      component.eval_cfndsl

      compiler = Cfhighlander::Compiler::ComponentCompiler.new(component)
      model_flat = compiler.compileCloudFormation

      resources = model_flat['Resources']

      child_a_bucket = resources['ConfigBucket']
      child_b_bucket = resources['childbConfigBucket']

      expect(child_a_bucket).not_to be_nil, "expected child_a's ConfigBucket resource"
      expect(child_b_bucket).not_to be_nil, "expected child_b's childbConfigBucket resource"

      child_a_name = child_a_bucket['Properties']['BucketName']
      child_b_name = child_b_bucket['Properties']['BucketName']

      expect(child_a_name).to eq('alpha'), "child_a should use its own config"
      expect(child_b_name).to eq('beta'), "child_b should use its own config"
    end
  end

end

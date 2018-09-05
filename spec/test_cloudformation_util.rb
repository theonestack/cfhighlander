require_relative '../bin/cfhighlander'
require_relative '../lib/util/cloudformation.util'
require 'git'
require 'pp'
require 'octokit'
require 'rspec'

RSpec.describe Cfhighlander::Util::CloudformationUtil, "#flattenCloudformation" do

  context "test cloudformation inllining" do
    it "flattens cloudformation" do

      src_dir = "#{File.dirname(__FILE__)}/data/flatten/src"
      ENV['CFHIGHLANDER_WORKDIR'] = src_dir

      factory = Cfhighlander::Factory::ComponentFactory.new
      component = factory.loadComponentFromTemplate('c')
      component.load
      component.eval_cfndsl

      compiler = Cfhighlander::Compiler::ComponentCompiler.new(component)
      compiler.compileCloudFormation

      model_flat = Cfhighlander::Util::CloudformationUtil.flattenCloudformation(component:component)
      model_flat = JSON.parse(model_flat.to_json)
      model_flat_expected =  YAML.load(File.read("#{src_dir}/../c.compiled.flat.yaml"))
      File.write "#{File.dirname(__FILE__)}/../test/c.flat.yaml", model_flat.to_yaml

      expect(model_flat).to eq(model_flat_expected)

    end

  end
end


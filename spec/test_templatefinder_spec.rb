require_relative '../lib/cfhighlander.factory.templatefinder'
require 'fileutils'
require 'git'
require 'rspec'
require 'tmpdir'

RSpec.describe Cfhighlander::Factory::TemplateFinder, "#findTemplateGit" do

  let(:finder) { Cfhighlander::Factory::TemplateFinder.new }

  around(:each) do |example|
    Dir.mktmpdir do |dir|
      @cache_path = File.join(dir, 'component')
      example.run
    end
  end

  before(:each) do
    # keep the spec instant regardless of retry/delay env overrides
    allow(finder).to receive(:sleep)
    ENV.delete('CFHIGHLANDER_COMPONENT_FETCH_RETRIES')
    ENV.delete('CFHIGHLANDER_COMPONENT_FETCH_RETRY_DELAY')
  end

  it "retries a failing clone and succeeds once it stops failing" do
    ENV['CFHIGHLANDER_COMPONENT_FETCH_RETRIES'] = '3'

    attempts = 0
    allow(Git).to receive(:clone) do |_url, path, _opts|
      attempts += 1
      raise Git::GitExecuteError, "simulated github flakiness" if attempts < 3

      FileUtils.mkdir_p path
      File.write(File.join(path, 'mycomponent.cfhighlander.rb'), '')
    end

    component_name, location = finder.findTemplateGit(
      @cache_path, 'mycomponent', 'latest', 'https://github.com/theonestack/hl-component-mycomponent', 'master'
    )

    expect(attempts).to eq(3)
    expect(component_name).to eq('mycomponent')
    expect(location).to eq("#{@cache_path}/")
    expect(finder).to have_received(:sleep).twice
    expect(finder).to have_received(:sleep).with(1)
    expect(finder).to have_received(:sleep).with(2)
  end

  it "gives up after exhausting retries and returns nil without raising" do
    ENV['CFHIGHLANDER_COMPONENT_FETCH_RETRIES'] = '2'
    allow(STDERR).to receive(:puts)

    attempts = 0
    allow(Git).to receive(:clone) do |*_args|
      attempts += 1
      raise Git::GitExecuteError, "simulated github outage"
    end

    result = finder.findTemplateGit(
      @cache_path, 'mycomponent', 'latest', 'https://github.com/theonestack/hl-component-mycomponent', 'master'
    )

    expect(result).to be_nil
    # initial attempt + 2 retries
    expect(attempts).to eq(3)
    expect(finder).to have_received(:sleep).twice
    expect(STDERR).to have_received(:puts).with(a_string_matching(/Failed to resolve component mycomponent@latest/))
  end

end

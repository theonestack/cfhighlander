require_relative '../bin/highlander'
require 'git'

RSpec.describe HighlanderCli, "#run" do

  context "test component" do
    it "compiles test cfhighlander component" do

      clone_opts = { depth: 1 }
      clone_opts[:branch] = 'develop'
      current = Dir.pwd
      wd = "#{current}/test/hl-component-test"
      if Dir.exist? wd
        FileUtils.rmtree wd
      end
      Git.clone 'https://github.com/theonestack/hl-component-test', wd, clone_opts

      is_travis_pr = (ENV['TRAVIS'] and ENV['TRAVIS_PULL_REQUEST'].to_i > 0)

      Dir.chdir wd
      ARGV.clear
      ARGV << 'cfcompile'
      ARGV << 'test'
      ARGV << '--validate' unless is_travis_pr


      default_maps = {
          '123456789012' => {
              'us-east-1' => {
                  'Az0' => 'us-east-1a',
                  'Az1' => 'us-east-1b',
                  'Ac2' => 'us-east-1c'
              }
          }
      }
      # if running within travis and caused by PR, there are no creds available, thus
      # we have to mock the azs
      if is_travis_pr
        File.write 'az.mappings.yaml', default_maps.to_yaml
      end

      result = HighlanderCli.start
      expect(result).not_to eq(nil)
    end
  end

end
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

      Dir.chdir wd
      ARGV.clear
      ARGV << 'cfcompile'
      ARGV << 'test'
      ARGV << '--validate'

      result = HighlanderCli.start
      expect(result).not_to eq(nil)
    end
  end

end
require_relative '../bin/cfhighlander'
require 'git'
require 'pp'
require 'octokit'

THEONSTACK_COMPONENT_PREFIX = 'hl-component-'

RSpec.describe HighlanderCli, "#run" do

  def test_repo(current_dir, repo, branch)
    clone_opts = { depth: 1 }
    clone_opts[:branch] = branch
    wd = "#{current_dir}/test/#{repo}"
    if Dir.exist? wd
      FileUtils.rmtree wd
    end
    puts "Testing #{repo} - cloning in #{wd}"
    Git.clone "https://github.com/theonestack/#{repo}", wd, clone_opts

    puts("Environment:")
    pp ENV

    is_travis_pr = ((ENV.key? 'TRAVIS') and (ENV['TRAVIS_PULL_REQUEST'].to_i > 0))

    Dir.chdir wd
    ARGV.clear
    ARGV << 'cfcompile'
    ARGV << repo.gsub(THEONSTACK_COMPONENT_PREFIX,'')
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
      File.write "#{ENV['HIGHLANDER_WORKDIR']}/az.mappings.yaml", default_maps.to_yaml
    end

    result = HighlanderCli.start

    expect(result).not_to eq(nil)
  end

  context "test theonestack default components" do
    Octokit.configure do |c|
      c.access_token = ENV['GITHUB_PERSONAL_ACCESS_TOKEN'] if ENV.key? 'GITHUB_PERSONAL_ACCESS_TOKEN'
    end
    client = Octokit::Client.new
    cwd = Dir.pwd
    client.get('orgs/theonestack/repos').each do |repo|
      if repo[:name].start_with? THEONSTACK_COMPONENT_PREFIX
        it "theonestack/#{repo[:name]} compiles" do
          test_repo(cwd, repo[:name], 'master')
        end
      end
    end
  end
end


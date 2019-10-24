require_relative '../bin/cfhighlander'
require 'git'
require 'pp'
require 'octokit'
THEONSTACK_COMPONENT_PREFIX = 'hl-component-'
THEONSTACK_COMPONENTS = %w(
  hl-component-vpc
  hl-component-ecs
  hl-component-application-loadbalancer
  hl-component-network-loadbalancer
  hl-component-eks-cluster
  hl-component-bastion
  hl-component-fargate
  hl-component-ecs-service
  hl-component-aurora-mysql
  hl-component-aurora-postgres
  hl-component-s3
  hl-component-cloudfront
  hl-component-sqs
  hl-component-amazonmq
  hl-component-sftp
)

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
    ARGV << 'cftest'
    ARGV << repo.gsub(THEONSTACK_COMPONENT_PREFIX,'')
    ARGV << '--no-validate' if is_travis_pr

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
    
    begin
      described_class.start
    rescue SystemExit => e
      expect(e.status).to eq 0
    end
    
  end

  context "test theonestack default components" do
    Octokit.configure do |c|
      c.access_token = ENV['GITHUB_PERSONAL_ACCESS_TOKEN'] if ENV.key? 'GITHUB_PERSONAL_ACCESS_TOKEN'
    end
    client = Octokit::Client.new
    cwd = Dir.pwd
    client.get('orgs/theonestack/repos').each do |repo|
      if THEONSTACK_COMPONENTS.include? repo[:name]
        it "theonestack/#{repo[:name]} passes cftests" do
          test_repo(cwd, repo[:name], 'master')
        end
      end
    end
  end
end

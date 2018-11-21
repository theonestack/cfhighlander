require 'rake'


Gem::Specification.new do |s|
  s.name = 'cfhighlander'
  s.version = '0.6.1'
  s.version = "#{s.version}.alpha.#{Time.now.getutc.to_i}" if ENV['TRAVIS'] and ENV['TRAVIS_BRANCH'] != 'master'
  s.summary = 'DSL on top of cfndsl. Manage libraries of cloudformation components'
  s.description = ''
  s.authors = [ 'Nikola Tosic', 'Aaron Walker', 'Angus Vine']
  s.email = 'theonestackcfhighlander@gmail.com'
  s.files = FileList['cfndsl_ext/**/*', 'hl_ext/*', 'templates/*.erb', 'lib/**/*.rb', 'bin/*', 'README.md']
  s.homepage = 'https://github.com/theonestack/cfhighlander/blob/master/README.md'
  s.license = 'MIT'
  s.executables << 'cfhighlander'
  s.executables << 'cfcompile'
  s.executables << 'cfpublish'

  s.add_runtime_dependency 'highline', '>=1.7.10','<1.8'
  s.add_runtime_dependency 'thor', '~>0.20', '<1'
  s.add_runtime_dependency 'cfndsl', '~>0.16', '<1'
  s.add_runtime_dependency 'rubyzip', '>=1.2.1', '<2'
  s.add_runtime_dependency 'aws-sdk-core', '~> 3','<4'
  s.add_runtime_dependency 'aws-sdk-s3', '~> 1', '<2'
  s.add_runtime_dependency 'aws-sdk-ec2', '~> 1', '<2'
  s.add_runtime_dependency 'aws-sdk-cloudformation', '~> 1', '<2'
  s.add_runtime_dependency 'git', '~> 1.4', '<2'
  s.add_runtime_dependency 'netaddr', '~> 1.5', '>= 1.5.1'
  s.add_runtime_dependency 'duplicate','~> 1.1'
  s.add_development_dependency 'rspec', '~> 3.7'
end

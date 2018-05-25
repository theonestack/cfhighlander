require 'rake'

Gem::Specification.new do |s|
  s.name = 'highlander'
  s.version = '0.1.2'
  s.date = '2018-04-19'
  s.summary = 'DSL on top of cfndsl. Manage libraries of cloudformation components'
  s.description = ''
  s.authors = ['Base2Services', 'Nikola Tosic']
  s.email = 'itsupport@base2services.com'
  s.files = FileList['cfndsl_ext/**/*', 'hl_ext/*', 'templates/*.erb', 'lib/**/*.rb', 'bin/*', 'README.md']
  s.homepage = 'https://github.com/base2Services/highlander/blob/master/README.md'
  s.license = 'MIT'
  s.executables << 'highlander'

  s.add_runtime_dependency 'highline', '>=1.7.10','<1.8'
  s.add_runtime_dependency 'thor', '>=0.20', '<1'
  s.add_runtime_dependency 'cfndsl', '>=0.16', '<1'
  s.add_runtime_dependency 'rubyzip', '>=1.2.1', '<2'
  s.add_runtime_dependency 'aws-sdk-core', '~> 3','<4'
  s.add_runtime_dependency 'aws-sdk-s3', '~> 1', '<2'
  s.add_runtime_dependency 'aws-sdk-ec2', '~> 1', '<2'
  s.add_runtime_dependency 'aws-sdk-cloudformation', '~> 1', '<2'
  s.add_runtime_dependency 'git', '~> 1.4', '<2'
end

.EXPORT_ALL_VARIABLES:

RUN_RUBY_CMD=docker-compose run --rm -v $$PWD:/src -w /src ruby
CFHL_DOCKER_TAG ?= $(shell cat lib/cfhighlander.version.rb  | grep VERSION | cut -d '=' -f 2 | sed 's/\.freeze//' | sed 's/"//g')
CFNDSL_SPEC_VERSION ?= 34.0.0

all: clean build test

clean:
	rm -f *.gem
	docker-compose down
.PHONY: clean

build:
	$(RUN_RUBY_CMD) make _build
.PHONY: clean

rubyShell:
	$(RUN_RUBY_CMD) bash
.PHONY: rubyShell

test:
	$(RUN_RUBY_CMD) make _test
.PHONY: test

buildDocker:
	docker build -t theonestack/cfhighlander:$(CFHL_DOCKER_TAG) -t theonestack/cfhighlander:latest --build-arg CFNDSL_SPEC_VERSION=${CFNDSL_SPEC_VERSION} .

pushDocker: buildDocker
    docker push theonestack/cfhighlander:$(CFHL_DOCKER_TAG)

_build:
	gem build cfhighlander.gemspec

_local_install:
	gem install cfhighlander-*.gem

_test:
	gem install bundler:2.0.1
	bundle install
	cfndsl -u ${CFNDSL_SPEC_VERSION}
	bundle exec rspec

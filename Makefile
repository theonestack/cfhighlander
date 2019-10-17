RUN_RUBY_CMD=docker-compose run --rm -v $$PWD:/src -w /src ruby
CFHL_DOCKER_TAG:=latest

.EXPORT_ALL_VARIABLES:

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
	docker build -t theonestack/cfhighlander:$(CFHL_DOCKER_TAG) .

_build:
	gem build cfhighlander.gemspec
_test:
	bundle install
	cfndsl -u 2.19.0
	bundle exec rspec

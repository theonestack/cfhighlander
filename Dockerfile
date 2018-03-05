FROM ruby:2.3-alpine

COPY . /src

WORKDIR /src
RUN gem build highlander.gemspec && gem install highlander-0.1.0.gem && \
    rm -rf /src

RUN adduser -h /work -u 1000 -D highlander

WORKDIR /work

USER highlander

CMD 'highlander'
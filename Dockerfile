FROM ruby:2.3-alpine

COPY . /src

WORKDIR /src
RUN rm cfhighlander-*.gem ; \
    gem build cfhighlander.gemspec && \
    gem install cfhighlander-*.gem && \
    rm -rf /src

RUN adduser -u 1000 -D cfhighlander && \
    apk add --update python py-pip git openssh-client && \
    pip install awscli

WORKDIR /work

USER cfhighlander

# required for any calls via aws sdk
ENV AWS_REGION us-east-1

CMD 'cfhighlander'

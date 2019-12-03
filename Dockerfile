FROM ruby:2.5-alpine

ARG CFNDSL_SPEC_VERSION=${CFNDSL_SPEC_VERSION:-9.0.0}

COPY . /src

WORKDIR /src
RUN rm cfhighlander-*.gem ; \
    gem build cfhighlander.gemspec && \
    gem install cfhighlander-*.gem && \
    rm -rf /src

RUN adduser -u 1000 -D cfhighlander && \
    apk add --update python3 git openssh-client bash && \
    ln $(which pip3) /bin/pip && \
    pip install awscli

WORKDIR /work

USER cfhighlander

RUN cfndsl -u ${CFNDSL_SPEC_VERSION}

# required for any calls via aws sdk
ENV AWS_REGION us-east-1

CMD 'cfhighlander'

FROM ruby:3.0.1-alpine3.13
LABEL "repository"="https://github.com/anothrNick/github-tag-action"
LABEL "homepage"="https://github.com/anothrNick/github-tag-action"
LABEL "maintainer"="Nick Sjostrom"

COPY entrypoint.sh /entrypoint.sh

RUN apk update && apk add bash git curl jq && apk add --update nodejs npm && npm install -g semver 

# Ruby build libs
RUN apk add build-essential bison openssl libreadline6 libreadline6-dev curl git-core zlib1g zlib1g-dev libssl-dev libyaml-dev libxml2-dev autoconf libc6-dev ncurses-dev automake libtool

ENTRYPOINT ["/entrypoint.sh"]

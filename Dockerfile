FROM ruby:3.0.1-alpine3.13
LABEL "repository"="https://github.com/anothrNick/github-tag-action"
LABEL "homepage"="https://github.com/anothrNick/github-tag-action"
LABEL "maintainer"="Nick Sjostrom"

COPY entrypoint.sh /entrypoint.sh

RUN apk update && apk add bash git curl jq && apk add --update nodejs npm && npm install -g semver

# Added Ruby and PG deps
RUN apk add --no-cache build-base openssl postgresql-dev

ENTRYPOINT ["/entrypoint.sh"]

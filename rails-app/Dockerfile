FROM ruby:3.3-slim

RUN apt-get update -qq && \
    apt-get install -y build-essential libpq-dev nodejs libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile ./
RUN bundle install

COPY . .

RUN mkdir -p tmp/pids

EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

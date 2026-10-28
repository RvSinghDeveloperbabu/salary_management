
FROM ruby:3.4-slim

RUN apt-get update -qq \
 && apt-get install --no-install-recommends -y \
      build-essential \
      libsqlite3-dev \
      libyaml-dev \
      pkg-config \
      git \
      curl \
      tzdata \
 && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=true

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

RUN chmod +x bin/rails \
 && mkdir -p /app/tmp/cache /app/tmp/pids /app/log \
 && chown -R 1000:1000 /app/tmp /app/log \
 && chmod -R u+rwX /app/tmp /app/log

EXPOSE 3000

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]

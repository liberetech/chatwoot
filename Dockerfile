FROM --platform=linux/amd64 chatwoot/chatwoot:v3.16.0

COPY app /app/app
COPY config/application.rb /app/config/application.rb

COPY Gemfile Gemfile.lock /app/

RUN bundle install

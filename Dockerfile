FROM ruby:3.2

ARG UID=1000
ARG GID=1000
RUN groupadd -g $GID appuser && \
    useradd -m -u $UID -g appuser appuser

WORKDIR /app

RUN chown -R appuser:appuser /app

USER appuser

COPY --chown=appuser:appuser Gemfile /app/

RUN gem install bundler
RUN bundle install

# Set the default command to run the invoice script with bundle exec
ENTRYPOINT ["bundle", "exec", "ruby", "render_invoice.rb"]
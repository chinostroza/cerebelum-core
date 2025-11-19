# ================================
# Build Stage
# ================================
FROM hexpm/elixir:1.18.0-erlang-27.1.2-debian-bookworm-20241016-slim AS build

# Install build dependencies
RUN apt-get update -y && apt-get install -y \
    build-essential \
    git \
    curl \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Prepare build directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy compile-time config files before we compile dependencies
# to ensure any relevant config changes trigger recompilation
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# Copy application code
COPY priv priv
COPY lib lib

# Compile the release
RUN mix compile

# Copy runtime configuration
COPY config/runtime.exs config/

# Compile assets (if any)
# RUN mix assets.deploy

# Create the release
RUN mix release

# ================================
# Runtime Stage
# ================================
FROM debian:bookworm-20241016-slim AS runtime

# Install runtime dependencies
RUN apt-get update -y && \
    apt-get install -y \
    libstdc++6 \
    openssl \
    libncurses6 \
    locales \
    ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create app user
RUN useradd --create-home app
WORKDIR /home/app

# Set runner ENV
ENV MIX_ENV=prod

# Copy the release from build stage
COPY --from=build --chown=app:app /app/_build/${MIX_ENV}/rel/cerebelum_core ./

# Switch to app user
USER app

# Expose ports
# 4001 for HTTP API (if you add Phoenix later)
# 9090 for gRPC server
EXPOSE 4001 9090

# Start the application
CMD ["bin/cerebelum_core", "start"]

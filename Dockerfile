# ================================
# Build Stage
# ================================
FROM elixir:1.18-alpine AS build

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    curl

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
FROM elixir:1.18-alpine AS runtime

# Install runtime dependencies (most already included in elixir image)
RUN apk add --no-cache \
    openssl \
    ncurses-libs

# Create app user
RUN addgroup -g 1000 app && \
    adduser -D -u 1000 -G app app
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

#
# === Stage 1: The Build Stage ===
# This stage compiles the Elixir application and creates a self-contained release.
#
# FROM hexpm/elixir:1.16.1-erlang-26.2.2-alpine-3.18.4 AS build_stage
FROM hexpm/elixir:1.18.4-erlang-26.2.2-alpine-3.18.4 AS build_stage

# Set the environment to production
ENV MIX_ENV=prod

# Install a required package for Elixir (e.g., inotify-tools for Phoenix development)
# For a release, you may need other runtime dependencies like openssl
# RUN apk add --no-cache openssl

# Set the working directory
WORKDIR /app

# Copy dependency files first to leverage Docker layer caching
COPY mix.exs mix.lock ./
# (Optional for Phoenix) Copy assets package files
# COPY assets/package.json assets/package-lock.json ./assets/

# Install dependencies
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only $MIX_ENV

# Copy the rest of the application source code
COPY . .

# (Optional for Phoenix) Build static assets
# RUN npm install --prefix ./assets && \
#     npm run deploy --prefix ./assets && \
#     mix phx.digest

# Compile and create the Elixir release
RUN mix compile && \
    mix release

#
# === Stage 2: The Release (Runtime) Stage ===
# This stage takes the minimal Erlang runtime and copies only the compiled release
# from the build stage, significantly reducing the final image size.
#
FROM alpine:3.18.4 AS release_stage

# Install the Erlang/Elixir runtime dependencies (e.g., required by a release)
RUN apk add --no-cache bash openssl ncurses-libs iproute2

# Set the working directory
WORKDIR /app

# Set default operational environment variables
ENV LISTEN_IP=0.0.0.0
ENV LISTEN_PORT=8080
ENV LISTEN_IP_S2=0.0.0.0
ENV LISTEN_PORT_S2=42001

# Copy the compiled release from the build stage.
# Replace `your_app_name` with the actual name of your Elixir application (from mix.exs)
COPY --from=build_stage _build/prod/rel/data_diode/ ./

# Copy operational scripts from the build stage
COPY --from=build_stage /app/bin/*.sh ./bin/
RUN chmod +x ./bin/*.sh

# Define the command to run your Elixir release
CMD ["/app/bin/data_diode", "start"]

# Expose the application port (e.g., 4000 for Phoenix)
EXPOSE 8080
# Add healthcheck to monitor application status
# Checks if the data_diode process is running every 30 seconds
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD /app/bin/data_diode pid || exit 1

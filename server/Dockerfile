# ================================
# Build image
# ================================
FROM swift:6.4.0-noble@sha256:64bab762bc73a3fda6d9ebc559258bd6d7660c10a705bb25ecacad2f99d066f9 AS build

ARG SWIFT_JOBS=4

# Install OS updates
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y libjemalloc-dev

# Set up a build area
WORKDIR /build

# First just resolve dependencies.
# This creates a cached layer that can be reused
# as long as your Package.swift/Package.resolved
# files do not change.
COPY ./Package.* ./
RUN swift package resolve \
        $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

# Copy entire repo into container
COPY . .

RUN mkdir /staging

# Build Release with the matching dynamic Swift runtime and jemalloc.
# Static Swift linking fails in Foundation with the evaluated 6.4.0 Linux toolchain.
RUN --mount=type=cache,id=smartshoppinglist-vapor4-swift-6.4.0,target=/build/.build \
    swift build -c release --jobs "$SWIFT_JOBS" --force-resolved-versions \
        --product SmartShoppingListServer \
        -Xlinker -ljemalloc && \
    # Copy main executable to staging area
    cp "$(swift build -c release --show-bin-path)/SmartShoppingListServer" /staging && \
    # Copy resources bundled by SPM to staging area
    find -L "$(swift build -c release --show-bin-path)" -regex '.*\.resources$' -exec cp -Ra {} /staging \;


# Switch to the staging area
WORKDIR /staging

# Copy any resources from the public directory and views directory if the directories exist
# Ensure that by default, neither the directory nor any of its contents are writable.
RUN [ -d /build/Public ] && { mv /build/Public ./Public && chmod -R a-w ./Public; } || true
RUN [ -d /build/Resources ] && { mv /build/Resources ./Resources && chmod -R a-w ./Resources; } || true

# ================================
# Run image
# ================================
FROM swift:6.4.0-noble-slim@sha256:460e6eab278b1695fb4b04bc20c77c68dc6f0b4e422aa867e465d6805bc1eeca

# Make sure all system packages are up to date, and install only essential packages.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      curl \
    && rm -r /var/lib/apt/lists/*

# Create a vapor user and group with /app as its home directory
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

# Switch to the new home directory
WORKDIR /app

# Copy built executable and any staged resources from builder
COPY --from=build --chown=vapor:vapor /staging /app

# Provide configuration needed by the built-in crash reporter and some sensible default behaviors.
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no

# Ensure all further commands run as the vapor user
USER vapor:vapor

# Let Docker bind to port 8080
EXPOSE 8080

HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=5 \
    CMD curl --fail --silent http://127.0.0.1:8080/hello || exit 1

# Start the Vapor service when the image is run, default to listening on 8080 in production environment
ENTRYPOINT ["./SmartShoppingListServer"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]

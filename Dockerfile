# Multi-platform Dockerfile for Elkyn DB
# Supports linux/amd64 and linux/arm64

# Build stage - runs on native platform for speed
FROM --platform=$BUILDPLATFORM alpine:latest AS builder

# Install build dependencies
RUN apk add --no-cache \
    zig \
    lmdb-dev \
    musl-dev \
    linux-headers \
    pkgconfig

# Set build arguments for cross-compilation
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

WORKDIR /src
COPY . .

# Cross-compile Zig target from platform info
RUN set -ex; \
    case "$TARGETPLATFORM" in \
        "linux/amd64") ZIG_TARGET="x86_64-linux" ;; \
        "linux/arm64") ZIG_TARGET="aarch64-linux" ;; \
        *) echo "Unsupported platform: $TARGETPLATFORM" && exit 1 ;; \
    esac; \
    echo "Building for $TARGETPLATFORM with Zig target: $ZIG_TARGET"; \
    zig build -Dtarget=$ZIG_TARGET -Doptimize=ReleaseFast

# Final runtime image
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache lmdb

# Copy the binary
COPY --from=builder /src/zig-out/bin/elkyn-server /usr/local/bin/elkyn-server
COPY --from=builder /src/zig-out/bin/elkyn-db /usr/local/bin/elkyn-db

# Create data directory
RUN mkdir -p /data

# Expose default port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Default command
CMD ["elkyn-server", "8080", "/data"]
# syntax=docker/dockerfile:1
# check=skip=FromPlatformFlagConstDisallowed

# Named in vm/image/Dockerfile, which is where to change it; `just build-vm-agent` passes it on.
# There is no default, so a build that forgets it fails rather than using another Alpine's Rust.
ARG ALPINE_VERSION

# Builds icc-agent for the guest with the Rust the pinned Alpine release ships. Cargo.toml's
# rust-version and the committed Cargo.lock hold it to Rust 1.96, Alpine 3.24's. v86 emulates a
# 32-bit PC, so the platform is fixed rather than taken from the build.
FROM --platform=linux/386 alpine:${ALPINE_VERSION} AS build

RUN apk add --no-cache rust cargo

WORKDIR /src

# The dependencies get a layer of their own, so a change to the agent's source does not download
# them again. The empty main.rs only lets cargo read the manifest.
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && touch src/main.rs && cargo fetch --locked

# Static, so the agent needs nothing from the image but the kernel: Alpine links dynamically by
# default, and then the agent would depend on libgcc_s, which the image only has because other
# packages pull it in. Naming the host as --target keeps RUSTFLAGS off serde_derive, a proc-macro
# that cannot be linked statically.
COPY src ./src
RUN target=$(rustc -vV | sed -n 's/^host: //p') && \
    RUSTFLAGS="-C target-feature=+crt-static" cargo build --release --locked --offline --target "$target" && \
    cp "target/$target/release/icc-agent" /icc-agent

# The binary alone, at a path the image build copies it from.
FROM scratch
COPY --from=build /icc-agent /icc-agent

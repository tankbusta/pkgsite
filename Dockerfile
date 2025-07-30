# Build arguments for multi-architecture support
ARG TARGETPLATFORM
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH

FROM --platform=$BUILDPLATFORM golang:1.24 AS build

WORKDIR /go/src/app

RUN git clone --depth=1 https://github.com/golang/pkgsite.git . && \
    mkdir -p bin

ENV CGO_ENABLED=0

RUN GOBIN=/go/src/app/bin go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest

RUN go build -ldflags="-s -w" -o bin/frontend ./cmd/frontend/main.go && \
    go build -ldflags="-s -w" -o bin/seeddb ./devtools/cmd/seeddb/main.go && \
    go build -ldflags="-s -w" -o bin/db ./devtools/cmd/db/main.go

RUN rm -rf /go/src/app/.git

# Intermediate stage to prepare libraries for all architectures
FROM debian:bookworm-slim AS git-builder

RUN apt-get update && apt-get install git -y

RUN mv `git --exec-path` /git-exec

# Copy libraries for all supported architectures using ldd to discover dependencies
RUN mkdir -p /libs/x86_64-linux-gnu /libs/aarch64-linux-gnu /libs/arm-linux-gnueabihf && \
    # Use ldd to get library dependencies for git and git-remote-https
    for binary in /git-exec/git /git-exec/git-remote-http; do \
        if [ -f "$binary" ]; then \
            ldd "$binary" | grep "=>" | awk '{print $3}' | grep -v "not found" | while read lib; do \
                if [ -n "$lib" ] && [ -f "$lib" ]; then \
                    # Determine architecture from library path
                    if echo "$lib" | grep -q "x86_64-linux-gnu"; then \
                        cp "$lib" "/libs/x86_64-linux-gnu/$(basename "$lib")" 2>/dev/null || true; \
                    elif echo "$lib" | grep -q "aarch64-linux-gnu"; then \
                        cp "$lib" "/libs/aarch64-linux-gnu/$(basename "$lib")" 2>/dev/null || true; \
                    elif echo "$lib" | grep -q "arm-linux-gnueabihf"; then \
                        cp "$lib" "/libs/arm-linux-gnueabihf/$(basename "$lib")" 2>/dev/null || true; \
                    fi; \
                fi; \
            done; \
        fi; \
    done

FROM --platform=$TARGETPLATFORM gcr.io/distroless/base-debian12:debug

WORKDIR /app

COPY --from=build /go/src/app/ /app

# git sub programs
COPY --from=git-builder /git-exec /git-exec

ENV GIT_EXEC_PATH=/git-exec

COPY --from=git-builder /usr/share/git-core /usr/share/git-core

# Copy the prepared libraries from the intermediate stage
COPY --from=git-builder /libs/ /lib/

ENV PATH="${PATH}:/app/bin:/git-exec"

ENTRYPOINT ["frontend"]

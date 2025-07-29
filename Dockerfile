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

RUN apt-get update && apt-get install git

RUN mv `git --exec-path` /git-exec

RUN mv /usr/bin/git* ./bin

# Intermediate stage to prepare libraries for all architectures
FROM debian:bookworm-slim AS libs

# Copy libraries for all supported architectures
RUN mkdir -p /libs/lib/x86_64-linux-gnu /libs/lib/aarch64-linux-gnu /libs/lib/arm-linux-gnueabihf && \
    for lib in libcurl-gnutls.so.4 libpcre2-8.so.0 libz.so.1 libc.so.6 libnghttp2.so.14 libidn2.so.0 librtmp.so.1 libssh2.so.1 libpsl.so.5 libnettle.so.8 libgnutls.so.30 libgssapi_krb5.so.2 libldap-2.5.so.0 liblber-2.5.so.0 libzstd.so.1 libbrotlidec.so.1 libunistring.so.2 libhogweed.so.6 libgmp.so.10 libcrypto.so.3 libp11-kit.so.0 libtasn1.so.6 libkrb5.so.3 libk5crypto.so.3 libcom_err.so.2 libkrb5support.so.0 libsasl2.so.2 libbrotlicommon.so.1 libffi.so.8 libkeyutils.so.1 libresolv.so.2; do \
        if [ -f "/lib/x86_64-linux-gnu/$lib" ]; then \
            cp "/lib/x86_64-linux-gnu/$lib" "/libs/lib/x86_64-linux-gnu/"; \
        fi; \
        if [ -f "/lib/aarch64-linux-gnu/$lib" ]; then \
            cp "/lib/aarch64-linux-gnu/$lib" "/libs/lib/aarch64-linux-gnu/"; \
        fi; \
        if [ -f "/lib/arm-linux-gnueabihf/$lib" ]; then \
            cp "/lib/arm-linux-gnueabihf/$lib" "/libs/lib/arm-linux-gnueabihf/"; \
        fi; \
    done

FROM --platform=$TARGETPLATFORM gcr.io/distroless/base-debian12:debug

WORKDIR /app

COPY --from=build /go/src/app/ /app

# git sub programs
COPY --from=build /git-exec /git-exec

ENV GIT_EXEC_PATH=/git-exec

COPY --from=build /usr/share/git-core /usr/share/git-core

# Copy the prepared libraries from the intermediate stage
COPY --from=libs /libs/ /lib/

ENV PATH="${PATH}:/app/bin"

ENTRYPOINT ["frontend"]

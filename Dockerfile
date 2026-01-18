# syntax=docker/dockerfile:1

################################################################################
# Create a stage for building the application.
ARG GO_VERSION=1.24
FROM golang:${GO_VERSION} AS build
WORKDIR /src

# Copy source files instead of using bind mounts to ensure Go embed works correctly
COPY go.mod go.sum ./
RUN go mod download -x

# Copy entire source tree
COPY . .

ARG BUILD_TAGS=""
# Build the application with embedded webplatform
RUN export VERSION_PKG_PATH="go.autokitteh.dev/autokitteh/internal/version" && \
    export TIMESTAMP="$(date -u "+%Y-%m-%dT%H:%MZ")" && \
    export LDFLAGS="-X ${VERSION_PKG_PATH}.Version=$(cat .version || echo) -X ${VERSION_PKG_PATH}.Time=${TIMESTAMP} -X ${VERSION_PKG_PATH}.Commit=$(cat .commit || echo)" && \
    make webplatform && \
    CGO_ENABLED=0 go build -o /bin/ak -ldflags="${LDFLAGS}" -tags=${BUILD_TAGS} ./cmd/ak




################################################################################
# Create a new stage for running the application that contains the minimal
# runtime dependencies for the application.
FROM python:3.11-slim AS pydeps

RUN apt-get update && rm -rf /var/lib/apt/lists/*

WORKDIR /runner

COPY ./runtimes/pythonrt/runner/pyproject.toml pyproject.toml
RUN python -m pip install .[all]

COPY ./runtimes/pythonrt/py-sdk py-sdk
RUN cd py-sdk && python -m pip install .[all]

FROM python:3.11-slim AS final

# Create a non-privileged user 
# See https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#user
ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/home/appuser" \
    --shell "/sbin/nologin" \
    --uid "${UID}" \
    appuser
USER appuser

# Copy packages to user site-packages which is enabled in this image.
RUN mkdir -p /home/appuser/.local/lib/python3.11/
COPY --chown=appuser:appuser --from=pydeps /usr/local/lib/python3.11/site-packages /home/appuser/.local/lib/python3.11/site-packages

# Copy the executable from the "build" stage.
COPY --chown=appuser:appuser --from=build /bin/ak /bin/

ENV AK_WORKER_PYTHON=/usr/local/bin/python
# Expose the port that the application listens on.
EXPOSE 9980

ENTRYPOINT [ "/bin/ak" ]

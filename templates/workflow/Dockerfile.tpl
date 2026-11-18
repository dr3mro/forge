ARG DEPENDENCY_IMAGE=deps
FROM ubuntu:24.04 AS deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ca-certificates cmake curl git ninja-build pkg-config \
    python3 python3-venv tar unzip zip && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/forge-ci && /opt/forge-ci/bin/pip install --no-cache-dir conan==2.33.0
ENV PATH="/opt/forge-ci/bin:$PATH"
WORKDIR /project
COPY .github/forge/ci.py .github/forge/ci.py
COPY target/forge-ci-inputs/ target/forge-ci-inputs/
ARG CONFIG=Debug
RUN python .github/forge/ci.py deps --config "$CONFIG"

FROM ${DEPENDENCY_IMAGE} AS project
ARG CONFIG=Debug
ARG LEAK_CHECK=1
COPY . .
RUN python .github/forge/ci.py build --config "$CONFIG"
# Generated projects fail their image build on leaks by default. The workflow
# passes [build].leak_check from plan.json as LEAK_CHECK.
RUN if [ "$LEAK_CHECK" = "1" ]; then \
      curl -fsSL https://raw.githubusercontent.com/dr3mro/forge/refs/heads/main/install.sh | sh && \
      "$HOME/.local/bin/forge" leaks --all; \
    fi

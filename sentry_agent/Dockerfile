# SentryAgent — multi-purpose image.
#
# The same image is used for both the orchestrator (`sentry serve`) and the
# mock sensor publisher (`sentry mock`); docker-compose picks the command
# per-service.
#
# Build:   docker build -t sentry-agent .
# Run:     docker run --rm sentry-agent serve --broker-host host.docker.internal

FROM python:3.12-slim

# Don't write .pyc, flush stdout/stderr immediately (matters for `docker logs`).
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

# Copy only what `pip install .` needs first, so dep changes invalidate
# the cache but code-only changes don't.
COPY pyproject.toml README.md ./
COPY sentry ./sentry

RUN pip install .

# Default config — can be overridden by mounting one over /app/config.yaml.
COPY config.yaml ./

ENTRYPOINT ["sentry"]
CMD ["--help"]

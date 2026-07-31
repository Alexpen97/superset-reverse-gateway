# Extend the lean official image with metadata DB + OIDC deps (build-time).
# See https://superset.apache.org/user-docs/6.0.0/installation/docker-builds
FROM apache/superset:6.1.0

USER root

RUN . /app/.venv/bin/activate && \
    uv pip install --no-cache-dir \
      "authlib>=1.3.0,<1.6" \
      "psycopg2-binary>=2.9.9"

USER superset

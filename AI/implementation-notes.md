# Implementation notes — compose gateway + Keycloak stack

Status: Implemented on branch `feature/compose-gateway-keycloak`
Date: 2026-07-31

## Decisions (plan §11)

1. **Keycloak URL:** exposed on `127.0.0.1:8081`. Superset uses
   `extra_hosts: localhost:host-gateway` so browser and token exchange share
   `http://localhost:8081` (issuer match).
2. **Postgres:** single `postgres:16-alpine` with two DBs via `db/init-multiple-dbs.sh`.
3. **Superset:** custom image from `apache/superset:6.1.0` (`superset/Dockerfile`)
   installs `authlib` + `psycopg2-binary` at build time via `uv pip` (official
   lean-image pattern). `superset-init` one-shot service runs migrations/admin/init;
   the app container uses the image default entrypoint (no `bootstrap.sh`).
   `SUPERSET_APP_ROOT=/bi`.
4. **Redis/Celery:** deferred.
5. **Roles:** `AUTH_USER_REGISTRATION_ROLE = Gamma`; no Keycloak role sync yet.
   Claim mapping lives in `superset/keycloak_userinfo.py`.

## `/bi` strategy

Strategy A: gateway `Path=/bi/**` without `StripPrefix`; Superset owns `/bi`.

## Security

- Gateway image is vulhub (CVE-2022-22947); port bound to `127.0.0.1` only.
- `.env` is gitignored; `.env.example` has demo defaults.

## Verify

```bash
# Podman rootless (Fedora/Bazzite):
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock

make test    # unit tests for claim mapping
make up      # start stack
make smoke   # HTTP acceptance checks (includes /bi/login/keycloak -> Keycloak)
```

Manual SSO: open `http://demo.io/bi/login/` (run `make setup` first), login as `analyst` / `analyst` → **Admin**.

## Custom image + init (2026-07-31)

- Removed runtime `uv pip install` from a mounted `bootstrap.sh`.
- Compose builds `local/superset-bi:6.1.0`; `superset` depends on
  `superset-init` (`service_completed_successfully`).
- `make up` uses `docker compose up -d --build`.

## Notes from bring-up

- Portless URLs need gateway on **:80**. Rootless Podman requires
  `net.ipv4.ip_unprivileged_port_start=80` — applied by `make setup` (sudo).
- Single origin: `http://demo.io/bi` (Superset) + `http://demo.io/auth` (Keycloak
  via gateway, `KC_HTTP_RELATIVE_PATH=/auth`).
- `make setup` also maps `demo.io` → loopback in `/etc/hosts`.
- Demo registration role: **Admin**.
- **OIDC via loopback gateway (fixed):** Superset must not call `http://demo.io/auth`
  server-side (gateway binds 127.0.0.1 only → connection refused from containers).
  Browser authorize uses `demo.io/auth`; token/userinfo/jwks use `keycloak:8080/auth`
  via static `server_metadata` in `superset_config.py`.

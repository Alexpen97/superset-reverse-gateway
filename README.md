# Superset behind Spring Cloud Gateway + Keycloak

Local Docker Compose stack that serves **Apache Superset** under **`/bi`** through a
**Spring Cloud Gateway**, with **Keycloak** OIDC login and a shared **Postgres**.

```
http://demo.io/bi/    -> Gateway -> Superset
http://demo.io/auth/  -> Gateway -> Keycloak (admin / admin)
```

Demo Keycloak user: `analyst` / `analyst` (registers in Superset as **Admin**).

## Security warning

`vulhub/spring-cloud-gateway:3.1.0` is **intentionally vulnerable**
([CVE-2022-22947](https://tanzu.vmware.com/security/cve-2022-22947)).
The compose file binds the gateway to **loopback only**. Do not publish it on a
shared network. For real deployments, replace it with a patched gateway image.

## Quick start

```bash
# On Fedora/Podman (rootless), point Compose at the user socket:
export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock

make setup       # sudo once: /etc/hosts + allow rootless bind on port 80
make up
make verify
```

Open `http://demo.io/bi/login/` → Keycloak → `analyst` / `analyst`.

## Architecture decisions

See [`AI/architecture-plan.md`](AI/architecture-plan.md). Summary of resolved
open questions:

| Topic | Choice |
|-------|--------|
| `/bi` strategy | Strategy A — `SUPERSET_APP_ROOT=/bi`, gateway does **not** strip prefix |
| Keycloak URL | Same origin `http://demo.io/auth` via gateway |
| Postgres | One instance, two DBs (`superset`, `keycloak`) |
| Superset version | Custom image from `apache/superset:6.1.0` (`superset/Dockerfile`) |
| Redis/Celery | Deferred |
| Roles | Self-register as `Admin` (demo) |
| Hostnames | `demo.io` → loopback via `make setup` (also allows :80) |

## Layout

```
docker-compose.yml
gateway/application.yml
superset/Dockerfile              # Authlib + psycopg2 at build time
superset/superset_config.py
superset/keycloak_userinfo.py
keycloak/realm-export.json
db/init-multiple-dbs.sh
scripts/smoke.sh
```

`superset-init` (one-shot Compose service) runs `db upgrade`, creates the local
admin fallback, and `superset init`. The app container only starts the server.

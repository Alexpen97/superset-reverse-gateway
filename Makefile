.PHONY: env setup hosts up down logs ps verify smoke test restart reset

# Prefer Podman rootless socket when Docker Engine isn't running (Fedora/Bazzite).
ifeq ($(wildcard /run/user/$(shell id -u)/podman/podman.sock),)
else ifeq ($(DOCKER_HOST),)
export DOCKER_HOST=unix:///run/user/$(shell id -u)/podman/podman.sock
endif

env:
	@test -f .env || cp .env.example .env
	@echo ".env ready (edit secrets if needed)"

# sudo: map demo.io → loopback and allow rootless bind on :80
setup hosts:
	@bash scripts/install-hosts.sh

up: env
	@docker compose up -d || { \
	  echo; \
	  echo "If port 80 failed (rootless), run:  make setup   # sudo once"; \
	  echo "Then:  docker compose up -d"; \
	  exit 1; \
	}
	@echo "App:  http://$${BI_HOSTNAME:-demo.io}/bi/"
	@echo "Auth: http://$${BI_HOSTNAME:-demo.io}/auth/ (admin/admin)"
	@echo "Demo user: analyst / analyst (Admin)"

down:
	docker compose down

logs:
	docker compose logs -f --tail=200

ps:
	docker compose ps

restart:
	docker compose restart

reset:
	docker compose down -v

test:
	@python3 scripts/test_keycloak_userinfo.py

verify: test smoke

smoke:
	@bash scripts/smoke.sh

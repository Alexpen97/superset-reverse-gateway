"""Superset runtime config: /bi app root, proxy fix, Keycloak OIDC."""

import logging
import os
import sys
from pathlib import Path

from flask_appbuilder.security.manager import AUTH_OAUTH
from superset.security import SupersetSecurityManager

# Allow importing the pure helper when mounted beside this file
sys.path.insert(0, str(Path(__file__).resolve().parent))
from keycloak_userinfo import map_keycloak_userinfo  # noqa: E402

logger = logging.getLogger(__name__)

# --- Core ---
SECRET_KEY = os.environ["SUPERSET_SECRET_KEY"]
SQLALCHEMY_DATABASE_URI = (
    f"postgresql+psycopg2://{os.environ['SUPERSET_DB_USER']}:"
    f"{os.environ['SUPERSET_DB_PASSWORD']}@"
    f"{os.environ.get('SUPERSET_DB_HOST', 'postgres')}:"
    f"{os.environ.get('SUPERSET_DB_PORT', '5432')}/"
    f"{os.environ['SUPERSET_DB']}"
)

# Application root is owned by create_app(superset_app_root='/bi') via FLASK_APP.
# Keep APPLICATION_ROOT aligned for URL generation / static assets.
APPLICATION_ROOT = os.environ.get("SUPERSET_APP_ROOT", "/bi")
ENABLE_PROXY_FIX = True
PROXY_FIX_CONFIG = {"x_for": 1, "x_proto": 1, "x_host": 1, "x_port": 1, "x_prefix": 1}

# --- Auth: Keycloak OIDC via Flask-AppBuilder ---
AUTH_TYPE = AUTH_OAUTH
AUTH_USER_REGISTRATION = True
# Demo stack: Keycloak users land as Admin (highest built-in role).
AUTH_USER_REGISTRATION_ROLE = os.environ.get("AUTH_USER_REGISTRATION_ROLE", "Admin")
AUTH_ROLES_SYNC_AT_LOGIN = False

# Browser uses the public gateway URL (demo.io/auth).
# Server-side token/userinfo/discovery must use the in-network Keycloak service:
# the gateway binds loopback-only, so demo.io:80 via host-gateway is refused.
_keycloak_public = os.environ.get("KEYCLOAK_EXTERNAL_URL", "http://demo.io/auth").rstrip("/")
_keycloak_internal = os.environ.get(
    "KEYCLOAK_INTERNAL_URL", "http://keycloak:8080/auth"
).rstrip("/")
_realm = os.environ.get("KEYCLOAK_REALM", "bi")

# Static metadata: browser authorize stays on demo.io; every server-side URL is
# in-network. (Gateway is loopback-only, so demo.io:80 from the container fails.)
_OIDC = {
    "issuer": f"{_keycloak_public}/realms/{_realm}",
    "authorization_endpoint": (
        f"{_keycloak_public}/realms/{_realm}/protocol/openid-connect/auth"
    ),
    "token_endpoint": (
        f"{_keycloak_internal}/realms/{_realm}/protocol/openid-connect/token"
    ),
    "userinfo_endpoint": (
        f"{_keycloak_internal}/realms/{_realm}/protocol/openid-connect/userinfo"
    ),
    "jwks_uri": (
        f"{_keycloak_internal}/realms/{_realm}/protocol/openid-connect/certs"
    ),
}

OAUTH_PROVIDERS = [
    {
        "name": "keycloak",
        "icon": "fa-key",
        "token_key": "access_token",
        "remote_app": {
            "client_id": os.environ["KEYCLOAK_CLIENT_ID"],
            "client_secret": os.environ["KEYCLOAK_CLIENT_SECRET"],
            "server_metadata": _OIDC,
            "api_base_url": (
                f"{_keycloak_internal}/realms/{_realm}/protocol/openid-connect/"
            ),
            "access_token_url": _OIDC["token_endpoint"],
            "authorize_url": _OIDC["authorization_endpoint"],
            "jwks_uri": _OIDC["jwks_uri"],
            "client_kwargs": {"scope": "openid email profile"},
            "request_token_url": None,
        },
    }
]


class KeycloakSecurityManager(SupersetSecurityManager):
    """Map Keycloak userinfo claims onto Superset / FAB user fields."""

    def oauth_user_info(self, provider, response=None):
        if provider != "keycloak":
            return super().oauth_user_info(provider, response)

        remote = self.appbuilder.sm.oauth_remotes[provider]
        try:
            me = remote.get("userinfo")
            me.raise_for_status()
            data = me.json()
        except Exception:
            # Fallback to id_token / userinfo embedded in the token response
            logger.exception("Keycloak userinfo request failed; using token response")
            data = response or {}

        mapped = map_keycloak_userinfo(data)
        logger.debug("Keycloak userinfo for %s: %s", mapped["username"], data)
        return mapped


CUSTOM_SECURITY_MANAGER = KeycloakSecurityManager

"""Pure helpers for Keycloak -> Superset user mapping (unit-tested)."""

from __future__ import annotations

from typing import Any, Mapping


def map_keycloak_userinfo(data: Mapping[str, Any]) -> dict[str, str]:
    """Map OIDC userinfo / id_token claims to Flask-AppBuilder user fields."""
    username = data.get("preferred_username") or data.get("sub")
    if not username:
        raise ValueError("Keycloak userinfo missing preferred_username and sub")

    return {
        "username": str(username),
        "email": str(data.get("email") or f"{username}@example.local"),
        "first_name": str(data.get("given_name") or data.get("name") or username),
        "last_name": str(data.get("family_name") or ""),
    }

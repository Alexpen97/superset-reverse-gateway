#!/usr/bin/env python3
"""Unit tests for Keycloak claim mapping (no Docker / Superset required)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "superset"))

from keycloak_userinfo import map_keycloak_userinfo  # noqa: E402


class MapKeycloakUserinfoTests(unittest.TestCase):
    def test_preferred_username(self):
        mapped = map_keycloak_userinfo(
            {
                "preferred_username": "analyst",
                "email": "analyst@example.com",
                "given_name": "Ana",
                "family_name": "Lyst",
            }
        )
        self.assertEqual(
            mapped,
            {
                "username": "analyst",
                "email": "analyst@example.com",
                "first_name": "Ana",
                "last_name": "Lyst",
            },
        )

    def test_falls_back_to_sub_and_defaults(self):
        mapped = map_keycloak_userinfo({"sub": "abc-123", "name": "Pat"})
        self.assertEqual(mapped["username"], "abc-123")
        self.assertEqual(mapped["email"], "abc-123@example.local")
        self.assertEqual(mapped["first_name"], "Pat")
        self.assertEqual(mapped["last_name"], "")

    def test_missing_identity_raises(self):
        with self.assertRaises(ValueError):
            map_keycloak_userinfo({"email": "x@y.z"})


if __name__ == "__main__":
    raise SystemExit(unittest.main())

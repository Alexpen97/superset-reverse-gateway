#!/usr/bin/env python3
"""Sanity checks for the custom Superset image Dockerfile."""
from __future__ import annotations

import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
DOCKERFILE = ROOT / "superset" / "Dockerfile"
COMPOSE = ROOT / "docker-compose.yml"


class SupersetDockerfileTests(unittest.TestCase):
    def test_dockerfile_extends_pinned_lean_image(self) -> None:
        text = DOCKERFILE.read_text(encoding="utf-8")
        self.assertIn("FROM apache/superset:6.1.0", text)
        self.assertIn("uv pip install", text)
        self.assertIn("authlib", text.lower())
        self.assertIn("psycopg2-binary", text)
        self.assertIn("USER superset", text)

    def test_compose_builds_image_and_uses_init_service(self) -> None:
        text = COMPOSE.read_text(encoding="utf-8")
        self.assertIn("local/superset-bi:6.1.0", text)
        self.assertIn("superset-init:", text)
        self.assertIn("service_completed_successfully", text)
        self.assertNotIn("bootstrap.sh", text)
        self.assertIn("superset db upgrade", text)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)

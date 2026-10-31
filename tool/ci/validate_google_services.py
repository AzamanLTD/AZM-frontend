#!/usr/bin/env python3
"""Validate an Android google-services.json before the Gradle build.

The file carries API keys and OAuth client ids, so this script never prints the
document or any key material: it reports structural facts only (project id,
counts, package names) and fails with a specific reason.

A real configuration must name the expected Firebase project, contain exactly
one Android client for the expected package, and carry a Web OAuth client
(client_type 3). When the caller supplies the Web client id used by the Flutter
build, it must be one of those Web clients, otherwise Google id-token issuance
would silently target the wrong audience.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

PROJECT = "azaman-app"
PACKAGE = "com.azaman.app"


def fail(message: str) -> None:
    print(f"::error::{message}")
    sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", default="android/app/google-services.json")
    parser.add_argument("--package", default=PACKAGE)
    parser.add_argument(
        "--project",
        default="",
        help="Expected Firebase project id. Empty validates structure only.",
    )
    parser.add_argument(
        "--server-client-id",
        default="",
        help="Web OAuth client id passed to the Flutter build, when one is set.",
    )
    parser.add_argument("--label", default="firebase")
    args = parser.parse_args()

    path = Path(args.file)
    if not path.is_file() or path.stat().st_size == 0:
        fail(f"{args.label}: {path} is missing or empty")
    try:
        data = json.loads(path.read_text())
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        fail(f"{args.label}: {path} is not valid JSON ({exc.__class__.__name__})")
    if not isinstance(data, dict):
        fail(f"{args.label}: {path} is not a JSON object")

    project = str((data.get("project_info") or {}).get("project_id") or "")
    clients = data.get("client") or []
    if not isinstance(clients, list):
        fail(f"{args.label}: 'client' is not a list")

    android_packages = []
    web_clients = []
    for client in clients:
        if not isinstance(client, dict):
            continue
        info = (client.get("client_info") or {}).get("android_client_info") or {}
        package = info.get("package_name")
        if package:
            android_packages.append(str(package))
        for oauth in client.get("oauth_client") or []:
            if not isinstance(oauth, dict):
                continue
            if oauth.get("client_type") == 3 and oauth.get("client_id"):
                web_clients.append(str(oauth["client_id"]))

    matching = [p for p in android_packages if p == args.package]

    if args.project and project != args.project:
        fail(
            f"{args.label}: project_id is '{project or '(absent)'}', expected "
            f"'{args.project}'. Refusing to build against the wrong Firebase project."
        )
    # The project may legitimately register other packages (a retired
    # com.example.* app, an iOS-bridged Android app), so only OUR package is
    # constrained: it must be present exactly once. Two clients for the same
    # package would make the build's identity ambiguous.
    if len(matching) != 1:
        fail(
            f"{args.label}: expected exactly one Android client for "
            f"'{args.package}', found {len(matching)} "
            f"(all registered packages: {sorted(set(android_packages))})"
        )
    # A real configuration must carry the Web client that Google id-token
    # issuance needs. The CI placeholder is validated for structure and package
    # only, which is what --project distinguishes.
    if args.project and not web_clients:
        fail(
            f"{args.label}: no Web OAuth client (client_type 3). Google Sign-In on "
            "Android cannot issue a usable id token without it."
        )
    if args.server_client_id and args.server_client_id not in web_clients:
        fail(
            f"{args.label}: the configured Web client id is not one of the "
            f"client_type 3 clients in this configuration ({len(web_clients)} present). "
            "Refusing to compile a build whose Google Sign-In audience would not match."
        )

    print(
        f"{args.label}: project_id={project or '(absent)'} "
        f"android_clients={len(android_packages)} package={matching[0]} "
        f"web_clients={len(web_clients)} "
        f"server_client_id={'matched' if args.server_client_id else 'not supplied'}"
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Validate an Android google-services.json before the Gradle build.

The file carries API keys and OAuth client ids, so this script never prints the
document or any key material: it reports structural facts only (project id,
counts, package names) and fails with a specific reason.

A real configuration must name the expected Firebase project, contain exactly
one Android client for the expected package, and that Android app's own client
object must carry a Web OAuth client (client_type 3). When the caller supplies
the Web client id used by the Flutter build, it must be one of the Web clients
attached to OUR app, otherwise Google id-token issuance would silently target
the wrong audience.

Scoping matters: Firebase writes one client object per registered Android app,
and a project may still register a retired app (com.example.azaman here). A Web
client that exists only on that other object is not usable by our build, so the
check is deliberately per-app rather than a union across the document.
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
    android_client_ids = set()
    ios_client_ids = set()
    all_web_clients = set()
    # Web clients per owning Android app. "owner" is the package of the client
    # object that carries them, which is exactly the scoping Firebase means.
    web_clients_by_app: dict[str, list[str]] = {}
    matching = []
    for client in clients:
        if not isinstance(client, dict):
            continue
        info = (client.get("client_info") or {}).get("android_client_info") or {}
        package = str(info.get("package_name") or "")
        if package:
            android_packages.append(package)
            matching.append(package)
        own_web: list[str] = []
        for oauth in client.get("oauth_client") or []:
            if not isinstance(oauth, dict):
                continue
            oauth_id = str(oauth.get("client_id") or "")
            oauth_type = oauth.get("client_type")
            if not oauth_id:
                continue
            if oauth_type == 1:
                android_client_ids.add(oauth_id)
            elif oauth_type == 2:
                ios_client_ids.add(oauth_id)
            elif oauth_type == 3:
                own_web.append(oauth_id)
                all_web_clients.add(oauth_id)
        if own_web:
            web_clients_by_app.setdefault(package or "(package absent)", []).extend(own_web)

    matching = [p for p in matching if p == args.package]

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
    # Only the Web clients attached to OUR app can issue a usable id token for
    # it. A client listed under another registered app is not a fallback.
    web_clients = list(dict.fromkeys(web_clients_by_app.get(args.package, [])))
    elsewhere = {
        app: ids for app, ids in web_clients_by_app.items() if app != args.package
    }

    elsewhere_count = {i for ids in elsewhere.values() for i in ids} - set(web_clients)

    # A real configuration must carry the Web client that Google id-token
    # issuance needs. The CI placeholder is validated for structure and package
    # only, which is what --project distinguishes.
    if args.project and not web_clients and not args.server_client_id:
        if elsewhere:
            fail(
                f"{args.label}: no Web OAuth client (client_type 3) on the "
                f"'{args.package}' client. The configuration has {len(all_web_clients)} "
                f"Web client(s), but they belong to other registered apps "
                f"({', '.join(sorted(elsewhere))}). Google Sign-In on Android issues "
                "its id token through a Web client of the calling app."
            )
        fail(
            f"{args.label}: no Web OAuth client (client_type 3). Google Sign-In on "
            "Android cannot issue a usable id token without it."
        )
    if args.server_client_id and args.server_client_id not in web_clients:
        # Client ids are public identifiers (they ship inside every APK), so the
        # candidates are printed: they are the only way to pick the right value
        # without opening the console again. No key or secret is printed.
        supplied = args.server_client_id
        if supplied.startswith(("http://", "https://")):
            shape = (
                "it is a URL, not a client id. Firebase shows both on the same "
                "page; the build needs the client id (…apps.googleusercontent.com "
                "with a project-number prefix), not an authorised redirect URI"
            )
        elif supplied in all_web_clients:
            owners = sorted(
                app for app, ids in elsewhere.items() if supplied in ids
            )
            shape = (
                "it is the Web client of a different registered app in this "
                f"project ({', '.join(owners)}). A Web client only issues tokens "
                f"for the app it is attached to, so the '{args.package}' client "
                "needs its own"
            )
        elif supplied in android_client_ids:
            shape = (
                "it is this project's ANDROID client id (client_type 1). Android "
                "id-token issuance needs the WEB client id (client_type 3)"
            )
        elif supplied in ios_client_ids:
            shape = "it is an iOS client id (client_type 2), not the web client id"
        elif not all_web_clients:
            shape = (
                "the configuration carries no Web OAuth client (client_type 3), so "
                "id-token issuance has nothing to target"
            )
        elif not supplied.endswith(".apps.googleusercontent.com"):
            shape = "it does not have the shape of a Google OAuth client id"
        else:
            shape = (
                "it is shaped like a client id but belongs to a different OAuth "
                "client or a different project"
            )
        fail(
            f"{args.label}: the supplied Web client id cannot be used: {shape}. "
            f"The '{args.package}' client carries {len(web_clients)} client_type 3 "
            f"client(s) of its own: {web_clients}"
        )

    print(
        f"{args.label}: project_id={project or '(absent)'} "
        f"android_clients={len(android_packages)} package={matching[0]} "
        f"web_clients={len(web_clients)} "
        f"web_clients_elsewhere={len(elsewhere_count)} "
        f"server_client_id={'matched' if args.server_client_id else 'not supplied'}"
    )


if __name__ == "__main__":
    main()

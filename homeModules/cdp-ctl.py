"""Command-line control client for cdp-proxy."""

import argparse
import asyncio
import json
import sys

import aiohttp


class ControlError(Exception):
    """A control-plane request failed."""


async def request_control(base_url, command, upstream=None):
    paths = {
        "status": ("GET", "/control/status"),
        "pin": ("POST", "/control/pin"),
        "unpin": ("POST", "/control/unpin"),
        "probe": ("POST", "/control/probe"),
    }
    method, path = paths[command]
    payload = {"upstream": upstream} if command == "pin" else None
    async with aiohttp.ClientSession(trust_env=False) as session:
        async with session.request(method, base_url.rstrip("/") + path, json=payload) as response:
            try:
                body = await response.json()
            except (aiohttp.ContentTypeError, json.JSONDecodeError):
                body = {"error": await response.text()}
            if response.status >= 400:
                raise ControlError(body.get("error", f"HTTP {response.status}"))
            return body


def main():
    parser = argparse.ArgumentParser(description="Control a running CDP fallback proxy")
    parser.add_argument("--base-url", default="http://127.0.0.1:9224")
    parser.add_argument("--json", action="store_true", help="Emit compact machine-readable JSON")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status")
    pin_parser = subparsers.add_parser("pin")
    pin_parser.add_argument("upstream", help="Configured upstream URL or zero-based index")
    subparsers.add_parser("unpin")
    subparsers.add_parser("probe")
    args = parser.parse_args()
    try:
        result = asyncio.run(request_control(args.base_url, args.command, getattr(args, "upstream", None)))
    except (ControlError, aiohttp.ClientError, OSError) as error:
        if args.json:
            print(json.dumps({"error": str(error)}, separators=(",", ":")))
        else:
            print(f"cdp-ctl: {error}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result, separators=(",", ":")))
    else:
        print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

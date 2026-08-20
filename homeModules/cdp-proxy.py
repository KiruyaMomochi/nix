"""CDP fallback proxy and loopback-only control plane."""

import argparse
import asyncio
import ipaddress
import json
import sys

import aiohttp
from aiohttp import WSMsgType, web


class PinnedUpstreamUnavailable(Exception):
    """The explicitly selected upstream cannot currently be reached."""


def is_loopback_host(host):
    if host == "localhost":
        return True
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


async def probe_upstream(session, url, timeout):
    """Check if a CDP endpoint is reachable."""
    try:
        async with session.get(
            f"{url}/json/version", timeout=aiohttp.ClientTimeout(total=timeout)
        ) as response:
            return response.status == 200
    except Exception:
        return False


async def probe_all(app):
    return await asyncio.gather(
        *(probe_upstream(app["session"], url, app["probe_timeout"])
          for url in app["upstreams"])
    )


async def pick_upstream(app):
    """Pick a reachable upstream, refusing silent fallback when pinned."""
    pinned = app["pinned_upstream"]
    if pinned is not None:
        if await probe_upstream(app["session"], pinned, app["probe_timeout"]):
            return pinned
        raise PinnedUpstreamUnavailable

    for url in app["upstreams"]:
        if await probe_upstream(app["session"], url, app["probe_timeout"]):
            return url
    return app["local_url"]


def json_error(message, status):
    return web.json_response({"error": message}, status=status)


def control_allowed(request):
    return is_loopback_host(request.app["listen_host"])


async def control_status(request):
    if not control_allowed(request):
        return json_error("control plane requires a loopback listen host", 403)
    reachability = await probe_all(request.app)
    pinned = request.app["pinned_upstream"]
    selected = None
    if pinned is not None:
        if reachability[request.app["upstreams"].index(pinned)]:
            selected = pinned
    else:
        selected = next(
            (url for url, reachable in zip(request.app["upstreams"], reachability) if reachable),
            request.app["local_url"],
        )
    return web.json_response({
        "selected_upstream": selected,
        "upstreams": [
            {"index": index, "url": url, "reachable": reachable}
            for index, (url, reachable) in enumerate(zip(request.app["upstreams"], reachability))
        ],
        "pinned_upstream": pinned,
        "local_fallback": request.app["local_url"],
        "probe_timeout": request.app["probe_timeout"],
        "pin_failure_behavior": "return_502",
    })


async def parse_json(request):
    try:
        body = await request.json()
    except (json.JSONDecodeError, aiohttp.ContentTypeError, UnicodeDecodeError):
        return None
    return body if isinstance(body, dict) else None


async def control_pin(request):
    if not control_allowed(request):
        return json_error("control plane requires a loopback listen host", 403)
    body = await parse_json(request)
    value = body.get("upstream") if body else None
    upstreams = request.app["upstreams"]
    if isinstance(value, int) or (isinstance(value, str) and value.isdigit()):
        index = int(value)
        if index < 0 or index >= len(upstreams):
            return json_error("upstream is not configured", 400)
        resolved = upstreams[index]
    elif isinstance(value, str) and value in upstreams:
        resolved = value
    else:
        return json_error("upstream is not configured", 400)
    request.app["pinned_upstream"] = resolved
    return web.json_response({"pinned_upstream": resolved})


async def control_unpin(request):
    if not control_allowed(request):
        return json_error("control plane requires a loopback listen host", 403)
    request.app["pinned_upstream"] = None
    return web.json_response({"pinned_upstream": None})


async def control_probe(request):
    if not control_allowed(request):
        return json_error("control plane requires a loopback listen host", 403)
    reachability = await probe_all(request.app)
    return web.json_response({
        "upstreams": [
            {"index": index, "url": url, "reachable": reachable}
            for index, (url, reachable) in enumerate(zip(request.app["upstreams"], reachability))
        ]
    })


async def handle_http(request):
    """Proxy HTTP requests (CDP discovery endpoints)."""
    try:
        upstream = await pick_upstream(request.app)
    except PinnedUpstreamUnavailable:
        return json_error("pinned upstream is unreachable", 502)
    target = f"{upstream}{request.path_qs}"
    try:
        async with request.app["session"].request(
            request.method,
            target,
            headers={key: value for key, value in request.headers.items() if key.lower() != "host"},
            data=await request.read(),
            timeout=aiohttp.ClientTimeout(total=10),
        ) as response:
            body = await response.read()
            if request.path.startswith("/json") and response.content_type == "application/json":
                body = body.replace(
                    upstream.replace("http://", "").encode(),
                    f"127.0.0.1:{request.app['port']}".encode(),
                )
            return web.Response(body=body, status=response.status, content_type=response.content_type)
    except Exception:
        return json_error("upstream proxy request failed", 502)


async def handle_ws(request):
    """Proxy WebSocket connections (CDP debug sessions)."""
    try:
        upstream = await pick_upstream(request.app)
    except PinnedUpstreamUnavailable:
        return json_error("pinned upstream is unreachable", 502)
    ws_server = web.WebSocketResponse()
    await ws_server.prepare(request)
    try:
        ws_url = f"{upstream.replace('http://', 'ws://')}{request.path_qs}"
        async with request.app["session"].ws_connect(ws_url) as ws_client:
            async def forward(source, destination):
                async for message in source:
                    if message.type == WSMsgType.TEXT:
                        await destination.send_str(message.data)
                    elif message.type == WSMsgType.BINARY:
                        await destination.send_bytes(message.data)
                    elif message.type in (WSMsgType.CLOSE, WSMsgType.CLOSING, WSMsgType.CLOSED, WSMsgType.ERROR):
                        break
            await asyncio.gather(forward(ws_client, ws_server), forward(ws_server, ws_client))
    except Exception:
        pass
    finally:
        if not ws_server.closed:
            await ws_server.close()
    return ws_server


async def route_handler(request):
    if request.headers.get("Upgrade", "").lower() == "websocket" or request.path.startswith("/devtools/"):
        return await handle_ws(request)
    return await handle_http(request)


async def on_startup(app):
    app["session"] = aiohttp.ClientSession()


async def on_cleanup(app):
    await app["session"].close()


def create_app(upstreams, local_url, probe_timeout, port, listen_host="127.0.0.1"):
    app = web.Application()
    app["port"] = port
    app["upstreams"] = list(upstreams)
    app["local_url"] = local_url
    app["probe_timeout"] = probe_timeout
    app["listen_host"] = listen_host
    app["pinned_upstream"] = None
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    app.router.add_get("/control/status", control_status)
    app.router.add_post("/control/pin", control_pin)
    app.router.add_post("/control/unpin", control_unpin)
    app.router.add_post("/control/probe", control_probe)
    app.router.add_route("*", "/{path:.*}", route_handler)
    return app


def main():
    parser = argparse.ArgumentParser(description="CDP Fallback Proxy")
    parser.add_argument("--port", type=int, default=9224, help="Listen port")
    parser.add_argument("--host", default="127.0.0.1", help="Listen host")
    parser.add_argument("--upstream", action="append", default=[], help="CDP upstream URL (repeatable, probed in order)")
    parser.add_argument("--local", default="http://127.0.0.1:9222", help="Local headless CDP (last resort)")
    parser.add_argument("--probe-timeout", type=float, default=1.5, help="Probe timeout (seconds)")
    args = parser.parse_args()
    app = create_app(args.upstream, args.local, args.probe_timeout, args.port, args.host)
    print(f"CDP proxy listening on {args.host}:{args.port}", file=sys.stderr)
    web.run_app(app, host=args.host, port=args.port, print=None)


if __name__ == "__main__":
    main()

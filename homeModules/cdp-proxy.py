"""
CDP Fallback Proxy — tries laptop first, falls back to local headless.

Handles both HTTP (CDP discovery: /json/*) and WebSocket (debug sessions).
"""

import asyncio
import argparse
import sys

import aiohttp
from aiohttp import web, WSMsgType


async def probe_upstream(session: aiohttp.ClientSession, url: str, timeout: float) -> bool:
    """Check if a CDP endpoint is reachable."""
    try:
        async with session.get(
            f"{url}/json/version", timeout=aiohttp.ClientTimeout(total=timeout)
        ) as resp:
            return resp.status == 200
    except Exception:
        return False


async def pick_upstream(app: web.Application) -> str:
    """Pick the best available upstream."""
    session = app["session"]
    if await probe_upstream(session, app["laptop_url"], app["probe_timeout"]):
        return app["laptop_url"]
    return app["local_url"]


async def handle_http(request: web.Request) -> web.Response:
    """Proxy HTTP requests (CDP discovery endpoints)."""
    session = request.app["session"]
    upstream = await pick_upstream(request.app)
    target = f"{upstream}{request.path_qs}"

    try:
        async with session.request(
            request.method,
            target,
            headers={k: v for k, v in request.headers.items() if k.lower() != "host"},
            data=await request.read(),
            timeout=aiohttp.ClientTimeout(total=10),
        ) as resp:
            body = await resp.read()
            # Rewrite WebSocket URLs in /json responses to point to our proxy
            if request.path.startswith("/json") and resp.content_type == "application/json":
                body = body.replace(
                    upstream.replace("http://", "").encode(),
                    f"127.0.0.1:{request.app['port']}".encode(),
                )
            return web.Response(
                body=body,
                status=resp.status,
                content_type=resp.content_type,
            )
    except Exception as e:
        return web.Response(text=f"proxy error: {e}", status=502)


async def handle_ws(request: web.Request) -> web.WebSocketResponse:
    """Proxy WebSocket connections (CDP debug sessions)."""
    session = request.app["session"]
    upstream = await pick_upstream(request.app)
    ws_url = f"{upstream.replace('http://', 'ws://')}{request.path_qs}"

    ws_server = web.WebSocketResponse()
    await ws_server.prepare(request)

    try:
        async with session.ws_connect(ws_url) as ws_client:

            async def forward(src, dst):
                async for msg in src:
                    if msg.type == WSMsgType.TEXT:
                        await dst.send_str(msg.data)
                    elif msg.type == WSMsgType.BINARY:
                        await dst.send_bytes(msg.data)
                    elif msg.type in (WSMsgType.CLOSE, WSMsgType.CLOSING, WSMsgType.CLOSED):
                        break
                    elif msg.type == WSMsgType.ERROR:
                        break

            await asyncio.gather(
                forward(ws_client, ws_server),
                forward(ws_server, ws_client),
            )
    except Exception:
        pass
    finally:
        if not ws_server.closed:
            await ws_server.close()

    return ws_server


async def route_handler(request: web.Request):
    """Route based on whether it's a WS upgrade or plain HTTP."""
    if (
        request.headers.get("Upgrade", "").lower() == "websocket"
        or request.path.startswith("/devtools/")
    ):
        return await handle_ws(request)
    return await handle_http(request)


async def on_startup(app: web.Application):
    app["session"] = aiohttp.ClientSession()


async def on_cleanup(app: web.Application):
    await app["session"].close()


def main():
    parser = argparse.ArgumentParser(description="CDP Fallback Proxy")
    parser.add_argument("--port", type=int, default=9224, help="Listen port")
    parser.add_argument("--host", default="127.0.0.1", help="Listen host")
    parser.add_argument("--laptop", default="http://100.82.238.137:9222", help="Laptop CDP URL")
    parser.add_argument("--local", default="http://127.0.0.1:9222", help="Local headless CDP URL")
    parser.add_argument("--probe-timeout", type=float, default=1.5, help="Probe timeout (seconds)")
    args = parser.parse_args()

    app = web.Application()
    app["port"] = args.port
    app["laptop_url"] = args.laptop
    app["local_url"] = args.local
    app["probe_timeout"] = args.probe_timeout
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    app.router.add_route("*", "/{path:.*}", route_handler)

    print(f"CDP proxy listening on {args.host}:{args.port}", file=sys.stderr)
    print(f"  Laptop: {args.laptop}", file=sys.stderr)
    print(f"  Local:  {args.local}", file=sys.stderr)
    web.run_app(app, host=args.host, port=args.port, print=None)


if __name__ == "__main__":
    main()

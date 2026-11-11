"""CDP fallback proxy and loopback-only control plane."""

import argparse
import asyncio
import ipaddress
import json
import shlex
import sys
import time

import aiohttp
from aiohttp import WSMsgType, web


class PinnedUpstreamUnavailable(Exception):
    """The explicitly selected upstream cannot currently be reached."""


class NoUpstream(Exception):
    """Nothing is reachable and there is no local fallback."""


class TabJanitor:
    """Closes pages on one browser that nobody has driven through this proxy for a while.

    A page counts as used when a client sends it a command (page websocket, or a browser
    websocket session attached to it), when it gets opened/activated over /json, or when its
    url/title changes between scans, which also catches someone clicking around over VNC.
    Pages with an open page websocket are never closed, and neither is the last page left."""

    def __init__(self, upstream, idle_seconds, interval):
        self.upstream = upstream
        self.idle_seconds = idle_seconds
        self.interval = interval
        self.last_used = {}
        self.seen = {}
        self.open_sockets = {}
        self.session_targets = {}
        self.pending_attach = {}

    def touch(self, target_id):
        if target_id:
            self.last_used[target_id] = time.monotonic()

    def socket_opened(self, target_id):
        self.open_sockets[target_id] = self.open_sockets.get(target_id, 0) + 1
        self.touch(target_id)

    def socket_closed(self, target_id):
        self.touch(target_id)
        count = self.open_sockets.get(target_id, 0) - 1
        if count > 0:
            self.open_sockets[target_id] = count
        else:
            self.open_sockets.pop(target_id, None)

    def client_message(self, connection, text):
        """A command from a client on a browser-level websocket."""
        try:
            message = json.loads(text)
        except ValueError:
            return
        if not isinstance(message, dict):
            return
        session_id = message.get("sessionId")
        if session_id:
            self.touch(self.session_targets.get(session_id))
        params = message.get("params")
        target_id = params.get("targetId") if isinstance(params, dict) else None
        if isinstance(target_id, str):
            self.touch(target_id)
            if message.get("method") == "Target.attachToTarget" and "id" in message:
                self.pending_attach[(connection, message["id"])] = target_id

    def upstream_message(self, connection, text):
        """A reply or event from the browser on a browser-level websocket."""
        if "sessionId" not in text and "targetId" not in text:
            return
        try:
            message = json.loads(text)
        except ValueError:
            return
        if not isinstance(message, dict):
            return
        result = message.get("result")
        if isinstance(result, dict):
            target_id = self.pending_attach.pop((connection, message.get("id")), None)
            if target_id and result.get("sessionId"):
                self.session_targets[result["sessionId"]] = target_id
            if isinstance(result.get("targetId"), str):
                self.touch(result["targetId"])
        params = message.get("params")
        if message.get("method") == "Target.attachedToTarget" and isinstance(params, dict):
            info = params.get("targetInfo") or {}
            if params.get("sessionId") and info.get("targetId"):
                self.session_targets[params["sessionId"]] = info["targetId"]

    def connection_closed(self, connection):
        for key in [key for key in self.pending_attach if key[0] == connection]:
            del self.pending_attach[key]

    def json_request(self, path):
        for prefix in ("/json/activate/", "/json/close/"):
            if path.startswith(prefix):
                self.touch(path[len(prefix):])

    async def list_pages(self, session):
        async with session.get(f"{self.upstream}/json/list", timeout=aiohttp.ClientTimeout(total=5)) as response:
            targets = await response.json(content_type=None)
        return [t for t in targets if t.get("type") == "page" and not t.get("url", "").startswith("devtools://")]

    async def scan(self, session):
        """One pass: note changes, close what has been idle too long. Returns closed pages."""
        pages = await self.list_pages(session)
        now = time.monotonic()
        alive = set()
        for page in pages:
            target_id = page["id"]
            alive.add(target_id)
            state = (page.get("url"), page.get("title"))
            if self.seen.get(target_id) != state:
                self.seen[target_id] = state
                self.last_used[target_id] = now
        for table in (self.seen, self.last_used, self.open_sockets):
            for target_id in [t for t in table if t not in alive]:
                del table[target_id]
        for session_id in [s for s, t in self.session_targets.items() if t not in alive]:
            del self.session_targets[session_id]

        idle = [p for p in pages
                if p["id"] not in self.open_sockets
                and now - self.last_used.get(p["id"], now) >= self.idle_seconds]
        if len(idle) == len(pages) and idle:
            keep = max(idle, key=lambda p: self.last_used.get(p["id"], now))
            idle = [p for p in idle if p is not keep]
        closed = []
        for page in idle:
            try:
                async with session.get(f"{self.upstream}/json/close/{page['id']}",
                                       timeout=aiohttp.ClientTimeout(total=5)) as response:
                    if response.status == 200:
                        closed.append(page)
                        print(f"cdp-proxy: closed idle page {page.get('url')}", file=sys.stderr)
            except Exception:
                pass
        return closed

    def status(self):
        now = time.monotonic()
        return {
            "upstream": self.upstream,
            "idle_seconds": self.idle_seconds,
            "pages": [
                {"id": target_id, "url": url, "title": title,
                 "idle_seconds": int(now - self.last_used.get(target_id, now)),
                 "open_sockets": self.open_sockets.get(target_id, 0)}
                for target_id, (url, title) in self.seen.items()
            ],
        }

    async def run(self, session):
        while True:
            try:
                await self.scan(session)
            except Exception:
                pass
            await asyncio.sleep(self.interval)


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


async def first_reachable(app):
    for url in app["upstreams"]:
        if await probe_upstream(app["session"], url, app["probe_timeout"]):
            return url
    return None


async def wake_upstream(app):
    """Run the wake command once (concurrent callers share it), then wait for any upstream."""
    async with app["wake_lock"]:
        url = await first_reachable(app)
        if url is not None:
            return url
        print(f"cdp-proxy: no upstream reachable, running {app['wake_command']}", file=sys.stderr)
        process = await asyncio.create_subprocess_exec(*shlex.split(app["wake_command"]))
        await process.wait()
        deadline = time.monotonic() + app["wake_timeout"]
        while time.monotonic() < deadline:
            url = await first_reachable(app)
            if url is not None:
                return url
            await asyncio.sleep(0.5)
        return None


async def pick_upstream(app):
    """Pick a reachable upstream, refusing silent fallback when pinned.

    With nothing reachable: run the wake command if there is one, then fall back to the local
    browser if there is one. With neither, the caller gets a 502."""
    pinned = app["pinned_upstream"]
    if pinned is not None:
        if await probe_upstream(app["session"], pinned, app["probe_timeout"]):
            return pinned
        raise PinnedUpstreamUnavailable

    url = await first_reachable(app)
    if url is None and app["wake_command"]:
        url = await wake_upstream(app)
    if url is None:
        url = app["local_url"]
    if url is None:
        raise NoUpstream
    return url


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
        "wake_command": request.app["wake_command"],
        "probe_timeout": request.app["probe_timeout"],
        "pin_failure_behavior": "return_502",
        "janitor": request.app["janitor"].status() if request.app["janitor"] else None,
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
    except NoUpstream:
        return json_error("no upstream is reachable", 502)
    janitor = request.app["janitor"]
    if janitor and upstream == janitor.upstream:
        janitor.json_request(request.path)
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
    except NoUpstream:
        return json_error("no upstream is reachable", 502)
    janitor = request.app["janitor"]
    if janitor and upstream != janitor.upstream:
        janitor = None
    page_id = None
    if janitor and request.path.startswith("/devtools/page/"):
        page_id = request.path[len("/devtools/page/"):]
    connection = object()
    ws_server = web.WebSocketResponse()
    await ws_server.prepare(request)
    if page_id:
        janitor.socket_opened(page_id)
    try:
        ws_url = f"{upstream.replace('http://', 'ws://')}{request.path_qs}"
        async with request.app["session"].ws_connect(ws_url) as ws_client:
            async def forward(source, destination, from_client):
                async for message in source:
                    if message.type == WSMsgType.TEXT:
                        if janitor:
                            if page_id:
                                if from_client:
                                    janitor.touch(page_id)
                            elif from_client:
                                janitor.client_message(connection, message.data)
                            else:
                                janitor.upstream_message(connection, message.data)
                        await destination.send_str(message.data)
                    elif message.type == WSMsgType.BINARY:
                        await destination.send_bytes(message.data)
                    elif message.type in (WSMsgType.CLOSE, WSMsgType.CLOSING, WSMsgType.CLOSED, WSMsgType.ERROR):
                        break
            await asyncio.gather(forward(ws_client, ws_server, False), forward(ws_server, ws_client, True))
    except Exception:
        pass
    finally:
        if page_id:
            janitor.socket_closed(page_id)
        elif janitor:
            janitor.connection_closed(connection)
        if not ws_server.closed:
            await ws_server.close()
    return ws_server


async def route_handler(request):
    if request.headers.get("Upgrade", "").lower() == "websocket" or request.path.startswith("/devtools/"):
        return await handle_ws(request)
    return await handle_http(request)


async def on_startup(app):
    app["session"] = aiohttp.ClientSession()
    app["wake_lock"] = asyncio.Lock()
    if app["janitor"]:
        app["janitor_task"] = asyncio.create_task(app["janitor"].run(app["session"]))


async def on_cleanup(app):
    task = app.get("janitor_task")
    if task:
        task.cancel()
    await app["session"].close()


def create_app(upstreams, local_url, probe_timeout, port, listen_host="127.0.0.1",
               wake_command=None, wake_timeout=20.0, janitor=None):
    app = web.Application()
    app["port"] = port
    app["upstreams"] = list(upstreams)
    app["local_url"] = local_url or None
    app["probe_timeout"] = probe_timeout
    app["listen_host"] = listen_host
    app["pinned_upstream"] = None
    app["wake_command"] = wake_command or None
    app["wake_timeout"] = wake_timeout
    app["janitor"] = janitor
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
    parser.add_argument("--local", default="http://127.0.0.1:9222", help="Local headless CDP (last resort; empty string disables)")
    parser.add_argument("--probe-timeout", type=float, default=1.5, help="Probe timeout (seconds)")
    parser.add_argument("--wake-command", default="", help="Command to run when no upstream is reachable, before the local fallback")
    parser.add_argument("--wake-timeout", type=float, default=20.0, help="Seconds to wait for an upstream after the wake command")
    parser.add_argument("--janitor-upstream", default="", help="Upstream whose idle pages get closed")
    parser.add_argument("--janitor-idle", type=float, default=1800.0, help="Seconds a page may sit unused before it is closed")
    parser.add_argument("--janitor-interval", type=float, default=60.0, help="Seconds between janitor scans")
    args = parser.parse_args()
    janitor = None
    if args.janitor_upstream:
        janitor = TabJanitor(args.janitor_upstream, args.janitor_idle, args.janitor_interval)
    app = create_app(args.upstream, args.local, args.probe_timeout, args.port, args.host,
                     wake_command=args.wake_command, wake_timeout=args.wake_timeout, janitor=janitor)
    print(f"CDP proxy listening on {args.host}:{args.port}", file=sys.stderr)
    web.run_app(app, host=args.host, port=args.port, print=None)


if __name__ == "__main__":
    main()

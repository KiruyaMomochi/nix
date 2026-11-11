import asyncio
import importlib.util
import json
import pathlib
import unittest

import aiohttp
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer


MODULE_PATH = pathlib.Path(__file__).with_name("cdp-proxy.py")
SPEC = importlib.util.spec_from_file_location("cdp_proxy", MODULE_PATH)
cdp_proxy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cdp_proxy)


async def make_upstream(name):
    app = web.Application()

    async def version(_request):
        return web.json_response({"Browser": name})

    app.router.add_get("/json/version", version)
    server = TestServer(app)
    await server.start_server()
    return server


class ControlPlaneTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.first = await make_upstream("first")
        self.second = await make_upstream("second")
        self.proxy = TestClient(
            TestServer(
                cdp_proxy.create_app(
                    upstreams=[str(self.first.make_url("/")).rstrip("/"), str(self.second.make_url("/")).rstrip("/")],
                    local_url="http://127.0.0.1:9",
                    probe_timeout=0.1,
                    port=9224,
                    listen_host="127.0.0.1",
                )
            )
        )
        await self.proxy.start_server()

    async def asyncTearDown(self):
        await self.proxy.close()
        await self.first.close()
        await self.second.close()

    async def test_status_reports_effective_upstream_ordered_reachability_and_policy(self):
        response = await self.proxy.get("/control/status")

        self.assertEqual(response.status, 200)
        body = await response.json()
        self.assertEqual(body["selected_upstream"], str(self.first.make_url("/")).rstrip("/"))
        self.assertIsNone(body["pinned_upstream"])
        self.assertEqual(body["local_fallback"], "http://127.0.0.1:9")
        self.assertEqual(body["probe_timeout"], 0.1)
        self.assertEqual(body["pin_failure_behavior"], "return_502")
        self.assertEqual(
            body["upstreams"],
            [
                {"index": 0, "url": str(self.first.make_url("/")).rstrip("/"), "reachable": True},
                {"index": 1, "url": str(self.second.make_url("/")).rstrip("/"), "reachable": True},
            ],
        )

    async def test_pin_by_index_changes_cdp_target_and_unpin_restores_probe_order(self):
        pin_response = await self.proxy.post("/control/pin", json={"upstream": "1"})
        self.assertEqual(pin_response.status, 200)
        self.assertEqual((await pin_response.json())["pinned_upstream"], str(self.second.make_url("/")).rstrip("/"))

        pinned = await self.proxy.get("/json/version")
        self.assertEqual((await pinned.json())["Browser"], "second")

        unpin_response = await self.proxy.post("/control/unpin")
        self.assertEqual(unpin_response.status, 200)
        self.assertIsNone((await unpin_response.json())["pinned_upstream"])

        unpinned = await self.proxy.get("/json/version")
        self.assertEqual((await unpinned.json())["Browser"], "first")

    async def test_pin_accepts_configured_url_and_rejects_other_urls(self):
        configured = str(self.first.make_url("/")).rstrip("/")
        accepted = await self.proxy.post("/control/pin", json={"upstream": configured})
        self.assertEqual(accepted.status, 200)

        rejected = await self.proxy.post("/control/pin", json={"upstream": "http://example.com:9222"})
        self.assertEqual(rejected.status, 400)
        self.assertEqual((await rejected.json())["error"], "upstream is not configured")

    async def test_pinned_unreachable_upstream_returns_json_502_without_fallback(self):
        await self.proxy.post("/control/pin", json={"upstream": "0"})
        await self.first.close()

        response = await self.proxy.get("/json/version")

        self.assertEqual(response.status, 502)
        self.assertEqual((await response.json())["error"], "pinned upstream is unreachable")

    async def test_probe_returns_fresh_reachability_map(self):
        await self.second.close()

        response = await self.proxy.post("/control/probe")

        self.assertEqual(response.status, 200)
        body = await response.json()
        self.assertTrue(body["upstreams"][0]["reachable"])
        self.assertFalse(body["upstreams"][1]["reachable"])


class FakeBrowser:
    """Just enough of /json for the janitor: list and close."""

    def __init__(self, pages):
        self.pages = pages
        self.closed = []

    async def start(self):
        app = web.Application()

        async def version(_request):
            return web.json_response({"Browser": "fake"})

        async def listing(_request):
            return web.json_response(self.pages)

        async def close(request):
            target_id = request.match_info["id"]
            self.closed.append(target_id)
            self.pages = [p for p in self.pages if p["id"] != target_id]
            return web.Response(text="Target is closing")

        app.router.add_get("/json/version", version)
        app.router.add_get("/json/list", listing)
        app.router.add_get("/json/close/{id}", close)
        self.server = TestServer(app)
        await self.server.start_server()
        return str(self.server.make_url("/")).rstrip("/")


def page(target_id, url="https://example.com/", title="t"):
    return {"id": target_id, "type": "page", "url": url, "title": title}


class TabJanitorTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.browser = FakeBrowser([page("a"), page("b"), page("c")])
        url = await self.browser.start()
        self.janitor = cdp_proxy.TabJanitor(url, idle_seconds=100, interval=60)
        self.session = aiohttp.ClientSession()
        await self.janitor.scan(self.session)

    async def asyncTearDown(self):
        await self.session.close()
        await self.browser.server.close()

    def age(self, target_id, seconds):
        self.janitor.last_used[target_id] -= seconds

    async def test_closes_only_pages_idle_past_the_limit(self):
        self.age("a", 200)
        await self.janitor.scan(self.session)
        self.assertEqual(self.browser.closed, ["a"])

    async def test_url_change_counts_as_use(self):
        self.age("a", 200)
        self.browser.pages[0] = page("a", url="https://example.com/next")
        await self.janitor.scan(self.session)
        self.assertEqual(self.browser.closed, [])

    async def test_open_page_socket_keeps_page(self):
        self.janitor.socket_opened("a")
        self.age("a", 200)
        await self.janitor.scan(self.session)
        self.assertEqual(self.browser.closed, [])
        self.janitor.socket_closed("a")
        self.age("a", 200)
        await self.janitor.scan(self.session)
        self.assertEqual(self.browser.closed, ["a"])

    async def test_keeps_the_most_recent_page_when_all_are_idle(self):
        self.age("a", 300)
        self.age("b", 200)
        self.age("c", 400)
        await self.janitor.scan(self.session)
        self.assertEqual(sorted(self.browser.closed), ["a", "c"])

    async def test_browser_socket_session_commands_touch_their_page(self):
        conn = object()
        self.janitor.client_message(conn, json.dumps({"id": 1, "method": "Target.attachToTarget", "params": {"targetId": "a", "flatten": True}}))
        self.janitor.upstream_message(conn, json.dumps({"id": 1, "result": {"sessionId": "S1"}}))
        self.age("a", 200)
        self.janitor.client_message(conn, json.dumps({"id": 2, "sessionId": "S1", "method": "Runtime.evaluate", "params": {}}))
        await self.janitor.scan(self.session)
        self.assertEqual(self.browser.closed, [])

    async def test_auto_attached_sessions_are_mapped(self):
        conn = object()
        self.janitor.upstream_message(conn, json.dumps({"method": "Target.attachedToTarget", "params": {"sessionId": "S2", "targetInfo": {"targetId": "b"}}}))
        self.age("b", 200)
        self.janitor.client_message(conn, json.dumps({"id": 3, "sessionId": "S2", "method": "Page.navigate", "params": {}}))
        await self.janitor.scan(self.session)
        self.assertEqual(self.browser.closed, [])


class WakeTests(unittest.IsolatedAsyncioTestCase):
    async def test_runs_wake_command_then_uses_the_upstream_that_came_up(self):
        browser = FakeBrowser([])
        url = await browser.start()
        port = browser.server.port
        await browser.server.close()
        marker = pathlib.Path(self.id().replace(".", "_") + ".woke")
        app = cdp_proxy.create_app(
            upstreams=[url], local_url="", probe_timeout=0.2, port=9224,
            wake_command=f"touch {marker}", wake_timeout=5)
        client = TestClient(TestServer(app))
        await client.start_server()

        async def bring_back():
            while not marker.exists():
                await asyncio.sleep(0.05)
            async def version(_request):
                return web.json_response({"Browser": "woken"})

            again = web.Application()
            again.router.add_get("/json/version", version)
            server = TestServer(again, port=port)
            await server.start_server()
            return server

        try:
            revive = asyncio.create_task(bring_back())
            response = await client.get("/json/version")
            server = await revive
            self.assertEqual((await response.json())["Browser"], "woken")
            await server.close()
        finally:
            marker.unlink(missing_ok=True)
            await client.close()

    async def test_no_upstream_and_no_fallback_is_a_502(self):
        app = cdp_proxy.create_app(upstreams=["http://127.0.0.1:9"], local_url="", probe_timeout=0.1, port=9224)
        client = TestClient(TestServer(app))
        await client.start_server()
        try:
            response = await client.get("/json/version")
            self.assertEqual(response.status, 502)
            self.assertEqual((await response.json())["error"], "no upstream is reachable")
        finally:
            await client.close()


class ControlPlaneSecurityTests(unittest.IsolatedAsyncioTestCase):
    async def test_control_routes_are_refused_on_non_loopback_listener(self):
        app = cdp_proxy.create_app(
            upstreams=[],
            local_url="http://127.0.0.1:9",
            probe_timeout=0.1,
            port=9224,
            listen_host="0.0.0.0",
        )
        client = TestClient(TestServer(app))
        await client.start_server()
        try:
            response = await client.get("/control/status")
            self.assertEqual(response.status, 403)
            self.assertEqual((await response.json())["error"], "control plane requires a loopback listen host")
        finally:
            await client.close()


class CliTests(unittest.IsolatedAsyncioTestCase):
    async def test_client_session_ignores_proxy_environment(self):
        ctl_path = pathlib.Path(__file__).with_name("cdp-ctl.py")
        spec = importlib.util.spec_from_file_location("cdp_ctl", ctl_path)
        cdp_ctl = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cdp_ctl)

        captured = {}

        class FakeResponse:
            status = 200

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_args):
                return None

            async def json(self):
                return {"ok": True}

        class FakeSession:
            def __init__(self, **kwargs):
                captured.update(kwargs)

            async def __aenter__(self):
                return self

            async def __aexit__(self, *_args):
                return None

            def request(self, *_args, **_kwargs):
                return FakeResponse()

        original = cdp_ctl.aiohttp.ClientSession
        cdp_ctl.aiohttp.ClientSession = FakeSession
        try:
            result = await cdp_ctl.request_control("http://127.0.0.1:9224", "status")
        finally:
            cdp_ctl.aiohttp.ClientSession = original

        self.assertEqual(result, {"ok": True})
        self.assertIs(captured["trust_env"], False)


if __name__ == "__main__":
    unittest.main()

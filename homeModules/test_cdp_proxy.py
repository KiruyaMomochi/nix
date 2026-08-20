import importlib.util
import json
import pathlib
import unittest

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

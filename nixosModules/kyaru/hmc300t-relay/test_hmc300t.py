# /// script
# requires-python = ">=3.11"
# dependencies = ["pycryptodome"]
# ///
"""Unit and loopback tests for HMC300T protocol, relay, and CLI."""
import asyncio
import base64
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from protocol import (
    FACTORY_KEY,
    encode_frame,
    parse_frame,
    session_key_from_102,
    encrypt_command,
    decrypt_command,
    decode_status,
    build_command,
)
from controlled_relay import ControlledRelay
from Crypto.Cipher import AES
from Crypto.Util.Padding import pad


class ProtocolTest(unittest.TestCase):
    def test_build_command_swing_and_angle(self):
        on_frame = build_command(swing="on")
        self.assertEqual(len(on_frame), 84)
        self.assertEqual(on_frame[23], 0x04)
        self.assertEqual(on_frame[27], 0x01)
        self.assertEqual(on_frame[32], 0xC0)
        decoded = decode_status(base64.b64encode(on_frame).decode())
        self.assertTrue(decoded["length_valid"])
        self.assertTrue(decoded["checksum_valid"])
        self.assertEqual(decoded["class"], 0x65)

        fixed5 = build_command(angle=5)
        self.assertEqual(fixed5[31], 0x0B)
        self.assertEqual(fixed5[32], 0x40)

        temp24 = build_command(temp_c=24)
        self.assertEqual(temp24[18], 0x0C)
        self.assertEqual(temp24[19], 49)
        self.assertEqual(temp24[45], 0x01)

    def test_encrypt_decrypt_roundtrip(self):
        session_key = b"04f3aa6b8a1823af"
        key_b64 = base64.b64encode(AES.new(FACTORY_KEY, AES.MODE_ECB).encrypt(pad(session_key, 16))).decode()
        self.assertEqual(session_key_from_102(key_b64), session_key)
        raw = build_command(swing="off")
        enc = encrypt_command(raw, session_key)
        self.assertEqual(decrypt_command(enc, session_key), raw)


class ControlledRelayLoopbackTest(unittest.IsolatedAsyncioTestCase):
    async def test_alias_resolution_and_injection(self):
        session_key = b"b455ecc0377fd8a9"
        key_b64 = base64.b64encode(AES.new(FACTORY_KEY, AES.MODE_ECB).encrypt(pad(session_key, 16))).decode()
        devices = {
            "bedroom": {
                "ip": "127.0.0.1",
                "did": "86100c009005001000000040000000000001",
                "description": "Bedroom AC",
            }
        }
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            devices_file = tmp_path / "devices.json"
            devices_file.write_text(json.dumps(devices))

            async def handle_cloud(reader, writer):
                frame101 = await reader.readline()
                self.assertEqual(parse_frame(frame101)["id"], 101)
                writer.write(encode_frame({"id": 102, "key": key_b64}))
                await writer.drain()
                await reader.read(1024)
                writer.close()
                await writer.wait_closed()

            cloud = await asyncio.start_server(handle_cloud, "127.0.0.1", 0)
            cloud_port = cloud.sockets[0].getsockname()[1]

            relay = ControlledRelay("127.0.0.1", cloud_port, tmp_path / "logs", devices=devices)
            sock_path = tmp_path / "control.sock"
            ctrl = await relay.start_control(sock_path)
            front = await asyncio.start_server(relay.handle, "127.0.0.1", 0)
            front_port = front.sockets[0].getsockname()[1]

            try:
                dev_reader, dev_writer = await asyncio.open_connection("127.0.0.1", front_port)
                dev_writer.write(
                    encode_frame(
                        {
                            "id": 101,
                            "wid": "86100c009005001000000040000000000001",
                            "ver": "HMC300T.6.03.05.00",
                            "ProtVer": "215",
                        }
                    )
                )
                await dev_writer.drain()
                line102 = await dev_reader.readline()
                self.assertEqual(parse_frame(line102)["id"], 102)

                listed = await relay.request({"op": "list"})
                self.assertEqual(len(listed["sessions"]), 1)
                self.assertEqual(listed["sessions"][0]["alias"], "bedroom")
                self.assertTrue(listed["sessions"][0]["session_key_available"])

                # Preview via alias using CLI subprocess
                proc = await asyncio.create_subprocess_exec(
                    sys.executable,
                    str(Path(__file__).resolve().parent / "cli.py"),
                    "--socket",
                    str(sock_path),
                    "--devices-file",
                    str(devices_file),
                    "command",
                    "bedroom",
                    "--swing",
                    "on",
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, stderr = await asyncio.wait_for(proc.communicate(), 5)
                self.assertEqual(proc.returncode, 0, stderr.decode())
                preview = json.loads(stdout.decode())
                self.assertFalse(preview["sent"])
                self.assertEqual(preview["alias"], "bedroom")

                dev_writer.close()
                await dev_writer.wait_closed()
            finally:
                front.close()
                ctrl.close()
                cloud.close()
                await front.wait_closed()
                await ctrl.wait_closed()
                await cloud.wait_closed()
                for t in list(relay.tasks):
                    t.cancel()
                if relay.tasks:
                    await asyncio.gather(*list(relay.tasks), return_exceptions=True)
                relay.log.close()


if __name__ == "__main__":
    unittest.main()

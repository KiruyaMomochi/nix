#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pycryptodome"]
# ///
"""Transparent Hisense HMC300T cloud relay with Unix control socket."""
import argparse
import asyncio
from collections import deque
import datetime
import json
import os
from pathlib import Path
import secrets
import signal
import stat
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
from relay import Relay, timestamp
from protocol import (
    parse_frame,
    encode_frame,
    session_key_from_102,
    encrypt_command,
    decode_status,
)


def load_devices(devices_file):
    if not devices_file:
        return {}
    path = Path(devices_file)
    if not path.is_file():
        return {}
    return json.loads(path.read_text())


class ControlledRelay(Relay):
    def __init__(self, upstream_host, upstream_port, directory, devices=None):
        super().__init__(upstream_host, upstream_port, directory)
        self.active = {}
        self.devices = devices or {}

    def match_device(self, state):
        peer_ip = state["peer"][0] if isinstance(state.get("peer"), (list, tuple)) and state["peer"] else None
        did = state.get("did")
        for alias, info in self.devices.items():
            if did and info.get("did") == did:
                return alias, info
            if peer_ip and info.get("ip") == peer_ip:
                return alias, info
        return None, None

    def resolve_session(self, target):
        if target in self.active:
            return self.active[target]
        candidates = []
        dev = self.devices.get(target)
        for state in self.active.values():
            peer_ip = state["peer"][0] if isinstance(state.get("peer"), (list, tuple)) and state["peer"] else ""
            did = state.get("did") or ""
            alias, _ = self.match_device(state)
            if dev is not None:
                if (dev.get("did") and did == dev["did"]) or (dev.get("ip") and peer_ip == dev["ip"]):
                    candidates.append(state)
            elif (
                alias == target
                or peer_ip == target
                or (target.startswith(".") and peer_ip.endswith(target))
                or (len(target) >= 4 and did.endswith(target))
            ):
                candidates.append(state)
        if not candidates:
            raise KeyError(target)
        return candidates[-1]

    def observe(self, state, direction, data):
        buf = state["buffers"][direction] + data
        while b"\r\n" in buf:
            line, buf = buf.split(b"\r\n", 1)
            try:
                obj = parse_frame(line + b"\r\n")
                if direction == "client_to_cloud" and obj.get("id") == 101:
                    state["did"] = obj.get("wid")
                if direction == "cloud_to_client" and obj.get("id") == 102 and "key" in obj:
                    state["key"] = session_key_from_102(obj["key"])
                if obj.get("id") == 201 and isinstance(obj.get("seq"), int):
                    state["seen_seq"].add(obj["seq"])
                if direction == "client_to_cloud" and obj.get("id") in (901, 201, 202):
                    decoded = []
                    for status in obj.get("status", []):
                        if status.get("msgtype") == 102:
                            try:
                                decoded.append(decode_status(status["result"]))
                            except (ValueError, KeyError) as exc:
                                decoded.append({"error": str(exc)})
                    state["status_counter"] += 1
                    state["observations"].append({"at": timestamp(), "message": obj, "decoded": decoded})
            except Exception as exc:
                self.event(state["session"], "inspection_error", direction=direction, error=repr(exc))
        state["buffers"][direction] = buf
        if len(buf) > 1024 * 1024:
            state["inspection_overflow"] = True
            state["buffers"][direction] = buf[-65536:]

    def summary(self, state):
        alias, dev = self.match_device(state)
        latest_summary = None
        for obs in reversed(state["observations"]):
            if obs["message"].get("id") == 901:
                for dec in obs.get("decoded", []):
                    if "summary" in dec:
                        latest_summary = dec["summary"]
                        break
            if latest_summary is not None:
                break
        info = {k: state[k] for k in ("session", "peer", "did", "status_counter")}
        info["alias"] = alias
        if dev and dev.get("description"):
            info["description"] = dev["description"]
        info["session_key_available"] = state["key"] is not None
        if latest_summary is not None:
            info["latest"] = latest_summary
        return info

    async def start_control(self, path, mode=0o600, unlink_stale=False):
        path = Path(path)
        if path.exists():
            if unlink_stale and stat.S_ISSOCK(path.lstat().st_mode):
                path.unlink()
            else:
                raise FileExistsError(path)
        server = await asyncio.start_unix_server(self.control, str(path), limit=65536)
        os.chmod(path, mode)
        return server

    async def control(self, reader, writer):
        try:
            request = json.loads(await asyncio.wait_for(reader.readline(), 5))
            response = await self.request(request)
        except Exception as exc:
            response = {"error": str(exc), "sent": False}
        writer.write(json.dumps(response, separators=(",", ":")).encode() + b"\n")
        try:
            await writer.drain()
        finally:
            writer.close()
            await writer.wait_closed()

    async def request(self, req):
        op = req.get("op")
        if op == "list":
            return {"sessions": [self.summary(s) for s in self.active.values()]}
        state = self.resolve_session(req["session"])
        if op == "status":
            return self.summary(state) | {"observations": list(state["observations"])}
        if op not in ("query", "command"):
            raise ValueError("op must be list, status, query, or command")
        seq = req.get("seq", 0x70000000 + secrets.randbelow(0x0FFFFFFF))
        if not isinstance(seq, int) or isinstance(seq, bool) or not 0 <= seq <= 0x7FFFFFFF:
            raise ValueError("seq must be a nonnegative signed 32-bit integer")
        if seq in state["seen_seq"]:
            raise ValueError("sequence number already used on this session")
        if op == "query":
            message = {"id": 202, "seq": seq}
        else:
            if state["key"] is None:
                raise ValueError("No session key: observe the 102 handshake first")
            raw = bytes.fromhex(req["payload_hex"])
            message = {"id": 201, "seq": seq, "com": encrypt_command(raw, state["key"]), "cmdversion": 0}
        frame = encode_frame(message)
        result = {
            "sent": False,
            "session": state["session"],
            "alias": self.match_device(state)[0],
            "seq": seq,
            "message": message,
            "frame_hex": frame.hex(),
            "status_counter_before": state["status_counter"],
        }
        if req.get("commit") is not True:
            return result
        async with state["downstream_lock"]:
            if state["buffers"]["cloud_to_client"] or state.get("inspection_overflow"):
                raise ValueError("Refusing injection during a partial/unframed cloud message")
            if state["writer"].is_closing() or state["downstream_eof"]:
                raise ValueError("Session downstream is closed")
            state["seen_seq"].add(seq)
            state["writer"].write(frame)
            self.record(state, "cloud_to_client", frame, "injected")
            try:
                await state["writer"].drain()
            except Exception as exc:
                raise RuntimeError("Write attempted; outcome unknown; do not retry blindly") from exc
            result["sent"] = True
        return result

    def record(self, state, direction, data, source):
        offset = state["offsets"][direction]
        state["files"][direction].write(data)
        self.event(
            state["session"],
            "bytes",
            direction=direction,
            offset=offset,
            length=len(data),
            hex=data.hex(),
            source=source,
        )
        state["offsets"][direction] += len(data)

    async def handle(self, reader, writer):
        task = asyncio.current_task()
        self.tasks.add(task)
        sid = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex
        directions = ("client_to_cloud", "cloud_to_client")
        state = {
            "session": sid,
            "peer": writer.get_extra_info("peername"),
            "did": None,
            "writer": writer,
            "key": None,
            "buffers": {d: b"" for d in directions},
            "offsets": {d: 0 for d in directions},
            "files": {},
            "downstream_lock": asyncio.Lock(),
            "downstream_eof": False,
            "seen_seq": set(),
            "status_counter": 0,
            "observations": deque(maxlen=32),
        }
        remote_writer = None
        pumps = []
        self.event(sid, "accepted", peer=state["peer"], upstream=[self.upstream_host, self.upstream_port])
        try:
            for d in directions:
                state["files"][d] = (self.sessions / f"{sid}.{d}.bin").open("xb", buffering=0)
            remote_reader, remote_writer = await asyncio.wait_for(
                asyncio.open_connection(self.upstream_host, self.upstream_port), 15
            )
            self.active[sid] = state

            async def forward(source, destination, direction):
                while True:
                    data = await source.read(65536)
                    lock = state["downstream_lock"] if direction == "cloud_to_client" else asyncio.Lock()
                    async with lock:
                        if not data:
                            if direction == "cloud_to_client":
                                state["downstream_eof"] = True
                            self.event(sid, "eof", direction=direction)
                            if destination.can_write_eof():
                                destination.write_eof()
                                await destination.drain()
                            return
                        self.record(state, direction, data, "forwarded")
                        self.observe(state, direction, data)
                        destination.write(data)
                        await destination.drain()

            pumps = [
                asyncio.create_task(forward(reader, remote_writer, "client_to_cloud")),
                asyncio.create_task(forward(remote_reader, writer, "cloud_to_client")),
            ]
            await asyncio.gather(*pumps)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            self.event(sid, "error", error=repr(exc))
        finally:
            self.active.pop(sid, None)
            for p in pumps:
                p.cancel()
            if pumps:
                await asyncio.gather(*pumps, return_exceptions=True)
            for w in (writer, remote_writer):
                if w is not None:
                    w.close()
                    try:
                        await asyncio.wait_for(w.wait_closed(), 3)
                    except Exception:
                        pass
            for f in state["files"].values():
                f.close()
            self.event(sid, "closed")
            self.tasks.discard(task)


async def main(args):
    os.umask(0o077)
    devices = load_devices(args.devices_file)
    relay = ControlledRelay(args.upstream_host, args.upstream_port, args.log_dir, devices=devices)
    control = await relay.start_control(
        args.control_socket,
        mode=int(args.socket_mode, 8),
        unlink_stale=args.unlink_stale_socket,
    )
    frontend = await asyncio.start_server(relay.handle, args.listen_host, args.listen_port)
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        asyncio.get_running_loop().add_signal_handler(sig, stop.set)
    try:
        async with frontend, control:
            await stop.wait()
    finally:
        frontend.close()
        control.close()
        await frontend.wait_closed()
        await control.wait_closed()
        for task in list(relay.tasks):
            task.cancel()
        if relay.tasks:
            await asyncio.gather(*list(relay.tasks), return_exceptions=True)
        Path(args.control_socket).unlink(missing_ok=True)
        relay.log.close()


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--listen-host", default="127.0.0.1")
    p.add_argument("--listen-port", type=int, default=18088)
    p.add_argument("--upstream-host", default="220.243.139.234")
    p.add_argument("--upstream-port", type=int, default=8088)
    p.add_argument("--log-dir", default=str(Path(__file__).parent / "captures"))
    p.add_argument("--control-socket", default=str(Path(__file__).parent / "control.sock"))
    p.add_argument("--socket-mode", default="0600")
    p.add_argument("--unlink-stale-socket", action="store_true")
    p.add_argument("--devices-file", default=os.environ.get("HMC300T_DEVICES_FILE"))
    asyncio.run(main(p.parse_args()))

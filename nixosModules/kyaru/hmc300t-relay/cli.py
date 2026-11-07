#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["pycryptodome"]
# ///
"""HMC300T CLI for passive capture decoding, live status, and control injection."""
import argparse
import asyncio
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from protocol import parse_frame, decode_status, build_command


def default_socket_path():
    env_sock = os.environ.get("HMC300T_SOCKET")
    if env_sock:
        return Path(env_sock)
    run_sock = Path("/run/hmc300t-relay/control.sock")
    if run_sock.exists():
        return run_sock
    scratch_sock = Path("/home/yozakura/.hermes/cache/scratch/hmc300t/inject/control.sock")
    if scratch_sock.exists():
        return scratch_sock
    return run_sock


def load_devices(devices_file):
    path = Path(devices_file) if devices_file else None
    if path and path.is_file():
        return json.loads(path.read_text())
    return {}


def scan_capture(path):
    path = Path(path)
    data = path.read_bytes()
    result = {
        "path": str(path),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "counts": {},
        "invalid_signatures": 0,
        "mainboard_frames": 0,
        "invalid_mainboard_frames": 0,
        "heads": {},
        "lengths": {},
        "class_counts": {},
        "last_status": None,
        "last_reply": None,
        "trailing_partial_bytes": 0,
    }
    counts = Counter()
    heads = Counter()
    lengths = Counter()
    classes = Counter()
    lines = data.split(b"\r\n")
    result["trailing_partial_bytes"] = len(lines.pop())
    for index, line in enumerate(lines):
        if not line:
            continue
        try:
            obj = parse_frame(line + b"\r\n")
        except ValueError:
            result["invalid_signatures"] += 1
            continue
        counts[str(obj.get("id"))] += 1
        decoded = []
        for status in obj.get("status", []):
            if status.get("msgtype") != 102:
                continue
            result["mainboard_frames"] += 1
            try:
                item = decode_status(status["result"])
                if not item["checksum_valid"] or not item["length_valid"]:
                    result["invalid_mainboard_frames"] += 1
                heads[item["hex"][:32]] += 1
                lengths[str(item["length"])] += 1
                classes[f"0x{item['class']:02x}"] += 1
                decoded.append(item)
            except (ValueError, KeyError) as exc:
                result["invalid_mainboard_frames"] += 1
                decoded.append({"error": str(exc)})
        if obj.get("id") == 901 and decoded:
            result["last_status"] = {"frame_index": index, "message": obj, "decoded": decoded}
        if obj.get("id") == 201 and decoded:
            result["last_reply"] = {"frame_index": index, "message": obj, "decoded": decoded}
    result.update(
        counts=dict(counts),
        heads=dict(heads),
        lengths=dict(lengths),
        class_counts=dict(classes),
    )
    return result


async def rpc(path, request):
    reader, writer = await asyncio.open_unix_connection(str(path))
    try:
        writer.write(json.dumps(request).encode() + b"\n")
        await writer.drain()
        return json.loads(await asyncio.wait_for(reader.readline(), 10))
    finally:
        writer.close()
        await writer.wait_closed()


def resolve_target_client_side(sessions, target, devices):
    for s in sessions:
        if s.get("session") == target:
            return s["session"]
    matches = []
    dev = devices.get(target)
    for s in sessions:
        peer = s.get("peer") or []
        peer_ip = peer[0] if peer else ""
        did = s.get("did") or ""
        alias = s.get("alias")
        if dev is not None:
            if (dev.get("did") and did == dev["did"]) or (dev.get("ip") and peer_ip == dev["ip"]):
                matches.append(s["session"])
        elif (
            alias == target
            or peer_ip == target
            or (target.startswith(".") and peer_ip.endswith(target))
            or (len(target) >= 4 and did.endswith(target))
        ):
            matches.append(s["session"])
    if matches:
        return matches[-1]
    return target


def enrich_sessions(sessions, devices):
    for s in sessions:
        if s.get("alias"):
            continue
        peer = s.get("peer") or []
        peer_ip = peer[0] if peer else None
        did = s.get("did")
        for alias, info in devices.items():
            if (did and info.get("did") == did) or (peer_ip and info.get("ip") == peer_ip):
                s["alias"] = alias
                if info.get("description"):
                    s["description"] = info["description"]
                break
    return sessions


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--socket", type=Path, default=default_socket_path())
    p.add_argument("--devices-file", default=os.environ.get("HMC300T_DEVICES_FILE"))
    sub = p.add_subparsers(dest="op", required=True)
    scan = sub.add_parser("capture", help="Offline/passive decode; never sends to appliances")
    scan.add_argument("paths", nargs="+", type=Path)
    sub.add_parser("list")
    for op in ("status", "query", "command"):
        s = sub.add_parser(op)
        s.add_argument("session", help="Session ID, room alias, IP (.26), or DID suffix")
        if op in ("query", "command"):
            s.add_argument("--seq", type=int)
            s.add_argument(
                "--commit",
                action="store_true",
                help="Actually write to appliance; omitted means preview only",
            )
        if op == "command":
            s.add_argument("--payload-hex", help="Complete unpadded bus frame; checked length/checksum")
            s.add_argument("--power", choices=["on", "off"], help="Power state")
            s.add_argument("--mode", choices=["heat", "cool"], help="Operating mode (turns power on)")
            s.add_argument("--temp", type=int, help="Target temperature in Celsius (16..30)")
            s.add_argument("--swing", choices=["on", "off"], help="Vertical swing toggle")
            s.add_argument("--angle", type=int, choices=[1, 2, 3, 4, 5], help="Fixed vertical louver position (1..5)")
            s.add_argument(
                "--set",
                dest="overrides",
                action="append",
                default=[],
                metavar="OFFSET=VAL",
                help="Raw command byte override (e.g. 32=0xc0)",
            )
    args = p.parse_args()
    devices = load_devices(args.devices_file)
    if args.op == "capture":
        result = [scan_capture(path) for path in args.paths]
    else:
        try:
            target = getattr(args, "session", None)
            if target is not None:
                listed = asyncio.run(rpc(args.socket, {"op": "list"}))
                if "sessions" in listed:
                    target = resolve_target_client_side(listed["sessions"], target, devices)
            request = {"op": args.op}
            if target is not None:
                request["session"] = target
            if hasattr(args, "commit"):
                request["commit"] = args.commit
            if getattr(args, "seq", None) is not None:
                request["seq"] = args.seq
            if args.op == "command":
                if args.payload_hex:
                    request["payload_hex"] = args.payload_hex
                else:
                    overrides = {}
                    for item in args.overrides:
                        k, v = item.split("=", 1)
                        overrides[int(k, 0)] = int(v, 0)
                    if not any(
                        [
                            args.power,
                            args.mode,
                            args.temp is not None,
                            args.swing,
                            args.angle is not None,
                            overrides,
                        ]
                    ):
                        p.error(
                            "command requires --payload-hex or at least one of --power/--mode/--temp/--swing/--angle/--set"
                        )
                    request["payload_hex"] = build_command(
                        power=args.power,
                        mode=args.mode,
                        temp_c=args.temp,
                        swing=args.swing,
                        angle=args.angle,
                        overrides=overrides,
                    ).hex()
            result = asyncio.run(rpc(args.socket, request))
            if args.op == "list" and isinstance(result, dict) and "sessions" in result:
                enrich_sessions(result["sessions"], devices)
        except (OSError, asyncio.TimeoutError) as exc:
            p.exit(1, f"Control socket unavailable ({args.socket}): {exc}\n")
    print(json.dumps(result, indent=2))
    if isinstance(result, dict) and "error" in result:
        sys.exit(1)


if __name__ == "__main__":
    main()

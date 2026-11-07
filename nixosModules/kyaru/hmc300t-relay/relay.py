#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Byte-transparent Hisense cloud relay."""
import argparse
import asyncio
import datetime
import json
import os
from pathlib import Path
import signal
import time
import uuid


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


class Relay:
    def __init__(self, upstream_host, upstream_port, directory):
        self.upstream_host = upstream_host
        self.upstream_port = upstream_port
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.sessions = self.directory / "sessions"
        self.sessions.mkdir(exist_ok=True, mode=0o700)
        self.log = (self.directory / "relay.log").open("a", buffering=1)
        self.tasks = set()

    def event(self, session, event, **fields):
        record = dict(
            timestamp=timestamp(),
            monotonic_ns=time.monotonic_ns(),
            session=session,
            event=event,
            **fields,
        )
        self.log.write(json.dumps(record, ensure_ascii=True) + "\n")

    async def handle(self, reader, writer):
        task = asyncio.current_task()
        self.tasks.add(task)
        sid = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S") + "-" + uuid.uuid4().hex
        remote_writer = None
        pumps = []
        files = {}
        self.event(
            sid,
            "accepted",
            peer=writer.get_extra_info("peername"),
            local=writer.get_extra_info("sockname"),
            upstream=[self.upstream_host, self.upstream_port],
        )
        try:
            for direction in ("client_to_cloud", "cloud_to_client"):
                files[direction] = (self.sessions / f"{sid}.{direction}.bin").open("xb", buffering=0)
            remote_reader, remote_writer = await asyncio.wait_for(
                asyncio.open_connection(self.upstream_host, self.upstream_port), 15
            )
            self.event(
                sid,
                "upstream_connected",
                peer=remote_writer.get_extra_info("peername"),
                local=remote_writer.get_extra_info("sockname"),
            )

            async def pipe(source, destination, direction):
                offset = 0
                while True:
                    data = await source.read(65536)
                    if not data:
                        self.event(sid, "eof", direction=direction, bytes=offset)
                        if destination.can_write_eof():
                            destination.write_eof()
                            await destination.drain()
                        return
                    files[direction].write(data)
                    self.event(
                        sid,
                        "bytes",
                        direction=direction,
                        offset=offset,
                        length=len(data),
                        hex=data.hex(),
                    )
                    destination.write(data)
                    await destination.drain()
                    self.event(sid, "forwarded", direction=direction, offset=offset, length=len(data))
                    offset += len(data)

            pumps = [
                asyncio.create_task(pipe(reader, remote_writer, "client_to_cloud")),
                asyncio.create_task(pipe(remote_reader, writer, "cloud_to_client")),
            ]
            await asyncio.gather(*pumps)
        except asyncio.CancelledError:
            self.event(sid, "cancelled")
            raise
        except Exception as exc:
            self.event(sid, "error", error=repr(exc))
        finally:
            for pump in pumps:
                if not pump.done():
                    pump.cancel()
            if pumps:
                await asyncio.gather(*pumps, return_exceptions=True)
            for output in (remote_writer, writer):
                if output is not None:
                    output.close()
                    try:
                        await asyncio.wait_for(output.wait_closed(), 3)
                    except Exception:
                        pass
            for file in files.values():
                file.close()
            self.event(sid, "closed")
            self.tasks.discard(task)


async def main(args):
    os.umask(0o077)
    relay = Relay(args.upstream_host, args.upstream_port, args.log_dir)
    stop = asyncio.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        asyncio.get_running_loop().add_signal_handler(sig, stop.set)
    server = await asyncio.start_server(relay.handle, args.listen_host, args.listen_port)
    relay.event(None, "listening", sockets=[s.getsockname() for s in server.sockets])
    try:
        async with server:
            await stop.wait()
    finally:
        server.close()
        await server.wait_closed()
        for task in list(relay.tasks):
            task.cancel()
        if relay.tasks:
            await asyncio.gather(*list(relay.tasks), return_exceptions=True)
        relay.event(None, "stopped")
        relay.log.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listen-host", default="127.0.0.1")
    parser.add_argument("--listen-port", type=int, default=8088)
    parser.add_argument("--upstream-host", default="220.243.139.234")
    parser.add_argument("--upstream-port", type=int, default=8088)
    parser.add_argument("--log-dir", default=str(Path(__file__).parent))
    asyncio.run(main(parser.parse_args()))

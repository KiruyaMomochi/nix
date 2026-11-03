"""
Redfish BMC source for hardware poller.

Polls /Thermal, /Power and /LogServices from a Supermicro (or compatible) BMC.

Three requests per cycle. Walking /Sensors one GET per sensor (~40 req/min)
wedged the Supermicro Redfish service into 503 every week or two.
"""

import logging
import os
import re
import socket
import warnings
from datetime import datetime

warnings.filterwarnings("ignore", message="Unverified HTTPS request")

import requests
from requests.adapters import HTTPAdapter

log = logging.getLogger("hardware-poller.redfish")

# --- Network interface binding ---
class InterfaceAdapter(HTTPAdapter):
    """Bind requests to a specific network interface via SO_BINDTODEVICE."""

    def __init__(self, interface: str, **kwargs):
        self.interface = interface
        super().__init__(**kwargs)

    def init_poolmanager(self, *args, **kwargs):
        import urllib3.util.connection

        interface = self.interface
        _orig_create = urllib3.util.connection.create_connection

        def _create_bound(address, *a, **kw):
            sock = _orig_create(address, *a, **kw)
            try:
                sock.setsockopt(
                    socket.SOL_SOCKET,
                    socket.SO_BINDTODEVICE,
                    interface.encode(),
                )
            except OSError as e:
                log.warning(f"SO_BINDTODEVICE failed: {e}")
            return sock

        urllib3.util.connection.create_connection = _create_bound
        super().init_poolmanager(*args, **kwargs)
        urllib3.util.connection.create_connection = _orig_create


METRIC_NAMES = {
    "Temperature": "redfish.temperature.celsius",
    "Voltage": "redfish.voltage.volts",
    "Current": "redfish.current.amperes",
    "Power": "redfish.power.watts",
    "Rotational": "redfish.fan.rpm",
}

UNITS = {
    "Temperature": "Cel",
    "Voltage": "V",
    "Current": "A",
    "Power": "W",
    "Rotational": "RPM",
}

STATE_FILE = "/var/lib/hardware-poller/redfish_last_event_id"


class RedfishSource:
    """Redfish BMC sensor and event log source."""

    def setup(self, config: dict, session_state: dict, credentials: dict[str, str]):
        """Initialize Redfish session and discover sensors."""
        password = credentials.get("bmc_password")
        if not password:
            raise ValueError("Missing required credential: bmc_password")
        
        session = requests.Session()
        session.auth = (config["username"], password)
        session.verify = False
        session.trust_env = False  # No proxy
        
        interface = config.get("interface")
        if interface:
            adapter = InterfaceAdapter(interface)
            session.mount("https://", adapter)
            session.mount("http://", adapter)
        
        # Load last event ID
        last_event_id = 0
        try:
            if os.path.isfile(STATE_FILE):
                with open(STATE_FILE) as f:
                    last_event_id = int(f.read().strip())
        except (ValueError, OSError):
            pass
        
        session_state["last_event_id"] = last_event_id
        log.info(f"Event log cursor: starting after id {last_event_id}")
        
        return {
            "session": session,
            "config": config,
            "session_state": session_state,
        }

    # (collection, array, value key, ReadingType as /Sensors reports it)
    ARRAYS = [
        ("Thermal", "Temperatures", "ReadingCelsius", "Temperature"),
        ("Thermal", "Fans", "Reading", "Rotational"),
        ("Power", "Voltages", "ReadingVolts", "Voltage"),
    ]

    def poll(self, context: dict) -> list[tuple[str, float, dict[str, str], str]]:
        """Read Thermal and Power, return metric readings."""
        session = context["session"]
        cfg = context["config"]
        base = f"{cfg['bmc_url']}/redfish/v1/Chassis/{cfg['chassis_id']}"

        docs = {}
        for collection in ("Thermal", "Power"):
            try:
                resp = session.get(f"{base}/{collection}", timeout=15)
                resp.raise_for_status()
                docs[collection] = resp.json()
            except Exception as e:
                log.warning(f"Failed to read {collection}: {e}")

        readings = []
        for collection, array, key, reading_type in self.ARRAYS:
            for item in docs.get(collection, {}).get(array, []):
                reading = item.get(key)
                if reading is None:
                    continue
                name = item.get("Name", "")
                status = item.get("Status", {})
                readings.append((
                    METRIC_NAMES[reading_type],
                    float(reading),
                    {
                        # same Id the /Sensors collection used, keeps old series continuous
                        "sensor.id": name.replace(" ", ""),
                        "sensor.name": name,
                        "sensor.reading_type": reading_type,
                        "sensor.health": status.get("Health", "Unknown"),
                        "sensor.state": status.get("State", "Unknown"),
                        "chassis.id": cfg["chassis_id"],
                    },
                    UNITS[reading_type],
                ))
        return readings

    def poll_logs(self, context: dict) -> list[tuple[str, str, dict[str, str], int | None]]:
        """Poll BMC event log for new entries."""
        session = context["session"]
        cfg = context["config"]
        session_state = context["session_state"]
        last_id = session_state["last_event_id"]
        
        # Ids are sequential; ask only for what is new. The trailing slash avoids a 301.
        url = f"{cfg['bmc_url']}/redfish/v1/Systems/1/LogServices/Log1/Entries/"
        try:
            resp = session.get(url, params={"$skip": str(last_id)}, timeout=15)
            resp.raise_for_status()
            data = resp.json()
        except Exception as e:
            log.warning(f"Failed to fetch event log: {e}")
            return []
        
        log_entries = []
        new_last_id = last_id
        
        for entry in data.get("Members", []):
            entry_id = int(entry.get("Id", "0"))
            if entry_id <= last_id:
                continue
            
            severity_text = entry.get("Severity", "OK")
            message = entry.get("Message", "")
            created = entry.get("Created", "")
            message_id = entry.get("MessageId", "")
            
            # Parse BMC timestamp
            timestamp_ns = None
            if created:
                try:
                    dt = datetime.fromisoformat(created)
                    timestamp_ns = int(dt.timestamp() * 1_000_000_000)
                except (ValueError, OSError):
                    pass
            
            # Extract category from message prefix like [SA-0003]
            category = ""
            cat_match = re.match(r"\[([A-Z]+-\d+)\]", message)
            if cat_match:
                category = cat_match.group(1).rsplit("-", 1)[0]
            
            log_entries.append((
                message,
                severity_text,
                {
                    "event.id": str(entry_id),
                    "event.created": created,
                    "event.message_id": message_id,
                    "event.category": category,
                    "event.source": "redfish.bmc",
                    "chassis.id": cfg["chassis_id"],
                },
                timestamp_ns,
            ))
            
            new_last_id = max(new_last_id, entry_id)
        
        if new_last_id > last_id:
            count = new_last_id - last_id
            log.info(f"Emitted {count} new BMC event(s) (id {last_id+1}..{new_last_id})")
            session_state["last_event_id"] = new_last_id
            # Persist to disk
            os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
            with open(STATE_FILE, "w") as f:
                f.write(str(new_last_id))
        
        return log_entries

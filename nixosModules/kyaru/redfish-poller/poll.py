"""
Redfish BMC sensor poller → OTLP metrics.

Polls /Sensors from a Supermicro (or compatible) BMC and exports
OpenTelemetry gauge metrics to a local collector.

Config: JSON file passed via --config.
Password: read from systemd credential at /run/credentials/<unit>/bmc_password.
"""

import argparse
import json
import logging
import os
import socket
import sys
import time
import warnings

warnings.filterwarnings("ignore", message="Unverified HTTPS request")

import requests
from requests.adapters import HTTPAdapter

from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk._logs import LoggerProvider, LogRecord
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry._logs import set_logger_provider, SeverityNumber

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("redfish-poller")


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


# --- Metric name mapping ---
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


def load_password() -> str:
    """Read password from systemd LoadCredential or environment fallback."""
    # systemd credential path
    cred_dir = os.environ.get("CREDENTIALS_DIRECTORY", "/run/credentials/redfish-poller.service")
    cred_path = os.path.join(cred_dir, "bmc_password")

    if os.path.isfile(cred_path):
        with open(cred_path) as f:
            return f.read().strip()

    # Fallback for development/testing
    password = os.environ.get("BMC_PASSWORD", "")
    if password:
        return password

    log.error("No BMC password found (checked credential file and BMC_PASSWORD env)")
    sys.exit(1)


def setup_otlp(cfg: dict) -> metrics.Meter:
    """Configure OTLP metric and log exporters."""
    resource = Resource.create({
        "host.name": cfg["host_name"],
        "service.name": "redfish-poller",
    })
    # Metrics
    exporter = OTLPMetricExporter(
        endpoint=f"{cfg['otlp_endpoint']}/v1/metrics",
    )
    reader = PeriodicExportingMetricReader(
        exporter,
        export_interval_millis=cfg["interval"] * 1000,
    )
    provider = MeterProvider(resource=resource, metric_readers=[reader])
    metrics.set_meter_provider(provider)

    # Logs
    log_exporter = OTLPLogExporter(
        endpoint=f"{cfg['otlp_endpoint']}/v1/logs",
    )
    logger_provider = LoggerProvider(resource=resource)
    logger_provider.add_log_record_processor(BatchLogRecordProcessor(log_exporter))
    set_logger_provider(logger_provider)

    return metrics.get_meter("redfish-poller", "1.0.0")


def create_session(cfg: dict, password: str) -> requests.Session:
    """Create a requests session with auth and optional interface binding."""
    session = requests.Session()
    session.auth = (cfg["username"], password)
    session.verify = False
    session.trust_env = False  # No proxy

    interface = cfg.get("interface")
    if interface:
        adapter = InterfaceAdapter(interface)
        session.mount("https://", adapter)
        session.mount("http://", adapter)

    return session


def discover_sensors(session: requests.Session, cfg: dict) -> list[str]:
    """Get list of sensor URIs from the BMC."""
    url = f"{cfg['bmc_url']}/redfish/v1/Chassis/{cfg['chassis_id']}/Sensors"
    resp = session.get(url, timeout=10)
    resp.raise_for_status()
    data = resp.json()
    return [m["@odata.id"] for m in data.get("Members", [])]


def poll_sensor(session: requests.Session, base_url: str, uri: str) -> dict | None:
    """Fetch a single sensor reading."""
    try:
        resp = session.get(f"{base_url}{uri}", timeout=10)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        log.warning(f"Failed to read {uri}: {e}")
        return None


def poll_all(session: requests.Session, cfg: dict, sensor_uris: list[str], gauges: dict):
    """Poll all sensors and record metrics."""
    for uri in sensor_uris:
        data = poll_sensor(session, cfg["bmc_url"], uri)
        if data is None:
            continue

        reading = data.get("Reading")
        if reading is None:
            continue

        reading_type = data.get("ReadingType", "")
        sensor_id = data.get("Id", uri.split("/")[-1])
        sensor_name = data.get("Name", sensor_id)
        status_health = data.get("Status", {}).get("Health", "Unknown")
        status_state = data.get("Status", {}).get("State", "Unknown")

        metric_name = METRIC_NAMES.get(reading_type, "redfish.sensor.reading")
        unit = UNITS.get(reading_type, "")

        if metric_name not in gauges:
            gauges[metric_name] = metrics.get_meter_provider().get_meter(
                "redfish-poller"
            ).create_gauge(
                name=metric_name,
                unit=unit,
                description=f"Redfish {reading_type or 'sensor'} reading",
            )

        gauges[metric_name].set(
            float(reading),
            attributes={
                "sensor.id": sensor_id,
                "sensor.name": sensor_name,
                "sensor.reading_type": reading_type,
                "sensor.health": status_health,
                "sensor.state": status_state,
                "chassis.id": cfg["chassis_id"],
            },
        )


# --- Event Log Polling ---

SEVERITY_MAP = {
    "OK": SeverityNumber.INFO,
    "Warning": SeverityNumber.WARN,
    "Critical": SeverityNumber.ERROR,
}

STATE_FILE = "/var/lib/redfish-poller/last_event_id"


def load_last_event_id() -> int:
    """Load the last seen event ID from state file."""
    try:
        if os.path.isfile(STATE_FILE):
            with open(STATE_FILE) as f:
                return int(f.read().strip())
    except (ValueError, OSError):
        pass
    return 0


def save_last_event_id(event_id: int):
    """Persist the last seen event ID."""
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        f.write(str(event_id))


def poll_event_log(session: requests.Session, cfg: dict, last_id: int) -> int:
    """Poll BMC event log for new entries, emit as OTLP logs. Returns new last_id."""
    url = f"{cfg['bmc_url']}/redfish/v1/Systems/1/LogServices/Log1/Entries"
    try:
        resp = session.get(url, timeout=15)
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:
        log.warning(f"Failed to fetch event log: {e}")
        return last_id

    from opentelemetry._logs import get_logger_provider

    logger = get_logger_provider().get_logger("redfish-events")
    new_last_id = last_id

    for entry in data.get("Members", []):
        entry_id = int(entry.get("Id", "0"))
        if entry_id <= last_id:
            continue

        severity_text = entry.get("Severity", "OK")
        severity_number = SEVERITY_MAP.get(severity_text, SeverityNumber.INFO)
        message = entry.get("Message", "")
        created = entry.get("Created", "")
        message_id = entry.get("MessageId", "")

        logger.emit(LogRecord(
            body=message,
            severity_text=severity_text,
            severity_number=severity_number,
            span_id=0,
            trace_id=0,
            trace_flags=0,
            attributes={
                "event.id": str(entry_id),
                "event.created": created,
                "event.message_id": message_id,
                "event.source": "redfish.bmc",
                "chassis.id": cfg["chassis_id"],
            },
        ))

        new_last_id = max(new_last_id, entry_id)

    if new_last_id > last_id:
        count = new_last_id - last_id
        log.info(f"Emitted {count} new BMC event(s) (id {last_id+1}..{new_last_id})")
        save_last_event_id(new_last_id)

    return new_last_id


def main():
    parser = argparse.ArgumentParser(description="Redfish BMC sensor poller")
    parser.add_argument("--config", required=True, help="JSON config file path")
    parser.add_argument("--once", action="store_true", help="Poll once and exit")
    args = parser.parse_args()

    with open(args.config) as f:
        cfg = json.load(f)

    password = load_password()

    log.info(f"Redfish poller: {cfg['bmc_url']} via {cfg.get('interface', 'default')}")
    log.info(f"OTLP → {cfg['otlp_endpoint']}, interval {cfg['interval']}s")

    setup_otlp(cfg)
    session = create_session(cfg, password)
    gauges: dict = {}

    log.info("Discovering sensors...")
    sensor_uris = discover_sensors(session, cfg)
    log.info(f"Found {len(sensor_uris)} sensors")

    # Load last seen event ID (for incremental event log polling)
    last_event_id = load_last_event_id()
    log.info(f"Event log cursor: starting after id {last_event_id}")

    if args.once:
        poll_all(session, cfg, sensor_uris, gauges)
        last_event_id = poll_event_log(session, cfg, last_event_id)
        log.info("Single poll complete")
        time.sleep(5)
        metrics.get_meter_provider().shutdown()
        from opentelemetry._logs import get_logger_provider
        get_logger_provider().shutdown()
        return

    rediscovery_counter = 0
    while True:
        try:
            poll_all(session, cfg, sensor_uris, gauges)
            last_event_id = poll_event_log(session, cfg, last_event_id)
            log.info(f"Polled {len(sensor_uris)} sensors")

            rediscovery_counter += 1
            if rediscovery_counter >= 10:
                sensor_uris = discover_sensors(session, cfg)
                rediscovery_counter = 0

        except Exception as e:
            log.error(f"Poll cycle failed: {e}")
            try:
                session = create_session(cfg, password)
                sensor_uris = discover_sensors(session, cfg)
            except Exception as e2:
                log.error(f"Recovery failed: {e2}")

        time.sleep(cfg["interval"])


if __name__ == "__main__":
    main()

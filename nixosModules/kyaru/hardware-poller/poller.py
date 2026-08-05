"""
Generic hardware metrics poller framework → OTLP.

Provides common infrastructure for polling hardware metrics from various
sources (Redfish BMC, SMART disk health, etc.) and pushing to OTLP endpoints.

Each source implements a simple interface:
  - setup(config, session_state) -> context
  - poll(context) -> list of (metric_name, value, attributes, unit)
  - poll_logs(context) -> list of (body, severity, attributes, timestamp_ns)

The framework handles:
  - OTLP exporter setup (metrics + logs)
  - Config loading (JSON + systemd credentials)
  - Main loop with error recovery
  - Graceful shutdown
"""

import argparse
import json
import logging
import os
import sys
import time
from typing import Any, Protocol

from opentelemetry import metrics
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry._logs import LogRecord
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry._logs import set_logger_provider, get_logger_provider

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("hardware-poller")


class Source(Protocol):
    """Protocol that hardware sources must implement."""
    
    def setup(self, config: dict, session_state: dict, credentials: dict[str, str]) -> Any:
        """
        Initialize the source. Returns source-specific context object.
        credentials: dict of credential_name -> value (pre-loaded by framework)
        """
        ...
    
    def poll(self, context: Any) -> list[tuple[str, float, dict[str, str], str]]:
        """
        Poll metrics from the hardware source.
        Returns: list of (metric_name, value, attributes, unit)
        """
        ...
    
    def poll_logs(self, context: Any) -> list[tuple[str, str, dict[str, str], int | None]]:
        """
        Poll log events from the hardware source (optional).
        Returns: list of (body, severity_text, attributes, timestamp_ns)
        Empty list if source doesn't emit logs.
        """
        ...


def load_credential(name: str, fallback_env: str | None = None) -> str:
    """Load a credential from systemd LoadCredential or environment fallback."""
    cred_dir = os.environ.get("CREDENTIALS_DIRECTORY")
    if cred_dir:
        cred_path = os.path.join(cred_dir, name)
        if os.path.isfile(cred_path):
            with open(cred_path) as f:
                return f.read().strip()
    
    if fallback_env and (value := os.environ.get(fallback_env)):
        return value
    
    log.error(f"Credential '{name}' not found (checked systemd + env {fallback_env})")
    sys.exit(1)


def setup_otlp(cfg: dict) -> metrics.Meter:
    """Configure OTLP metric and log exporters."""
    resource = Resource.create({
        "host.name": cfg["host_name"],
        "service.name": cfg["service_name"],
    })
    
    # Metrics
    exporter = OTLPMetricExporter(
        endpoint=f"{cfg['otlp_endpoint']}/v1/metrics",
    )
    # Export interval defaults to 60s; can be overridden via exportInterval config key
    export_interval_ms = cfg.get("exportInterval", 60) * 1000
    reader = PeriodicExportingMetricReader(
        exporter,
        export_interval_millis=export_interval_ms,
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
    
    return metrics.get_meter(cfg["service_name"], "1.0.0")


def run_poller(source: Source, config_path: str, once: bool = False):
    """Main poller loop."""
    with open(config_path) as f:
        cfg = json.load(f)
    
    log.info(f"Hardware poller ({cfg['source_type']}): {cfg.get('description', 'no description')}")
    log.info(f"OTLP → {cfg['otlp_endpoint']}, interval {cfg['interval']}s")
    
    meter = setup_otlp(cfg)
    gauges: dict[str, Any] = {}
    
    # Load credentials specified in config
    credentials = {}
    for cred_name in cfg.get("credentials", []):
        credentials[cred_name] = load_credential(cred_name)
    
    # Source setup
    session_state = {}
    try:
        context = source.setup(cfg, session_state, credentials)
    except Exception as e:
        log.error(f"Source setup failed: {e}")
        sys.exit(1)
    
    def poll_cycle():
        """Single poll iteration."""
        # Metrics
        try:
            readings = source.poll(context)
            for metric_name, value, attributes, unit in readings:
                if metric_name not in gauges:
                    gauges[metric_name] = meter.create_gauge(
                        name=metric_name,
                        unit=unit,
                        description=f"Hardware metric: {metric_name}",
                    )
                gauges[metric_name].set(value, attributes=attributes)
            if readings:
                log.info(f"Collected {len(readings)} reading(s)")
            else:
                log.warning("Poll returned no readings")
        except Exception as e:
            log.error(f"Metric poll failed: {e}", exc_info=True)
        
        # Logs (optional)
        try:
            log_entries = source.poll_logs(context)
            if log_entries:
                logger = get_logger_provider().get_logger(cfg["source_type"])
                for body, severity_text, attributes, timestamp_ns in log_entries:
                    from opentelemetry._logs import SeverityNumber
                    severity_map = {
                        "OK": SeverityNumber.INFO,
                        "INFO": SeverityNumber.INFO,
                        "Warning": SeverityNumber.WARN,
                        "WARN": SeverityNumber.WARN,
                        "Critical": SeverityNumber.ERROR,
                        "ERROR": SeverityNumber.ERROR,
                    }
                    severity_number = severity_map.get(severity_text, SeverityNumber.INFO)
                    
                    logger.emit(LogRecord(
                        body=body,
                        severity_text=severity_text,
                        severity_number=severity_number,
                        timestamp=timestamp_ns,
                        span_id=0,
                        trace_id=0,
                        trace_flags=0,
                        attributes=attributes,
                    ))
        except Exception as e:
            log.error(f"Log poll failed: {e}", exc_info=True)
    
    if once:
        poll_cycle()
        log.info("Single poll complete")
        time.sleep(5)
        metrics.get_meter_provider().shutdown()
        get_logger_provider().shutdown()
        return
    
    # Continuous polling
    while True:
        try:
            poll_cycle()
            log.info(f"Poll cycle complete")
        except Exception as e:
            log.error(f"Poll cycle error: {e}", exc_info=True)
            # Try to recover context
            try:
                context = source.setup(cfg, session_state, credentials)
            except Exception as e2:
                log.error(f"Recovery failed: {e2}")
        
        time.sleep(cfg["interval"])


def main():
    parser = argparse.ArgumentParser(description="Hardware metrics poller → OTLP")
    parser.add_argument("--config", required=True, help="JSON config file")
    parser.add_argument("--source", required=True, help="Source module (redfish, smart)")
    parser.add_argument("--once", action="store_true", help="Poll once and exit")
    args = parser.parse_args()
    
    # Dynamically import source module
    if args.source == "redfish":
        from source_redfish import RedfishSource
        source = RedfishSource()
    elif args.source == "smart":
        from source_smart import SmartSource
        source = SmartSource()
    else:
        log.error(f"Unknown source: {args.source}")
        sys.exit(1)
    
    run_poller(source, args.config, args.once)


if __name__ == "__main__":
    main()

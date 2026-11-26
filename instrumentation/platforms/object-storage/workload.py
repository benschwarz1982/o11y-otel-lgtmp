#!/usr/bin/env python3
"""
This system's (4015 Filestorage) actual live workload - Terraform
reads this file directly (fleet-4015-filestorage/main.tf's file())
and applies it as this pod's ConfigMap. Uploads/downloads/lists/
deletes small blobs on a loop against a real Azure Blob Storage
account, and emits its own telemetry about those operations (there's
no built-in OTel instrumentation for the Azure SDK, so spans/metrics/
logs are created directly here). The storage account itself is real;
only the traffic driving it is synthetic - see README.md in this
directory for why a generic Azure Storage Account template looks
different.
"""
import logging
import os
import random
import time
import uuid

from azure.storage.blob import BlobServiceClient
from opentelemetry import metrics, trace
from opentelemetry._logs import set_logger_provider
from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

OTLP_ENDPOINT = os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"]
TENANT_ID = os.environ.get("TENANT_ID", "4015-prod")
HEADERS = {"tenant_id": TENANT_ID}


# schema/core.yaml's Core Schema - platform.type is static per this
# platform template, doesn't vary per tenant.
resource = Resource.create({
    "service.name": "filestorage-demo",
    "service.namespace": "filestorage-demo",
    "platform.type": "object-storage",
})

trace.set_tracer_provider(TracerProvider(resource=resource))
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(OTLPSpanExporter(endpoint=f"{OTLP_ENDPOINT}/v1/traces", headers=HEADERS))
)
tracer = trace.get_tracer("filestorage-demo")

metrics.set_meter_provider(
    MeterProvider(
        resource=resource,
        metric_readers=[
            PeriodicExportingMetricReader(
                OTLPMetricExporter(endpoint=f"{OTLP_ENDPOINT}/v1/metrics", headers=HEADERS),
                export_interval_millis=15000,
            )
        ],
    )
)
meter = metrics.get_meter("filestorage-demo")
operations_counter = meter.create_counter("storage.operations", description="Blob storage operations performed")
bytes_histogram = meter.create_histogram("storage.operation.bytes", unit="By", description="Bytes transferred per operation")
# Current total container size/object count, updated on every "list" cycle
# below - not a per-operation counter/histogram like the two above, a
# snapshot gauge of what's actually in the container right now. Lets the
# dashboard show live storage growth (and its daily rate, for anomaly
# detection) - blobs are only ever added here, never deleted, so this is
# expected to trend upward over time.
storage_bytes_gauge = meter.create_gauge("storage.container.bytes", unit="By", description="Total bytes currently stored in the container")
storage_blob_count_gauge = meter.create_gauge("storage.container.blob_count", description="Total number of blobs currently in the container")

logger_provider = LoggerProvider(resource=resource)
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(OTLPLogExporter(endpoint=f"{OTLP_ENDPOINT}/v1/logs", headers=HEADERS))
)
set_logger_provider(logger_provider)
handler = LoggingHandler(logger_provider=logger_provider)
logging.basicConfig(level=logging.INFO, handlers=[handler, logging.StreamHandler()])
LoggingInstrumentor().instrument(set_logging_format=True)
log = logging.getLogger("filestorage-demo")


def main() -> None:
    account_name = os.environ["STORAGE_ACCOUNT_NAME"]
    account_key = os.environ["STORAGE_ACCOUNT_KEY"]
    container_name = os.environ.get("STORAGE_CONTAINER", "demo-files")

    client = BlobServiceClient(
        account_url=f"https://{account_name}.blob.core.windows.net",
        credential=account_key,
    )
    container = client.get_container_client(container_name)
    # A container that never exists - every operation against it fails
    # with a real Azure SDK error (404, ContainerNotFound), producing
    # genuine storage_operations_total{result="error"} samples. Only
    # reached when FAULT_MODE=1 is set via `kubectl set env`; unset
    # again (`kubectl set env ... FAULT_MODE-`) to stop, no redeploy
    # either way - this pod picks up the env var change on its own.
    # No longer wired to a CI job or a dedicated alert - 4015 dropped
    # its own Use Case/alert outright (see alerting/README.md) but
    # stays onboarded, and this fault-injection knob still works if
    # ever needed again by hand.
    fault_container = client.get_container_client("demo-fault-nonexistent")
    log.info("Connected to storage account %s, container %s", account_name, container_name)

    known_blobs: list[str] = []

    while True:
        time.sleep(5)
        fault_mode = os.environ.get("FAULT_MODE", "").lower() in ("1", "true", "on")
        target = fault_container if (fault_mode and random.random() < 0.5) else container
        operation = random.choice(["upload", "download", "list", "upload", "download"])
        with tracer.start_as_current_span(f"blob.{operation}") as span:
            try:
                if operation == "upload" or not known_blobs:
                    name = f"demo-{uuid.uuid4().hex[:8]}.txt"
                    payload = os.urandom(random.randint(512, 8192))
                    target.upload_blob(name, payload, overwrite=True)
                    known_blobs.append(name)
                    span.set_attribute("blob.name", name)
                    span.set_attribute("blob.size_bytes", len(payload))
                    operations_counter.add(1, {"operation": "upload"})
                    bytes_histogram.record(len(payload), {"operation": "upload"})
                    log.info("Uploaded blob %s (%d bytes)", name, len(payload))
                elif operation == "download":
                    name = random.choice(known_blobs)
                    data = target.download_blob(name).readall()
                    span.set_attribute("blob.name", name)
                    span.set_attribute("blob.size_bytes", len(data))
                    operations_counter.add(1, {"operation": "download"})
                    bytes_histogram.record(len(data), {"operation": "download"})
                    log.info("Downloaded blob %s (%d bytes)", name, len(data))
                elif operation == "list":
                    blobs = list(target.list_blobs())
                    count = len(blobs)
                    total_bytes = sum(b.size for b in blobs)
                    span.set_attribute("blob.count", count)
                    span.set_attribute("blob.total_bytes", total_bytes)
                    operations_counter.add(1, {"operation": "list"})
                    storage_bytes_gauge.set(total_bytes)
                    storage_blob_count_gauge.set(count)
                    log.info("Listed container: %d blobs, %d bytes total", count, total_bytes)
            except Exception:
                log.exception("Blob operation %s failed", operation)
                operations_counter.add(1, {"operation": operation, "result": "error"})
                # Outside fault mode this is a genuine unexpected
                # failure - re-raise, same fail-fast behavior as
                # before (the Deployment's restart policy handles it).
                # In fault mode the failure is deliberate and expected
                # every ~2nd iteration - swallowing it here is what
                # keeps the pod (and known_blobs, and the real
                # container's own traffic) alive through the whole
                # break window instead of crash-looping on its own
                # injected fault.
                if not fault_mode:
                    raise


if __name__ == "__main__":
    main()

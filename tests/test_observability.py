import json
import logging

from app.observability import JsonLogFormatter, log_event, normalize_trace_id, trace_context


def test_trace_id_accepts_safe_client_value_and_replaces_invalid_value():
    assert normalize_trace_id("rec_test_12345678") == "rec_test_12345678"
    assert normalize_trace_id("bad value").startswith("trace_")


def test_json_formatter_includes_trace_and_redacted_fields():
    records = []
    logger = logging.getLogger("unit-observability")
    logger.handlers = []
    logger.propagate = False
    handler = logging.Handler()
    handler.emit = records.append
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    with trace_context("rec_test_12345678"):
        log_event(
            logger,
            logging.INFO,
            "unit_completed",
            duration_ms=12,
            authorization="Bearer secret-value",
        )
        payload = json.loads(JsonLogFormatter().format(records[0]))

    assert payload["event"] == "unit_completed"
    assert payload["trace_id"] == "rec_test_12345678"
    assert payload["duration_ms"] == 12
    assert payload["authorization"] == "[REDACTED]"

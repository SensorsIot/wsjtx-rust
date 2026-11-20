"""Summarize real instrumented stderr; never manufacture missing stage values."""
import argparse
import json
from pathlib import Path

TARGETS = ["CQ F5RXL IN94", "N1API F2VX 73", "CQ EA2BFM IN83",
           "WA2FZW DL5AXX RR73", "CQ DX DL8YHR JO41"]


def analyze(text):
    contexts = {}
    published = []
    count = 0
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip().startswith('{"trace":"ft8-stage-v1"'):
            continue  # Preserve other original decoder stderr outside this parser.
        event = json.loads(line)
        if event.get("stage") == "trace_limit":
            raise ValueError("trace truncated: no complete stage comparison may be claimed")
        count += 1
        serial = event["serial"]
        chain = contexts.setdefault(serial, [])
        chain.append(event)
        if event["stage"] == "publish" and event.get("text") in TARGETS:
            def last(stage):
                values = [e for e in chain if e["stage"] == stage]
                if not values:
                    raise ValueError(f"published target lacks observed {stage}: {event['text']}")
                return values[-1]
            published.append({
                "message": event["text"], "serial": serial,
                "period_half_symbols": event["period_half_symbols"],
                "outer_pass": event["outer_pass"],
                "candidate": last("candidate"),
                "refinement": last("refinement"),
                "hard_sync": last("hard_sync"),
                "selected_metric": last("metric"),
                "last_crc": last("crc"),
                "fec_result": last("fec_result"),
                "publication": event,
                "first_failing_stage": None,
                "outcome": "published by actual instrumented Fortran decoder",
            })
    if not count:
        raise ValueError("no actual Fortran stage records found")
    missing = sorted(set(TARGETS) - {r["message"] for r in published})
    if missing:
        raise ValueError(f"target publications absent from bounded trace: {missing}")
    return {"schema": 1, "observed_trace_events": count,
            "target_publications": published, "all_five_observed": True}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("stderr")
    p.add_argument("output")
    a = p.parse_args()
    result = analyze(Path(a.stderr).read_text(encoding="utf-8", errors="strict"))
    Path(a.output).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

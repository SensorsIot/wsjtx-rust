import json
import unittest
from analyze_fortran_trace import TARGETS, analyze


def records():
    out = []
    for serial, name in enumerate(TARGETS, 1):
        for stage in ["candidate", "refinement", "hard_sync", "metric", "crc", "fec_result", "publish"]:
            out.append({"trace": "ft8-stage-v1", "stage": stage,
                        "serial": serial, "period_half_symbols": 50,
                        "outer_pass": 2, "i": 0, "text": name if stage == "publish" else ""})
    return out


def lines(events):
    return "\n".join(json.dumps(e, separators=(",", ":")) for e in events)


class TraceParserTests(unittest.TestCase):
    def test_complete_observed_chains(self):
        result = analyze(lines(records()))
        self.assertTrue(result["all_five_observed"])
        self.assertEqual(result["observed_trace_events"], 35)
        self.assertEqual(len(result["target_publications"]), 5)
        self.assertTrue(all(e["first_failing_stage"] is None for e in result["target_publications"]))

    def test_absent_trace_is_not_inferred_from_final_messages(self):
        with self.assertRaisesRegex(ValueError, "no actual"):
            analyze('{"t":"decode","message":"CQ F5RXL IN94"}')

    def test_limit_is_failure(self):
        with self.assertRaisesRegex(ValueError, "truncated"):
            analyze(lines(records() + [{"trace": "ft8-stage-v1", "stage": "trace_limit"}]))

    def test_missing_stage_refused(self):
        with self.assertRaisesRegex(ValueError, "lacks observed refinement"):
            analyze(lines([e for e in records() if not (e["stage"] == "refinement" and e["serial"] == 1)]))

    def test_missing_target_refused(self):
        with self.assertRaisesRegex(ValueError, "target publications absent"):
            analyze(lines([e for e in records() if e["serial"] != 2]))

    def test_contexts_remain_separate(self):
        events = records()
        for event in events:
            if event["stage"] == "metric":
                event["i"] = event["serial"]
        result = analyze(lines(events))
        self.assertEqual([e["selected_metric"]["i"] for e in result["target_publications"]], [1,2,3,4,5])


if __name__ == "__main__":
    unittest.main()

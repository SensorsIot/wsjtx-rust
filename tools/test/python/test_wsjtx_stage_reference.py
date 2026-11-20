"""Instrumentation must preserve every compared request and emitted observation."""
import copy
import unittest
from wsjtx_reference import REVISION
from wsjtx_stage_reference import check_identity


def document():
    return {"source_revision": REVISION, "cases": [
        {"id": name, "mode": mode, "input_sha256": "input", "pcm_sha256": "pcm", "frames": 180000,
         "configure": {"ft8_ap_on": False, "nfa": 200, "nfb": 3500}, "request_sha256": "request",
         "rows": [{"text": "CQ K1ABC FN42"}], "events": [{"t": "decode_finished"}], "stdout_sha256": "output"}
        for name, mode in [("ft8-official", "ft8"), ("ft4-current", "ft4")]]}


class StageIdentity(unittest.TestCase):
    def test_identical_sample_observations_accepted(self):
        left = document()
        self.assertTrue(check_identity(left, copy.deepcopy(left))["same_stdout_and_decoded_observations"])

    def test_any_compared_observation_or_request_change_refused(self):
        left = document()
        for field in ["mode", "input_sha256", "pcm_sha256", "frames", "configure", "request_sha256", "rows", "events", "stdout_sha256"]:
            right = copy.deepcopy(left)
            right["cases"][0][field] = "changed"
            with self.subTest(field=field), self.assertRaises(ValueError):
                check_identity(left, right)

    def test_missing_case_and_wrong_revision_refused(self):
        left = document()
        right = copy.deepcopy(left)
        right["cases"].pop()
        with self.assertRaises(ValueError):
            check_identity(left, right)
        right = copy.deepcopy(left)
        right["source_revision"] = "other"
        with self.assertRaises(ValueError):
            check_identity(left, right)


if __name__ == "__main__":
    unittest.main()

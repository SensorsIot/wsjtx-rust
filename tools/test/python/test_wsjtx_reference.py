"""Checks that differential comparison cannot silently declare missing data equal."""
import copy
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch
from wsjtx_reference import (compare, parse_reference_output, reference_command, run_reference,
                             codec_configure, parse_codec_output, stream_frame)


def inputs(reference, candidate):
    common = {"id": "fixed", "mode": "ft8", "input_sha256": "a", "pcm_sha256": "b", "frames": 180000}
    ref = {"cases": [{**common, "rows": [{"text": text, "frequency_hz": hz, "snr_db": -12,
                                           "display_dt_seconds": 0.1} for text, hz in reference]}]}
    rust = {"cases": [{**common, "rows": [{"text": text, "frequency_hz": hz} for text, hz in candidate]}]}
    return ref, rust


class Comparison(unittest.TestCase):
    def test_missing_extra_and_duplicate_observations_are_not_equal(self):
        ref, rust = inputs([("CQ K1ABC FN42", 1000), ("W1AW K1ABC -10", 1500)],
                           [("CQ K1ABC FN42", 1001), ("CQ K1ABC FN42", 1001)])
        case = compare(ref, rust, 5)["cases"][0]
        self.assertEqual(case["match_count"], 1)
        self.assertEqual(case["missing_from_rust"][0]["text"], "W1AW K1ABC -10")
        self.assertEqual(len(case["rust_only"]), 1)
        self.assertFalse(case["same_messages_within_frequency_tolerance"])

    def test_order_and_documented_report_spacing_do_not_create_differences(self):
        ref, rust = inputs([("W1AW K1ABC R-10", 1000), ("CQ W1AW FN31", 1500)],
                           [("CQ W1AW FN31", 1505), ("W1AW K1ABC R -10", 999)])
        self.assertTrue(compare(ref, rust, 5)["cases"][0]["same_messages_within_frequency_tolerance"])

    def test_nearest_greedy_trap_still_finds_both_distinct_observations(self):
        ref, rust = inputs([("CQ", 100), ("CQ", 105)], [("CQ", 103), ("CQ", 96)])
        self.assertEqual(compare(ref, rust, 4)["cases"][0]["match_count"], 2)

    def test_changed_pcm_or_mode_refused(self):
        ref, rust = inputs([("CQ", 100)], [("CQ", 100)])
        for field in ("input_sha256", "pcm_sha256", "frames", "mode"):
            changed = copy.deepcopy(rust)
            changed["cases"][0][field] = "different"
            with self.subTest(field=field), self.assertRaises(ValueError):
                compare(ref, changed, 5)

    def test_outside_frequency_tolerance_is_visible(self):
        ref, rust = inputs([("CQ", 100)], [("CQ", 105.01)])
        self.assertEqual(compare(ref, rust, 5)["cases"][0]["match_count"], 0)


class ReferenceProtocol(unittest.TestCase):
    row = "133430 -12  0.1 1000 ~  CQ K1ABC FN42"
    completion = "<DecodeFinished>   0   1        0"

    def test_pinned_ft8_three_attempts_preserve_repeated_observations(self):
        text = "\n".join([self.row, self.completion] * 3)
        attempts = parse_reference_output(text, "ft8", 3)
        self.assertEqual([a["attempt"] for a in attempts], [1, 2, 3])
        self.assertEqual([a["decoded"] for a in attempts], [1, 1, 1])
        self.assertEqual([a["rows"][0]["text"] for a in attempts], ["CQ K1ABC FN42"] * 3)

    def test_empty_attempt_and_single_ft4_completion(self):
        attempts = parse_reference_output("<DecodeFinished>   0   0        0\n", "ft4", 1)
        self.assertEqual(attempts[0]["rows"], [])

    def test_missing_malformed_extra_or_wrong_count_completion_refused(self):
        valid = "\n".join([self.row, self.completion] * 3)
        cases = [valid.rsplit("\n", 1)[0], valid.replace(self.completion, "<DecodeFinished> bad", 1),
                 valid + "\n<DecodeFinished> 0 0 0", valid.replace(self.completion, "<DecodeFinished> 0 2 0", 1),
                 valid + "\n" + self.row, ""]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_reference_output(text, "ft8", 3)

    def test_counts_belong_to_each_attempt_not_aggregate(self):
        text = "\n".join([self.row, self.completion, self.row, self.row,
                          "<DecodeFinished> 0 2 0", "<DecodeFinished> 0 0 0"])
        self.assertEqual([a["decoded"] for a in parse_reference_output(text, "ft8", 3)], [1, 2, 0])

    def test_wrong_mode_and_unparsed_rows_refused(self):
        for text in [self.row.replace("~", "+") + "\n" + self.completion, "unexpected\n" + self.completion]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_reference_output(text, "ft8", 1)

    def test_command_explicitly_blanks_calls_and_disables_experience(self):
        for mode, flag, period in [("ft8", "-8", "15"), ("ft4", "-5", "7.5")]:
            command = reference_command("jt9", "input.wav", "work", mode, 3)
            self.assertEqual(command[1], flag)
            for option, expected in [("-c", "b"), ("-x", "b"), ("-X", "0"), ("-Q", "0"), ("-L", "200"), ("-H", "3500"), ("-p", period), ("-d", "3")]:
                self.assertEqual(command[command.index(option) + 1], expected)

    def test_wrong_prebuilt_hash_refused_before_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            executable = root / "wrong.exe"
            executable.write_bytes(b"not the pinned official executable")
            with patch("wsjtx_reference.subprocess.run") as execute, self.assertRaises(ValueError):
                run_reference(executable, root, root / "out", 3)
            execute.assert_not_called()


class StreamProtocol(unittest.TestCase):
    ready = {"v": 1, "t": "ready", "protocol": 1, "modes": ["FT8", "FT4"]}
    decode = {"v": 1, "t": "decode", "mode": "FT8", "time": "13:34:30",
              "snr": -12, "dt": 0.1, "freq": 1000, "message": "CQ K1ABC FN42"}
    finished = {"v": 1, "t": "decode_finished", "period_end": "13:34:30"}

    def test_ap_control_is_boolean_and_ft4_unassisted_requires_fast(self):
        for ap in (False, True):
            config = codec_configure("ft8", 3, ap)
            self.assertIs(config["ft8_ap_on"], ap)
            self.assertIs(config["multithreaded_ft8"], False)
            self.assertEqual(config["depth"], 3)
            self.assertEqual((config["nfa"], config["nfb"]), (200, 3500))
            self.assertEqual((config["mycall"], config["his_call"]), ("", ""))
            self.assertEqual(json.loads(json.dumps(config))["ft8_ap_on"], ap)
        self.assertEqual(codec_configure("ft4", 3, False)["depth"], 1)
        self.assertEqual(codec_configure("ft4", 3, True)["depth"], 3)

    def test_frame_keeps_pcm_bytes_and_declares_little_endian_length(self):
        pcm = b"\x00\x80\xff\x7f\x01\x00"
        self.assertEqual(stream_frame(1, pcm), b"\x01\x06\x00\x00\x00" + pcm)

    def test_rows_duplicates_and_completion_are_preserved(self):
        events = [self.ready, self.decode, self.decode, self.finished]
        actual, rows = parse_codec_output("\n".join(map(json.dumps, events)), "ft8")
        self.assertEqual(actual, events)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["text"], "CQ K1ABC FN42")

    def test_error_missing_completion_wrong_mode_and_unknown_events_refused(self):
        error = {"v": 1, "t": "error", "code": "configure_type_error", "key": "ft8_ap_on"}
        cases = [[self.ready, error, self.finished], [self.ready, self.decode],
                 [self.ready, {**self.decode, "mode": "FT4"}, self.finished],
                 [self.ready, self.finished, self.decode], [self.ready, self.finished, self.finished],
                 [self.ready, {"v": 1, "t": "unknown"}, self.finished],
                 [self.ready, {**self.decode, "v": 2}, self.finished], [self.decode, self.finished]]
        for events in cases:
            with self.subTest(events=events), self.assertRaises(ValueError):
                parse_codec_output("\n".join(map(json.dumps, events)), "ft8")


if __name__ == "__main__":
    unittest.main()

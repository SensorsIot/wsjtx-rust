"""Layout and fault controls; these tests never load or call the Windows API."""

import contextlib
import ctypes
import io
import json
import unittest
from unittest.mock import patch

import windows_process_metrics as metrics


class FakeApi:
    def __init__(self, fault=None):
        self.fault = fault
        self.closed = []
        self.calls = []

    def open(self, access, inherit, pid):
        self.calls.append(("open", access, inherit, pid))
        return None if self.fault == "open" else 123

    def times(self, handle, created, exited, kernel, user):
        self.calls.append(("times", handle))
        if self.fault == "times":
            return 0
        created._obj.low = 89 if self.fault == "identity" else 88
        exited._obj.low = 0 if self.fault == "exited" else 0xDEADBEEF
        kernel._obj.low, user._obj.low = 20, 30
        return 1

    def memory(self, handle, counters, size):
        self.calls.append(("memory", handle, size))
        if self.fault == "memory":
            return 0
        assert size == 80 and counters._obj.cb == 80
        counters._obj.PrivateUsage = 0 if self.fault == "zero" else 500
        counters._obj.PagefileUsage = 500
        counters._obj.PeakPagefileUsage = (1 << 40) + 900
        if self.fault == "exit_during_sample":
            self.fault = "exited"
        return 1

    def close(self, handle):
        self.closed.append(handle)
        return 0 if self.fault == "close" else 1

    def wait(self, handle, timeout):
        assert timeout == 0
        self.calls.append(("wait", handle, timeout))
        return {"exited": 0, "wait": 0xFFFFFFFF, "unexpected_wait": 128}.get(self.fault, 258)

    @staticmethod
    def last_error():
        return 5


class WindowsMetricsControls(unittest.TestCase):
    def test_native_x64_fields_offsets_and_widths(self):
        self.assertEqual(metrics.checked_layout(), 80)
        self.assertEqual(ctypes.sizeof(metrics.FileTime), 8)
        self.assertEqual(metrics.ProcessMemoryCountersEx.PrivateUsage.offset, 72)
        self.assertEqual(metrics.ProcessMemoryCountersEx.PeakPagefileUsage.offset, 64)
        self.assertEqual(metrics.FileTime(0xFFFFFFFF, 0x12345678).ticks(), 0x12345678FFFFFFFF)

    def test_exact_private_and_lifetime_peak_are_not_idle_subtraction(self):
        api = FakeApi()
        with metrics.OwnedProcess(42, 88, api) as process:
            value = process.sample()
            self.assertEqual(value["private_usage"], 500)
            self.assertEqual(value["lifetime_peak_commit"], (1 << 40) + 900)
            self.assertEqual(value["process_cpu_100ns"], 50)
            self.assertEqual(value["creation_filetime"], 88)
            self.assertEqual(value["unit"], "bytes")
        self.assertEqual(api.calls[0], ("open", 0x101000, False, 42))
        self.assertEqual(api.closed, [123])

    def test_api_failures_retain_error_and_close_owned_handle(self):
        for fault, operation in [("open", "OpenProcess"), ("times", "GetProcessTimes"),
                                 ("memory", "K32GetProcessMemoryInfo"), ("close", "CloseHandle"),
                                 ("wait", "WaitForSingleObject")]:
            with self.subTest(fault=fault):
                api = FakeApi(fault)
                with self.assertRaises(metrics.MetricsError) as caught:
                    with metrics.OwnedProcess(42, 88, api) as process:
                        process.sample()
                self.assertEqual(caught.exception.operation, operation)
                self.assertEqual(caught.exception.code, 5)
                self.assertEqual(api.closed, [] if fault == "open" else [123])

    def test_wrong_identity_or_exit_never_yields_metrics(self):
        for fault in ["identity", "exited", "exit_during_sample", "zero", "unexpected_wait"]:
            with self.subTest(fault=fault):
                api = FakeApi(fault)
                with self.assertRaises(metrics.MetricsError):
                    with metrics.OwnedProcess(42, 88, api) as process:
                        process.sample()
                self.assertEqual(api.closed, [123])

    def test_identity_bounds_bool_and_closed_handle_refuse(self):
        for pid, creation in [(0, 88), (-1, 88), (1 << 32, 88), (True, 88), (42, 0), (42, 1 << 64)]:
            with self.assertRaises(metrics.MetricsError):
                metrics.OwnedProcess(pid, creation, FakeApi())
        api = FakeApi()
        process = metrics.OwnedProcess(42, 88, api)
        process.close()
        process.close()
        self.assertEqual(api.closed, [123])
        with self.assertRaisesRegex(metrics.MetricsError, "closed_handle"):
            process.sample()

    def test_parent_bootstrap_can_only_use_actual_waiting_parent(self):
        api = FakeApi()
        with patch.object(metrics.os, "getppid", return_value=42):
            value = metrics.parent_creation(api)
        self.assertEqual(value, {"v": 1, "pid": 42, "creation_filetime": 88})
        self.assertEqual(api.calls[0], ("open", 0x101000, False, 42))
        self.assertEqual(api.closed, [123])

    def test_bounded_strict_protocol_and_eof_close(self):
        for text in ["", '{"op":"sample","id":1}\n{"op":"close","id":2}\n']:
            api, output = FakeApi(), io.StringIO()
            with contextlib.redirect_stdout(output):
                metrics.serve(42, 88, io.StringIO(text), api)
            rows = [json.loads(line) for line in output.getvalue().splitlines()]
            self.assertEqual(rows[0]["state"], "bound")
            self.assertEqual(api.closed, [123])
            if text:
                self.assertEqual(rows[1]["private_usage"], 500)
                self.assertEqual(rows[-1]["state"], "closed")
        for text in ['{"op":"sample","id":1,"x":0}\n', '{"op":"sample","id":true}\n',
                     '{"op":"sample","op":"close","id":1}\n', 'x' * 4097,
                     '{"op":"sample","id":1}',
                     '{"op":"sample","id":1}\n{"op":"sample","id":1}\n']:
            api = FakeApi()
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises((metrics.MetricsError, ValueError)):
                metrics.serve(42, 88, io.StringIO(text), api)
            self.assertEqual(api.closed, [123])


if __name__ == "__main__":
    unittest.main()

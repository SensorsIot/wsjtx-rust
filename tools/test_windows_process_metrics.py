"""Layout and fault controls; these tests never load or call the Windows API."""

import contextlib
import ctypes
import io
import json
import sys
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

    def current(self):
        return -1

    def duplicate(self, parent, source, target_process, result, access, inherit, options):
        self.calls.append(("duplicate", parent, source, target_process, access, inherit, options))
        if self.fault == "duplicate":
            return 0
        if self.fault != "invalid_duplicate":
            result._obj.value = 456
        return 1

    def process_id(self, handle):
        self.calls.append(("process_id", handle))
        return 0 if self.fault == "process_id" else 99 if self.fault == "wrong_process" else 42

    @staticmethod
    def last_error():
        return 5


class WindowsMetricsControls(unittest.TestCase):
    def test_parent_handle_duplicate_binds_actual_object_and_narrows_access(self):
        api = FakeApi()
        with patch.object(metrics.os, "getppid", return_value=777):
            process = metrics.OwnedProcess.from_parent_handle(900, 42, api)
        self.assertEqual(api.calls[0], ("open", 0x40, False, 777))
        self.assertIn(("duplicate", 123, 900, -1, 0x101000, False, 0), api.calls)
        self.assertEqual(api.closed, [123])
        self.assertEqual(process.creation, 88)
        self.assertEqual(process.sample()["pid"], 42)
        api.fault = "identity"
        with self.assertRaisesRegex(metrics.MetricsError, "creation_identity_mismatch"):
            process.sample()
        process.close()
        self.assertEqual(api.closed, [123, 456])
        self.assertNotIn(900, api.closed)
        self.assertNotIn(-1, api.closed)

    def test_duplicate_faults_close_only_owned_handles(self):
        for fault, operation, closed in [
            ("open", "OpenProcessParent", []), ("duplicate", "DuplicateHandle", [123]),
            ("invalid_duplicate", "invalid_duplicate_handle", [123]),
            ("process_id", "GetProcessId", [123, 456]),
            ("wrong_process", "process_object_identity_mismatch", [123, 456]),
            ("times", "GetProcessTimes", [123, 456]),
            ("wait", "WaitForSingleObject", [123, 456]),
            ("exited", "process_not_live", [123, 456]),
            ("close", "CloseParentHandle", [123, 456]),
        ]:
            with self.subTest(fault=fault):
                api = FakeApi(fault)
                with self.assertRaises(metrics.MetricsError) as caught:
                    metrics.OwnedProcess.from_parent_handle(900, 42, api)
                self.assertEqual(caught.exception.operation, operation)
                self.assertEqual(api.closed, closed)
        for source in [0, -1, True, 1 << 64, (1 << 64) - 1]:
            with self.assertRaises(metrics.MetricsError):
                metrics.OwnedProcess.from_parent_handle(source, 42, FakeApi())

    def test_duplicate_mode_protocol_does_not_fallback_to_pid_open(self):
        api, output = FakeApi(), io.StringIO()
        with patch.object(metrics.os, "getppid", return_value=777), contextlib.redirect_stdout(output):
            metrics.serve(42, None, io.StringIO('{"op":"sample","id":1}\n{"op":"close","id":2}\n'), api, parent_handle=900)
        self.assertEqual([call for call in api.calls if call[0] == "open"], [("open", 0x40, False, 777)])
        rows = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(rows[0], {"v": 1, "state": "bound", "pid": 42, "creation_filetime": 88})
        self.assertEqual(rows[1]["creation_filetime"], 88)
        self.assertEqual(api.closed, [123, 456])
        api = FakeApi()
        with self.assertRaisesRegex(metrics.MetricsError, "invalid_request"):
            metrics.serve(42, 88, io.StringIO(""), api, parent_handle=900)
        self.assertEqual(api.calls, [])

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


class CapacityOwnerControls(unittest.TestCase):
    def exercise_owner(self, fault=None):
        """Entire owner uses fake process/metrics/streams; no OS API or spawn."""
        import hashlib
        from pathlib import Path
        import tempfile
        import subprocess
        nonce = "a"*32
        kernels = ["RESOURCE_KERNEL "+json.dumps({"mode":mode,"scalar":scalar,
                    "frames":360000,"complete":True,"actual_decoded_callbacks":1})+"\n"
                   for mode in ("ft8","ft4") for scalar in (False,True)]
        event = lambda state: "RESOURCE_HANDSHAKE "+json.dumps({"state":state,"nonce":nonce})+"\n"
        stderr = event("READY")+"".join(kernels)+"RESOURCE_DISPOSITION {\"all_test_owners_dropped\":true}\n"+event("FINISHED")
        if fault == "eof": stderr = event("READY")
        if fault == "duplicate": stderr = event("READY")+event("READY")
        if fault == "oversize": stderr = "X"*16385+"\n"
        if fault == "wrong_nonce": stderr = stderr.replace(nonce,"b"*32)
        if fault == "bad_json": stderr = "RESOURCE_HANDSHAKE {oops}\n"
        if fault == "missing_kernel": stderr = stderr.replace(kernels[0],"")
        if fault == "trailing": stderr += event("FINISHED")
        class Child:
            pid = 42
            _handle = 777
            returncode = None
            killed = False
            def __init__(self):
                self.stdin = io.StringIO()
                self.stdout = io.StringIO("test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured;\n")
                self.stderr = io.StringIO(stderr)
            def poll(self): return self.returncode
            def kill(self): self.killed = True; self.returncode = -9
            def wait(self, timeout):
                if fault == "wait_timeout" and not self.killed:
                    raise subprocess.TimeoutExpired("owned",timeout)
                if self.returncode is None: self.returncode = 0
                return self.returncode
        class Process:
            closed = False
            def sample(self): return {"lifetime_peak_commit":12345,"private_usage":12000,"pid":42,"creation_filetime":88}
            def close(self): self.closed = True
        child, process = Child(), Process()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            exe = root/"lib.exe"; exe.write_bytes(b"fake-exe")
            cache = root/"cache"
            real_sha = hashlib.sha256
            for name, data in (("ft8-strong-00",b"ft8"),("ft4-strong-00",b"ft4")):
                (cache/name).mkdir(parents=True); (cache/name/"000000_000000.wav").write_bytes(data)
            def fake_sha(data):
                class Digest:
                    def hexdigest(self): return {b"ft8":"02525d0ebe7661935d52e60f169501aae2428983a72a1e1a0c8087ddce322d51",
                       b"ft4":"17efa54767abee26df1116894f84c56c014135ac6aabf17277358d6ca55d7f36"}.get(data,real_sha(data).hexdigest())
                return Digest()
            files = [exe,Path(metrics.__file__).resolve(),cache/"ft8-strong-00/000000_000000.wav",cache/"ft4-strong-00/000000_000000.wav"]
            pins = {"source_commit":"test-attested","compiler":"fake","host":"fake","exe":str(exe),
                    "cache":str(cache),"root_clean_source_attestation":True,
                    "files":{str(p):fake_sha(p.read_bytes()).hexdigest() for p in files}}
            pinfile=root/"pins.json"; pinfile.write_text(json.dumps(pins))
            argv=["metrics","--capacity-pins",str(pinfile),"--capacity-pins-sha",real_sha(pinfile.read_bytes()).hexdigest(),
                  "--capacity-out",str(root/"out")]
            import time
            real_clock = time.monotonic
            clock_calls = []
            def clock():
                clock_calls.append(True)
                return (0 if len(clock_calls) == 1 else 301) if fault == "deadline" else real_clock()
            with patch.object(sys,"argv",argv), patch("hashlib.sha256",side_effect=fake_sha), \
                 patch("time.monotonic",side_effect=clock), \
                 patch("secrets.token_hex",return_value=nonce), patch.object(metrics,"pe_image_size",return_value=8192), \
                 patch("subprocess.Popen",return_value=child) as popen, \
                 patch.object(metrics.OwnedProcess,"from_local_parent_handle",return_value=process), \
                 patch.object(metrics,"NativeApi",side_effect=AssertionError("native API forbidden")):
                result=metrics.capacity_main()
            receipt=json.loads((root/"out/receipt.json").read_text())
            if fault == "deadline":
                self.assertEqual(popen.call_count,0)
                self.assertFalse(process.closed)
                return result,receipt,child.killed
            self.assertEqual(popen.call_count,1)
            self.assertTrue(process.closed)
            self.assertTrue(receipt["cleanup_complete"])
            self.assertTrue(receipt["reader_joined"])
            self.assertEqual(receipt["workspace_proof"],"INCONCLUSIVE")
            return result,receipt,child.killed

    def test_complete_parent_protocol_is_component_only(self):
        result,receipt,killed=self.exercise_owner()
        self.assertEqual(result,0)
        self.assertTrue(receipt["complete"])
        self.assertFalse(killed)
        self.assertEqual(receipt["absolute_peak_plus_main_image_bytes"],20537)
        self.assertIsNone(receipt["other_nonprivate_and_unexercised_capacity_allowance_bytes"])

    def test_expired_deadline_never_spawns(self):
        result,receipt,killed = self.exercise_owner("deadline")
        self.assertEqual(result,1)
        self.assertIn("deadline_before_spawn",receipt["failure"]["message"])
        self.assertFalse(killed)

    def test_parent_faults_cleanup_and_never_complete(self):
        for fault in ("eof","duplicate","oversize","wrong_nonce","bad_json","missing_kernel","trailing","wait_timeout"):
            with self.subTest(fault=fault):
                result,receipt,killed=self.exercise_owner(fault)
                self.assertEqual(result,1)
                self.assertFalse(receipt["complete"])
                self.assertIn("failure",receipt)

    def test_local_duplicate_never_opens_process(self):
        api = FakeApi()
        with metrics.OwnedProcess.from_local_parent_handle(777, 42, api) as process:
            self.assertEqual(process.handle, 456)
            self.assertEqual(process.creation, 88)
        self.assertEqual(api.closed, [456])
        self.assertFalse(any(call[0] == "open" for call in api.calls))
        self.assertIn(("duplicate", -1, 777, -1,
                       metrics.QUERY_LIMITED_INFORMATION | metrics.SYNCHRONIZE, False, 0), api.calls)

    def test_local_duplicate_failure_and_identity_close(self):
        for fault in ("duplicate", "invalid_duplicate", "process_id", "wrong_process", "times", "exited"):
            with self.subTest(fault=fault):
                api = FakeApi(fault)
                with self.assertRaises(metrics.MetricsError):
                    metrics.OwnedProcess.from_local_parent_handle(777, 42, api)
                self.assertEqual(api.closed, [] if fault in ("duplicate", "invalid_duplicate") else [456])

    def test_nonce_and_order(self):
        protocol = metrics.CapacityProtocol("abc")
        for record in ({"state":"FINISHED","nonce":"abc"}, {"state":"READY","nonce":"wrong"},
                       {"state":"READY","nonce":"abc","extra":True}):
            with self.assertRaises(metrics.MetricsError): protocol.accept(record)
        self.assertEqual(protocol.accept({"state":"READY","nonce":"abc"}), "READY")
        with self.assertRaises(metrics.MetricsError): protocol.accept({"state":"READY","nonce":"abc"})
        self.assertEqual(protocol.accept({"state":"FINISHED","nonce":"abc"}), "FINISHED")
        with self.assertRaises(metrics.MetricsError): protocol.accept({"state":"FINISHED","nonce":"abc"})

    def test_cleanup_uses_retained_child_and_remaining_deadline(self):
        class Child:
            returncode = None
            killed = False
            waited = None
            def poll(self): return self.returncode
            def kill(self): self.killed = True
            def wait(self, timeout): self.waited = timeout; self.returncode = -9
        child = Child(); receipt = {}
        metrics.finish_capacity_child(child, 300, lambda: 297, receipt)
        self.assertTrue(child.killed)
        self.assertEqual(child.waited, 3)
        self.assertTrue(receipt["cleanup_complete"])
        self.assertEqual(receipt["exit_code"], -9)

    def test_cleanup_failure_is_not_completion(self):
        class Child:
            returncode = None
            def poll(self): return None
            def kill(self): raise OSError("refused")
            def wait(self, timeout):
                self.timeout = timeout
                raise TimeoutError("unreaped")
        child = Child(); receipt = {}
        metrics.finish_capacity_child(child, 300, lambda: 301, receipt)
        self.assertEqual(child.timeout, 0)
        self.assertFalse(receipt["cleanup_complete"])
        self.assertIn("kill_error", receipt)
        self.assertIn("wait_error", receipt)

    def test_pe_image_size_and_malformed_images(self):
        import struct
        data = bytearray(512)
        data[:2] = b"MZ"; struct.pack_into("<I", data, 60, 64)
        data[64:68] = b"PE\0\0"; struct.pack_into("<HH", data, 68, 0x8664, 1)
        struct.pack_into("<H", data, 84, 112); struct.pack_into("<H", data, 88, 0x20B)
        struct.pack_into("<II", data, 144, 8192, 512)
        struct.pack_into("<III", data, 208, 100, 4096, 512)
        self.assertEqual(metrics.pe_image_size(data), 8192)
        for offset, replacement in ((0,b"XX"),(64,b"NOPE"),(68,b"\x4c\x01"),
                                    (88,b"\x0b\x01"),(144,b"\x00\x00\x00\x00"),
                                    (212,b"\xff\xff\xff\xff")):
            bad = data.copy(); bad[offset:offset+len(replacement)] = replacement
            with self.assertRaises(metrics.MetricsError): metrics.pe_image_size(bad)
        for length in (0,63,100,220):
            with self.assertRaises(metrics.MetricsError): metrics.pe_image_size(data[:length])


if __name__ == "__main__":
    unittest.main()

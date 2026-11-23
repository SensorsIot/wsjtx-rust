"""bench-hold.ps1: while a candidate bench runs, the server's own lock call on every known COM port fails.

It runs the holder for real on lock files in a temporary folder, with a device file in place of
Get-PnpDevice -Class Ports (no port, no device, no other process is touched), and then makes exactly the
call the server makes before it opens a port: the ownership file opened for writing, shared, and
LockFileEx exclusive and fail-immediately over the whole range, which is std::fs::File::try_lock on
Windows (windows.rs claim_identity, taken by radio detection's probe and the CAT open). That call must fail
with ERROR_LOCK_VIOLATION (Rust's TryLockError::WouldBlock: the port is in use, never opened) for every
known port but COM4, also for one that appears while the bench runs, and succeed once the bench ends.
"""
import ctypes
import json
import msvcrt
import os
import subprocess
import sys
import tempfile
import time
import unittest
from ctypes import wintypes

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "deploy", "tests"))
import pwsh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "bench-hold.ps1")
RADIO = "USB\\VID_10C4&PID_EA60\\IC-7300 03001234 A"
SIM = "COM0COM\\PORT\\CNCA0"
LATER = "FTDIBUS\\VID_0403+PID_6001+A1\\0000"
ERROR_LOCK_VIOLATION = 33


class OVERLAPPED(ctypes.Structure):
    _fields_ = [("Internal", ctypes.c_void_p), ("InternalHigh", ctypes.c_void_p),
                ("Offset", wintypes.DWORD), ("OffsetHigh", wintypes.DWORD), ("hEvent", wintypes.HANDLE)]


def try_lock(path):
    """std's File::try_lock on Windows, on `path` opened as the server opens it: True when locked."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.LockFileEx.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD,
                                    wintypes.DWORD, ctypes.POINTER(OVERLAPPED)]
    kernel32.UnlockFileEx.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD,
                                      ctypes.POINTER(OVERLAPPED)]
    with open(path, "a+b") as f:   # create, write, no truncation, shared read and write
        handle = msvcrt.get_osfhandle(f.fileno())
        if not kernel32.LockFileEx(handle, 0x2 | 0x1, 0, 0xFFFFFFFF, 0xFFFFFFFF, ctypes.byref(OVERLAPPED())):
            error = ctypes.get_last_error()
            if error != ERROR_LOCK_VIOLATION:
                raise OSError(error, "LockFileEx failed otherwise")
            return False
        kernel32.UnlockFileEx(handle, 0, 0xFFFFFFFF, 0xFFFFFFFF, ctypes.byref(OVERLAPPED()))
        return True


def owner_lock(root, identity):
    """windows.rs claim_identity's path: the upper-case identity's bytes in hex, 120 characters a folder."""
    hexed = identity.upper().encode("ascii").hex()
    parts = [hexed[i:i + 120] for i in range(0, len(hexed), 120)]
    return os.path.join(root, "WstxRust", "radio-ownership", *parts, "owner.lock")


class BenchHoldTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "appdata")
        self.record = os.path.join(self.tmp.name, "bench.json")
        self.devices = os.path.join(self.tmp.name, "devices.json")
        # The radio's bridge is known to Windows but switched off (not present): it is locked all the same.
        self.known([{"name": "Silicon Labs CP210x USB to UART Bridge (COM3)", "id": RADIO},
                    {"name": "com0com - serial port emulator CNCA0 (COM4)", "id": SIM}])
        with open(self.record, "w", encoding="utf-8") as f:
            json.dump({"issue": 7, "state": "starting"}, f)
        self.start()
        self.wait(lambda: os.path.exists(self.record + ".holding"), "the holder did not report its locks")

    def start(self):
        if getattr(self, "proc", None) is not None:
            self.proc.kill()
            self.proc.wait(timeout=30)
            self.proc.stdout.close()
        self.proc = subprocess.Popen([pwsh.POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                                      "-File", TOOL, "-Record", self.record, "-LockRoot", self.root, "-KeepPort", "4",
                                      "-Devices", self.devices, "-PollMilliseconds", "200"],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                     encoding="utf-8", errors="replace")

    def tearDown(self):
        if self.proc.poll() is None:
            self.proc.kill()
        self.proc.wait(timeout=30)
        self.proc.stdout.close()
        self.tmp.cleanup()

    def known(self, devices):
        with open(self.devices + ".new", "w", encoding="utf-8") as f:
            json.dump(devices, f)
        os.replace(self.devices + ".new", self.devices)

    def wait(self, done, why, seconds=30):
        deadline = time.monotonic() + seconds
        while not done():
            if self.proc.poll() is not None:
                self.fail(why + ": the holder ended: " + self.proc.stdout.read())
            if time.monotonic() > deadline:
                self.fail(why)
            time.sleep(0.1)

    def test_every_known_port_but_com4_is_in_use_for_the_server_while_the_bench_runs(self):
        self.assertFalse(try_lock(owner_lock(self.root, RADIO)), "the server could own COM3")
        self.assertTrue(try_lock(owner_lock(self.root, SIM)), "COM4, the simulator's port, must stay free")
        with open(self.record + ".holding", encoding="utf-8-sig") as f:
            self.assertEqual(json.load(f), [owner_lock(self.root, RADIO)])

    def test_a_port_that_appears_while_the_bench_runs_is_locked_at_once(self):
        self.assertTrue(try_lock(owner_lock(self.root, LATER)))       # not known yet
        self.known([{"name": "Silicon Labs CP210x USB to UART Bridge (COM3)", "id": RADIO},
                    {"name": "com0com - serial port emulator CNCA0 (COM4)", "id": SIM},
                    {"name": "USB Serial Port (COM9)", "id": LATER}])
        self.wait(lambda: not try_lock(owner_lock(self.root, LATER)), "the new port COM9 was not locked", seconds=5)
        self.assertFalse(try_lock(owner_lock(self.root, RADIO)))

    def test_the_locks_end_with_the_bench(self):
        os.remove(self.record)
        self.proc.wait(timeout=30)
        self.assertTrue(try_lock(owner_lock(self.root, RADIO)))
        self.assertFalse(os.path.exists(self.record + ".holding"))

    def test_the_locks_end_when_the_candidate_is_gone(self):
        with open(self.record, "w", encoding="utf-8") as f:
            json.dump({"issue": 7, "pid": 4194300}, f)   # no such process
        self.proc.wait(timeout=30)
        self.assertTrue(try_lock(owner_lock(self.root, RADIO)))


class BenchHoldReadyTests(BenchHoldTests):
    """The holder reports ready only with every known device locked, and a later scan never drops a lock."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "appdata")
        self.record = os.path.join(self.tmp.name, "bench.json")
        self.devices = os.path.join(self.tmp.name, "devices.json")
        with open(self.record, "w", encoding="utf-8") as f:
            json.dump({"issue": 7, "state": "starting"}, f)
        self.proc = None

    def tearDown(self):
        if self.proc is not None:
            super().tearDown()
        else:
            self.tmp.cleanup()

    def ended_without_ready(self):
        self.proc.wait(timeout=30)
        out = self.proc.stdout.read()
        self.assertEqual(self.proc.returncode, 2, out)
        self.assertFalse(os.path.exists(self.record + ".holding"), out)
        return out

    # The inherited tests run with the setUp of BenchHoldTests only.
    test_every_known_port_but_com4_is_in_use_for_the_server_while_the_bench_runs = None
    test_a_port_that_appears_while_the_bench_runs_is_locked_at_once = None
    test_the_locks_end_with_the_bench = None
    test_the_locks_end_when_the_candidate_is_gone = None

    def test_a_device_without_a_name_is_locked(self):
        self.known([{"id": RADIO}, {"name": "com0com - serial port emulator CNCA0 (COM4)", "id": SIM}])
        self.start()
        self.wait(lambda: os.path.exists(self.record + ".holding"), "the holder did not report its locks")
        self.assertFalse(try_lock(owner_lock(self.root, RADIO)))

    def test_a_failing_device_query_never_reports_ready(self):
        self.start()                                        # the device source does not exist
        self.assertIn("the device query failed", self.ended_without_ready())
        with open(self.devices, "w", encoding="utf-8") as f:
            f.write("{not json")                            # the device source cannot be read
        self.start()
        self.assertIn("the device query failed", self.ended_without_ready())

    def test_no_known_device_is_no_ready(self):
        self.known([])
        self.start()
        self.assertIn("no COM port device is known", self.ended_without_ready())
        self.known([{"name": "nameless id missing"}])     # a device without an instance id is no device
        self.start()
        self.assertIn("no COM port device is known", self.ended_without_ready())

    def test_a_failing_rescan_keeps_every_lock_and_is_tried_again(self):
        self.known([{"name": "Silicon Labs CP210x USB to UART Bridge (COM3)", "id": RADIO}])
        self.start()
        self.wait(lambda: os.path.exists(self.record + ".holding"), "the holder did not report its locks")
        with open(self.devices, "w", encoding="utf-8") as f:
            f.write("{not json")                            # every rescan fails now
        time.sleep(1.5)
        self.assertIsNone(self.proc.poll(), "the holder ended on a failing rescan")
        self.assertFalse(try_lock(owner_lock(self.root, RADIO)), "a failing rescan dropped the lock of COM3")
        self.known([{"name": "Silicon Labs CP210x USB to UART Bridge (COM3)", "id": RADIO},
                    {"name": "USB Serial Port (COM9)", "id": LATER}])
        self.wait(lambda: not try_lock(owner_lock(self.root, LATER)), "the next good scan did not lock COM9", seconds=5)


if __name__ == "__main__":
    unittest.main()

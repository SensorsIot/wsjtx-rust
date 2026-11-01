"""Read private commit for an identified, parent-owned Windows test process.

No process enumeration, memory reads, VM_READ privilege or station authority.
The caller keeps its Child handle and final-handshake pipe alive until close.
"""

import argparse
import ctypes
import datetime
import json
import os
import sys

DWORD = ctypes.c_uint32
BOOL = ctypes.c_int32
HANDLE = ctypes.c_void_p
SIZE_T = ctypes.c_size_t
QUERY_LIMITED_INFORMATION = 0x1000
PROCESS_DUP_HANDLE = 0x40
SYNCHRONIZE = 0x100000
WAIT_OBJECT_0, WAIT_TIMEOUT, WAIT_FAILED = 0, 258, 0xFFFFFFFF


class FileTime(ctypes.Structure):
    _fields_ = [("low", DWORD), ("high", DWORD)]

    def ticks(self):
        return (int(self.high) << 32) | int(self.low)


class ProcessMemoryCountersEx(ctypes.Structure):
    _fields_ = [("cb", DWORD), ("PageFaultCount", DWORD)] + [
        (name, SIZE_T)
        for name in (
            "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
            "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage",
            "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage", "PrivateUsage",
        )
    ]


class MetricsError(Exception):
    def __init__(self, operation, code=None):
        super().__init__(operation)
        self.operation, self.code = operation, code


def checked_layout():
    offsets = [getattr(ProcessMemoryCountersEx, name).offset
               for name, _ in ProcessMemoryCountersEx._fields_]
    if (ctypes.sizeof(HANDLE), ctypes.sizeof(SIZE_T), ctypes.sizeof(DWORD),
            ctypes.sizeof(BOOL), ctypes.sizeof(FileTime),
            ctypes.sizeof(ProcessMemoryCountersEx), ctypes.alignment(ProcessMemoryCountersEx), offsets) != (
                8, 8, 4, 4, 8, 80, 8, [0, 4, 8, 16, 24, 32, 40, 48, 56, 64, 72]):
        raise MetricsError("unsupported_native_layout")
    return 80


def positive_integer(value, field, maximum=(1 << 64) - 1):
    if type(value) is not int or not 0 < value <= maximum:
        raise MetricsError("invalid_" + field)
    return value


class NativeApi:
    def __init__(self):
        if sys.platform != "win32":
            raise MetricsError("unsupported_host")
        checked_layout()
        self.dll = ctypes.WinDLL("kernel32", use_last_error=True)
        self.open = self.dll.OpenProcess
        self.open.argtypes = [DWORD, BOOL, DWORD]
        self.open.restype = HANDLE
        self.memory = self.dll.K32GetProcessMemoryInfo
        self.memory.argtypes = [HANDLE, ctypes.POINTER(ProcessMemoryCountersEx), DWORD]
        self.memory.restype = BOOL
        self.times = self.dll.GetProcessTimes
        self.times.argtypes = [HANDLE] + [ctypes.POINTER(FileTime)] * 4
        self.times.restype = BOOL
        self.close = self.dll.CloseHandle
        self.close.argtypes = [HANDLE]
        self.close.restype = BOOL
        self.wait = self.dll.WaitForSingleObject
        self.wait.argtypes = [HANDLE, DWORD]
        self.wait.restype = DWORD
        self.duplicate = self.dll.DuplicateHandle
        self.duplicate.argtypes = [HANDLE, HANDLE, HANDLE, ctypes.POINTER(HANDLE), DWORD, BOOL, DWORD]
        self.duplicate.restype = BOOL
        self.current = self.dll.GetCurrentProcess
        self.current.argtypes = []
        self.current.restype = HANDLE
        self.process_id = self.dll.GetProcessId
        self.process_id.argtypes = [HANDLE]
        self.process_id.restype = DWORD

    @staticmethod
    def last_error():
        return ctypes.get_last_error()


class OwnedProcess:
    @classmethod
    def from_local_parent_handle(cls, source_handle, expected_pid, api=None):
        """Duplicate this caller's retained Popen handle; never reopen by PID."""
        checked_layout()
        source_handle = positive_integer(source_handle, "source_handle")
        if source_handle == (1 << 64) - 1:
            raise MetricsError("invalid_source_handle")
        pid = positive_integer(expected_pid, "pid", (1 << 32) - 1)
        native = api if api is not None else NativeApi()
        target = HANDLE()
        current = native.current()
        if not native.duplicate(current, source_handle, current, ctypes.byref(target),
                                QUERY_LIMITED_INFORMATION | SYNCHRONIZE, False, 0):
            raise MetricsError("DuplicateHandle", native.last_error())
        if not target.value:
            raise MetricsError("invalid_duplicate_handle")
        process = cls.__new__(cls)
        process.pid, process.creation = pid, None
        process.api, process.handle = native, target.value
        try:
            if native.process_id(process.handle) != pid:
                raise MetricsError("process_object_identity_mismatch")
            process._identity()
        except BaseException:
            process.close()
            raise
        return process

    @classmethod
    def from_parent_handle(cls, source_handle, expected_pid, api=None):
        checked_layout()
        source_handle = positive_integer(source_handle, "source_handle")
        if source_handle == (1 << 64) - 1:
            raise MetricsError("invalid_source_handle")
        pid = positive_integer(expected_pid, "pid", (1 << 32) - 1)
        native = api if api is not None else NativeApi()
        parent_pid = positive_integer(os.getppid(), "parent_pid", (1 << 32) - 1)
        parent = native.open(PROCESS_DUP_HANDLE, False, parent_pid)
        if not parent:
            raise MetricsError("OpenProcessParent", native.last_error())
        target = HANDLE()
        duplicated = False
        try:
            if not native.duplicate(parent, source_handle, native.current(), ctypes.byref(target),
                                    QUERY_LIMITED_INFORMATION | SYNCHRONIZE, False, 0):
                raise MetricsError("DuplicateHandle", native.last_error())
            if not target.value:
                raise MetricsError("invalid_duplicate_handle")
            duplicated = True
        finally:
            if not native.close(parent):
                code = native.last_error()
                if duplicated:
                    native.close(target.value)
                raise MetricsError("CloseParentHandle", code)
        process = cls.__new__(cls)
        process.pid, process.creation = pid, None
        process.api, process.handle = native, target.value
        try:
            actual_pid = native.process_id(process.handle)
            if not actual_pid:
                raise MetricsError("GetProcessId", native.last_error())
            if actual_pid != pid:
                raise MetricsError("process_object_identity_mismatch")
            process._identity()
        except BaseException:
            process.close()
            raise
        return process

    def __init__(self, pid, expected_creation, api=None):
        self.pid = positive_integer(pid, "pid", (1 << 32) - 1)
        self.creation = positive_integer(expected_creation, "creation")
        checked_layout()
        self.api = api if api is not None else NativeApi()
        self.handle = self.api.open(QUERY_LIMITED_INFORMATION | SYNCHRONIZE, False, self.pid)
        if not self.handle:
            raise MetricsError("OpenProcess", self.api.last_error())
        try:
            self._identity()
        except BaseException:
            self.close()
            raise

    def _identity(self):
        if self.handle is None:
            raise MetricsError("closed_handle")
        live(self.api, self.handle)
        created, exited, kernel, user = (FileTime() for _ in range(4))
        if not self.api.times(self.handle, ctypes.byref(created), ctypes.byref(exited),
                              ctypes.byref(kernel), ctypes.byref(user)):
            raise MetricsError("GetProcessTimes", self.api.last_error())
        if self.creation is None:
            self.creation = positive_integer(created.ticks(), "creation")
        elif created.ticks() != self.creation:
            raise MetricsError("creation_identity_mismatch")
        live(self.api, self.handle)
        return kernel.ticks() + user.ticks()

    def sample(self):
        self._identity()
        counters = ProcessMemoryCountersEx()
        counters.cb = checked_layout()
        if not self.api.memory(self.handle, ctypes.byref(counters), counters.cb):
            raise MetricsError("K32GetProcessMemoryInfo", self.api.last_error())
        cpu = self._identity()
        if counters.cb != checked_layout() or not counters.PrivateUsage or not counters.PeakPagefileUsage:
            raise MetricsError("invalid_memory_counters")
        return {
            "v": 1, "pid": self.pid, "creation_filetime": self.creation,
            "observed_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "unit": "bytes", "private_usage": int(counters.PrivateUsage),
            "pagefile_usage": int(counters.PagefileUsage),
            "lifetime_peak_commit": int(counters.PeakPagefileUsage),
            "process_cpu_100ns": cpu,
        }

    def close(self):
        handle, self.handle = self.handle, None
        if handle is not None and not self.api.close(handle):
            raise MetricsError("CloseHandle", self.api.last_error())

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()


def parent_creation(api):
    """Bootstrap only the waiting test caller, never a caller-supplied foreign PID."""
    pid = positive_integer(os.getppid(), "parent_pid", (1 << 32) - 1)
    handle = api.open(QUERY_LIMITED_INFORMATION | SYNCHRONIZE, False, pid)
    if not handle:
        raise MetricsError("OpenProcess", api.last_error())
    try:
        live(api, handle)
        created, exited, kernel, user = (FileTime() for _ in range(4))
        if not api.times(handle, ctypes.byref(created), ctypes.byref(exited),
                         ctypes.byref(kernel), ctypes.byref(user)):
            raise MetricsError("GetProcessTimes", api.last_error())
        live(api, handle)
        return {"v": 1, "pid": pid, "creation_filetime": created.ticks()}
    finally:
        if not api.close(handle):
            raise MetricsError("CloseHandle", api.last_error())


def live(api, handle):
    state = api.wait(handle, 0)
    if state == WAIT_TIMEOUT:
        return
    if state == WAIT_FAILED:
        raise MetricsError("WaitForSingleObject", api.last_error())
    if state == WAIT_OBJECT_0:
        raise MetricsError("process_not_live")
    raise MetricsError("unexpected_process_wait_state")


def emit(value):
    text = json.dumps(value, separators=(",", ":"), allow_nan=False)
    if len(text.encode("utf-8")) > 2048:
        raise MetricsError("output_limit")
    print(text, flush=True)


def exact_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise MetricsError("duplicate_key")
        result[key] = value
    return result


def serve(pid, creation, stream, api=None, parent_handle=None):
    if parent_handle is not None:
        if creation is not None:
            raise MetricsError("invalid_request")
        process = OwnedProcess.from_parent_handle(parent_handle, pid, api)
    else:
        process = OwnedProcess(pid, creation, api)
    with process:
        emit({"v": 1, "state": "bound", "pid": process.pid, "creation_filetime": process.creation})
        previous = 0
        while True:
            line = stream.readline(4097)
            if not line:
                return
            if len(line.encode("utf-8")) > 4096 or not line.endswith("\n"):
                raise MetricsError("input_limit")
            request = json.loads(line, object_pairs_hook=exact_object)
            if type(request) is not dict or set(request) != {"op", "id"}:
                raise MetricsError("invalid_request")
            sequence = positive_integer(request["id"], "sequence", (1 << 53) - 1)
            if sequence <= previous or request["op"] not in ("sample", "close"):
                raise MetricsError("invalid_request")
            previous = sequence
            if request["op"] == "close":
                process.close()
                emit({"v": 1, "id": sequence, "state": "closed"})
                return
            emit({"id": sequence, **process.sample()})


def main():
    if "--capacity-pins" in sys.argv:
        return capacity_main()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parent-identity", action="store_true")
    parser.add_argument("--pid", type=int)
    parser.add_argument("--creation", type=int)
    parser.add_argument("--parent-handle", type=int)
    args = parser.parse_args()
    try:
        if args.parent_identity:
            if args.pid is not None or args.creation is not None or args.parent_handle is not None:
                raise MetricsError("invalid_request")
            emit(parent_creation(NativeApi()))
        else:
            serve(args.pid, args.creation, sys.stdin, parent_handle=args.parent_handle)
    except (MetricsError, ValueError, TypeError) as error:
        emit({"v": 1, "error": getattr(error, "operation", "invalid_request"),
              "winerror": getattr(error, "code", None)})
        return 1
    return 0


CAPACITY_CASE = "decoder::search::tests::resource_capacity_owned_child"


def pe_image_size(data):
    """Conservatively charge every mapped main-image section, not file length."""
    import struct
    if len(data) < 64 or data[:2] != b"MZ":
        raise MetricsError("invalid_pe")
    offset = struct.unpack_from("<I", data, 60)[0]
    if offset > len(data) - 24 or data[offset:offset+4] != b"PE\0\0":
        raise MetricsError("invalid_pe")
    machine, sections = struct.unpack_from("<HH", data, offset+4)
    optional_size = struct.unpack_from("<H", data, offset+20)[0]
    optional = offset+24
    if machine != 0x8664 or not sections or optional_size < 112 or optional+optional_size > len(data):
        raise MetricsError("unsupported_pe")
    if struct.unpack_from("<H", data, optional)[0] != 0x20B:
        raise MetricsError("unsupported_pe")
    size = struct.unpack_from("<I", data, optional+56)[0]
    headers = struct.unpack_from("<I", data, optional+60)[0]
    table = optional+optional_size
    if not 0 < headers <= size or table+40*sections > len(data):
        raise MetricsError("invalid_pe")
    for index in range(sections):
        virtual_size, address, raw_size = struct.unpack_from("<III", data, table+40*index+8)
        if address+max(virtual_size, raw_size) > size:
            raise MetricsError("invalid_pe_section")
    return size


class CapacityProtocol:
    def __init__(self, nonce):
        self.nonce, self.state = nonce, "WAIT_READY"

    def accept(self, record):
        if type(record) is not dict or set(record) != {"state", "nonce"} or record["nonce"] != self.nonce:
            raise MetricsError("capacity_nonce_or_shape")
        expected = {"WAIT_READY": "READY", "WORKING": "FINISHED"}.get(self.state)
        if record["state"] != expected:
            raise MetricsError("capacity_protocol_order")
        self.state = "WORKING" if expected == "READY" else "FINISHED"
        return expected


def finish_capacity_child(child, deadline, clock, receipt):
    """No fresh timeout; cleanup remains inside the original operational budget."""
    if child.poll() is None:
        receipt["kill_attempted"] = True
        try:
            child.kill()
        except OSError as error:
            receipt["kill_error"] = repr(error)
    try:
        child.wait(timeout=max(0.0, deadline-clock()))
    except TimeoutError as error:
        receipt["wait_error"] = repr(error)
    # subprocess.TimeoutExpired is not a TimeoutError; the caller retains it below.
    except Exception as error:
        receipt["wait_error"] = repr(error)
    receipt.update(exit_code=child.returncode, cleanup_complete=child.poll() is not None)


def capacity_main():
    """One reviewed, descendant-free release-lib child; no metadata subprocesses."""
    import hashlib
    from pathlib import Path
    import queue
    import secrets
    import subprocess
    import threading
    import time
    started = time.monotonic()
    deadline = started+300
    parser = argparse.ArgumentParser()
    parser.add_argument("--capacity-pins", required=True)
    parser.add_argument("--capacity-pins-sha", required=True)
    parser.add_argument("--capacity-out", required=True)
    args = parser.parse_args()
    if sys.flags.optimize or not __debug__:
        raise MetricsError("assertions_disabled")
    digest = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
    if digest(args.capacity_pins) != args.capacity_pins_sha:
        raise MetricsError("unreviewed_capacity_pins")
    pins = json.loads(Path(args.capacity_pins).read_text(encoding="utf-8-sig"), object_pairs_hook=exact_object)
    for name in ("source_commit", "compiler", "host", "exe", "cache", "files", "root_clean_source_attestation"):
        if not pins.get(name):
            raise MetricsError("missing_capacity_pin_"+name)
    for path, expected in pins["files"].items():
        if digest(path) != expected:
            raise MetricsError("capacity_input_drift")
    # Bind actual launch/inputs/helper bytes, rather than merely any caller-listed files.
    required = [str(Path(pins["exe"]).resolve()), str(Path(__file__).resolve())]
    required += [str((Path(pins["cache"])/name/"000000_000000.wav").resolve())
                 for name in ("ft8-strong-00", "ft4-strong-00")]
    resolved = {str(Path(path).resolve()): expected for path, expected in pins["files"].items()}
    if any(path not in resolved for path in required):
        raise MetricsError("missing_launch_or_input_pin")
    # Immutable input truth comes from the admitted fixture, not caller-selected hashes.
    if [resolved[path] for path in required[2:]] != [
            "02525d0ebe7661935d52e60f169501aae2428983a72a1e1a0c8087ddce322d51",
            "17efa54767abee26df1116894f84c56c014135ac6aabf17277358d6ca55d7f36"]:
        raise MetricsError("wrong_capacity_input")
    image_size = pe_image_size(Path(pins["exe"]).read_bytes())
    out = Path(args.capacity_out)
    out.mkdir(parents=True, exist_ok=False)
    nonce = secrets.token_hex(16)
    command = [pins["exe"], "--exact", CAPACITY_CASE, "--ignored", "--nocapture", "--test-threads=1"]
    receipt = {"command": command, "pins": pins, "pins_sha256": args.capacity_pins_sha,
               "owner_pid": os.getpid(), "python_executable": sys.executable,
               "python_version": sys.version, "python_binary_sha256": digest(sys.executable),
               "owner_assertions_enabled": __debug__, "owner_optimize": sys.flags.optimize,
               "source_cleanliness_verification": "root attested; owner rechecked listed file hashes only",
               "host_qualification": "supplemental actual host; not canonical reference qualification",
               "main_pe_size_of_image": image_size, "operational_budget_seconds": 300,
               "cleanup_reserve_seconds": 10, "complete": False, "workspace_proof": "INCONCLUSIVE",
               "station_96mib_proved": False, "events": [], "samples": [], "reader_joined": False}
    events = queue.Queue(maxsize=128)
    child = process = None
    readers = []
    protocol = CapacityProtocol(nonce)
    def read_stream(stream, name):
        total = 0
        try:
            with (out/(name+".log")).open("w", encoding="utf-8") as log:
                while True:
                    line = stream.readline(16385)
                    if not line:
                        break
                    total += len(line)
                    if len(line) > 16384 or total > 4_000_000:
                        events.put_nowait(("error", "output_limit")); return
                    log.write(line); log.flush()
                    if line.startswith("RESOURCE_"):
                        events.put_nowait(("record", line))
        except BaseException as error:
            try: events.put_nowait(("error", repr(error)))
            except queue.Full: pass
        finally:
            try: events.put_nowait(("eof", name))
            except queue.Full: pass
    try:
        if deadline-time.monotonic() <= 10:
            raise MetricsError("capacity_deadline_before_spawn")
        env = dict(os.environ)
        env.update(WSTX_RESOURCE_CAPACITY_NONCE=nonce, WSTX_DECODER_CACHE=pins["cache"])
        child = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 text=True, encoding="utf-8", cwd=Path(pins["exe"]).parent, env=env)
        receipt["owned_pid"] = child.pid
        for name, stream in (("stdout", child.stdout), ("stderr", child.stderr)):
            thread = threading.Thread(target=read_stream, args=(stream, name), daemon=True)
            thread.start(); readers.append(thread)
        process = OwnedProcess.from_local_parent_handle(int(child._handle), child.pid)
        eof = 0
        while protocol.state != "FINISHED":
            remaining = deadline-time.monotonic()-10
            if remaining <= 0:
                raise MetricsError("capacity_timeout")
            try: kind, value = events.get(timeout=remaining)
            except queue.Empty: raise MetricsError("capacity_timeout") from None
            if kind == "error":
                raise MetricsError("capacity_reader_"+value)
            if kind == "eof":
                eof += 1
                if eof == 2: raise MetricsError("capacity_early_eof")
                continue
            prefix, text = value.split(" ", 1)
            if prefix not in {"RESOURCE_HANDSHAKE", "RESOURCE_STORAGE", "RESOURCE_CAPACITY", "RESOURCE_KERNEL", "RESOURCE_DISPOSITION"}:
                raise MetricsError("capacity_unknown_record")
            if prefix != "RESOURCE_HANDSHAKE" and protocol.state != "WORKING":
                raise MetricsError("capacity_record_outside_work")
            data = json.loads(text, object_pairs_hook=exact_object)
            receipt["events"].append({"kind": prefix, "data": data})
            if prefix == "RESOURCE_HANDSHAKE":
                state = protocol.accept(data)
                receipt["samples"].append(process.sample())
                child.stdin.write(("START" if state == "READY" else "RELEASE")+" "+nonce+"\n")
                child.stdin.flush()
        child.stdin.close()
        child.wait(timeout=max(0, deadline-time.monotonic()-10))
        for thread in readers: thread.join(timeout=max(0, deadline-time.monotonic()))
        # Drain remaining records: a duplicate FINISHED or trailing unknown event cannot pass.
        while not events.empty():
            kind, value = events.get_nowait()
            if kind not in ("eof",): raise MetricsError("capacity_trailing_record")
        stdout = (out/"stdout.log").read_text(encoding="utf-8")
        kernels = [r["data"] for r in receipt["events"] if r["kind"] == "RESOURCE_KERNEL"]
        dispositions = [r["data"] for r in receipt["events"] if r["kind"] == "RESOURCE_DISPOSITION"]
        if (child.returncode != 0 or len(kernels) != 4 or
                {(k["mode"],k["scalar"]) for k in kernels} != {(m,s) for m in ("ft8","ft4") for s in (False,True)} or
                not all(k["complete"] and k["frames"] == 360000 and k["actual_decoded_callbacks"] > 0 for k in kernels) or
                len(dispositions) != 1 or not dispositions[0]["all_test_owners_dropped"] or
                "test result: ok. 1 passed; 0 failed; 0 ignored;" not in stdout or
                any(thread.is_alive() for thread in readers)):
            raise MetricsError("capacity_incomplete_evidence")
        receipt["absolute_peak_plus_main_image_bytes"] = max(s["lifetime_peak_commit"] for s in receipt["samples"])+image_size
        receipt["other_nonprivate_and_unexercised_capacity_allowance_bytes"] = None
        receipt["complete"] = True
    except BaseException as error:
        receipt["failure"] = {"type": type(error).__name__, "message": str(error)}
    finally:
        if child is not None:
            if child.stdin and not child.stdin.closed:
                try: child.stdin.close()
                except OSError as error:
                    receipt["stdin_close_error"] = repr(error)
                    receipt["complete"] = False
            finish_capacity_child(child, deadline, time.monotonic, receipt)
            for thread in readers: thread.join(timeout=max(0, deadline-time.monotonic()))
            receipt["reader_joined"] = not any(t.is_alive() for t in readers)
            for stream in (child.stdout, child.stderr):
                if stream and receipt["reader_joined"]: stream.close()
        if process is not None:
            try: process.close()
            except MetricsError as error:
                receipt["query_close_error"] = str(error); receipt["complete"] = False
        receipt["elapsed_seconds"] = time.monotonic()-started
        receipt["complete"] = bool(receipt["complete"] and receipt.get("cleanup_complete") and receipt["reader_joined"])
        (out/"receipt.json").write_text(json.dumps(receipt, indent=2)+"\n", encoding="utf-8")
    return 0 if receipt["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

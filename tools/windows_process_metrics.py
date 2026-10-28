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

    @staticmethod
    def last_error():
        return ctypes.get_last_error()


class OwnedProcess:
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
        if created.ticks() != self.creation:
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


def serve(pid, creation, stream, api=None):
    with OwnedProcess(pid, creation, api) as process:
        emit({"v": 1, "state": "bound", "pid": pid, "creation_filetime": creation})
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--parent-identity", action="store_true")
    parser.add_argument("--pid", type=int)
    parser.add_argument("--creation", type=int)
    args = parser.parse_args()
    try:
        if args.parent_identity:
            if args.pid is not None or args.creation is not None:
                raise MetricsError("invalid_request")
            emit(parent_creation(NativeApi()))
        else:
            serve(args.pid, args.creation, sys.stdin)
    except (MetricsError, ValueError, TypeError) as error:
        emit({"v": 1, "error": getattr(error, "operation", "invalid_request"),
              "winerror": getattr(error, "code", None)})
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Own the two reviewed decoder resource selections in a Windows Job.

The resolver never starts a process. Importing this module never loads a DLL.
Ordinary Cargo coverage and the selected executable share one producer stream.
"""

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import secrets
import subprocess
import sys
import threading
import time
import tomllib


DWORD = ctypes.c_uint32
BOOL = ctypes.c_int32
HANDLE = ctypes.c_void_p
SIZE_T = ctypes.c_size_t
LARGE_INTEGER = ctypes.c_int64
ULONG_PTR = ctypes.c_size_t
KILL_ON_JOB_CLOSE = 0x2000
EXTENDED_LIMIT_INFORMATION = 9
BASIC_ACCOUNTING_INFORMATION = 1
MAX_LINE = 1024 * 1024
MAX_STREAM = 64 * 1024 * 1024
MAX_RUN_STREAM = 256 * 1024 * 1024
MAX_RUN_LINE = 4 * 1024 * 1024
READY_PREFIX = "WSTX_GUARDIAN_READY "
GO_PREFIX = "WSTX_GUARDIAN_GO "
MATRIX = "release_runtime_and_overlapping_window_history"
BUSY = "resource_busy_live_overlap_and_pending_cancel"
IGNORED = ("resource_finite_child", BUSY)
ORDINARY = (
    "independent_waveforms_decode", "quality_corpus",
    "cooperative_quanta_and_partial_cancellation", "planned_scalar_and_gain_invariance",
    "unmodulated_sources_are_not_frames", "crc_valid_unsupported_and_invalid_payloads_are_retained",
    "fixture_cache_refuses_forged_observations", "phase_drift_dynamic_range_and_residual_regressions",
    "official_modern_recording_baselines",
    "resource_owned_worker_failure_cleanup_uses_process_object_not_pid_reopen",
    "resource_concurrency_qualification_rejects_serial_work_and_clock_faults",
    "physical_noise_reproduction_has_no_frame", "same_frequency_preserves_two_temporal_frames",
    "physical_wrong_mode_reproduction_has_no_frame_or_search_error",
    "live_busy_period_publishes_every_decode_promptly",
)
ORDINARY_ARGV = (
    "cargo", "test", "--release", "--locked", "--test", "decoder_signal",
    "--message-format=json", "--", "--test-threads=1", "--skip", MATRIX,
)
CASES = {"matrix": MATRIX, "busy": BUSY}
# #36: the decoder_signal matrix re-measures a configuration whose 50 ms CPU quantum
# was not established up to this many attempts (RESOURCE_QUALIFICATION_ATTEMPTS).
QUALIFICATION_ATTEMPTS = 3
CPU_QUANTUM_WALL_SECONDS = 0.050
QUALIFIED, INCONCLUSIVE = "qualified", "inconclusive"
# Exit status of a strict (default) run whose matrix stayed inconclusive: a refusal.
INCONCLUSIVE_REFUSED = 3
# Exit status of an ordinary-gate run whose matrix stayed inconclusive: the harness
# reserved NOT RUN code (core/docs/CR-Process.md), neither a pass nor red.
NOT_RUN = 77
INPUT_ENV = (
    "WSTX_SAMPLE_DIR", "WSTX_DECODER_CACHE", "WSTX_DECODER_VECTORS",
    "WSTX_DECODER_SYNCHRONIZATION", "WSTX_DECODER_OFFICIAL_FT8",
)


class JobError(Exception):
    def __init__(self, operation, code=None):
        super().__init__(operation)
        self.operation, self.code = operation, code


def require(condition, operation):
    if not condition:
        raise JobError(operation)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def decode_json(raw):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, "duplicate_json_key")
            result[key] = value
        return result

    def invalid_constant(_value):
        raise JobError("invalid_json_constant")

    return json.loads(raw, object_pairs_hook=unique, parse_constant=invalid_constant)


def write_new(path, value):
    with Path(path).open("xb") as stream:
        stream.write(json_bytes(value))


def positive_handle(handle):
    require(type(handle) is int and 0 < handle < (1 << 64) - 1, "invalid_owned_handle")
    return handle


class BasicLimit(ctypes.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", LARGE_INTEGER), ("PerJobUserTimeLimit", LARGE_INTEGER),
        ("LimitFlags", DWORD), ("MinimumWorkingSetSize", SIZE_T),
        ("MaximumWorkingSetSize", SIZE_T), ("ActiveProcessLimit", DWORD),
        ("Affinity", ULONG_PTR), ("PriorityClass", DWORD), ("SchedulingClass", DWORD),
    ]


class IoCounters(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in (
        "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
        "ReadTransferCount", "WriteTransferCount", "OtherTransferCount",
    )]


class ExtendedLimit(ctypes.Structure):
    _fields_ = [("BasicLimitInformation", BasicLimit), ("IoInfo", IoCounters)] + [
        (name, SIZE_T) for name in (
            "ProcessMemoryLimit", "JobMemoryLimit", "PeakProcessMemoryUsed", "PeakJobMemoryUsed",
        )
    ]


class BasicAccounting(ctypes.Structure):
    _fields_ = [(name, LARGE_INTEGER) for name in (
        "TotalUserTime", "TotalKernelTime", "ThisPeriodTotalUserTime", "ThisPeriodTotalKernelTime",
    )] + [(name, DWORD) for name in (
        "TotalPageFaultCount", "TotalProcesses", "ActiveProcesses", "TotalTerminatedProcesses",
    )]


def checked_layout():
    expected = (
        (BasicLimit, 64, [0, 8, 16, 24, 32, 40, 48, 56, 60]),
        (IoCounters, 48, [0, 8, 16, 24, 32, 40]),
        (ExtendedLimit, 144, [0, 64, 112, 120, 128, 136]),
        (BasicAccounting, 48, [0, 8, 16, 24, 32, 36, 40, 44]),
    )
    require((ctypes.sizeof(HANDLE), ctypes.sizeof(SIZE_T), ctypes.sizeof(DWORD),
             ctypes.sizeof(BOOL)) == (8, 8, 4, 4), "unsupported_native_layout")
    for structure, size, offsets in expected:
        require(ctypes.sizeof(structure) == size and ctypes.alignment(structure) == 8 and
                [getattr(structure, name).offset for name, _ in structure._fields_] == offsets,
                "unsupported_native_layout")


class NativeApi:
    def __init__(self):
        require(sys.platform == "win32", "unsupported_host")
        checked_layout()
        self.dll = ctypes.WinDLL("kernel32", use_last_error=True)
        specifications = (
            ("create", "CreateJobObjectW", [ctypes.c_void_p, ctypes.c_wchar_p], HANDLE),
            ("set", "SetInformationJobObject", [HANDLE, ctypes.c_int, ctypes.c_void_p, DWORD], BOOL),
            ("assign", "AssignProcessToJobObject", [HANDLE, HANDLE], BOOL),
            ("query", "QueryInformationJobObject",
             [HANDLE, ctypes.c_int, ctypes.c_void_p, DWORD, ctypes.POINTER(DWORD)], BOOL),
            ("terminate", "TerminateJobObject", [HANDLE, ctypes.c_uint], BOOL),
            ("close", "CloseHandle", [HANDLE], BOOL),
        )
        for attribute, name, arguments, result in specifications:
            function = getattr(self.dll, name)
            function.argtypes, function.restype = arguments, result
            setattr(self, attribute, function)

    @staticmethod
    def last_error():
        return ctypes.get_last_error()


class OwnedJob:
    """The only close/terminate target is this object's newly created Job handle."""

    def __init__(self, api=None):
        checked_layout()
        self.api = api if api is not None else NativeApi()
        self.handle = None
        handle = self.api.create(None, None)
        self.handle = positive_handle(handle)
        limits = ExtendedLimit()
        limits.BasicLimitInformation.LimitFlags = KILL_ON_JOB_CLOSE
        try:
            if not self.api.set(self.handle, EXTENDED_LIMIT_INFORMATION,
                                ctypes.byref(limits), ctypes.sizeof(limits)):
                raise JobError("SetInformationJobObject", self.api.last_error())
        except BaseException:
            self.close()
            raise

    def assign(self, retained_process_handle):
        positive_handle(self.handle)
        positive_handle(retained_process_handle)
        if not self.api.assign(self.handle, retained_process_handle):
            raise JobError("AssignProcessToJobObject", self.api.last_error())

    def active(self):
        positive_handle(self.handle)
        accounting, returned = BasicAccounting(), DWORD()
        if not self.api.query(self.handle, BASIC_ACCOUNTING_INFORMATION, ctypes.byref(accounting),
                              ctypes.sizeof(accounting), ctypes.byref(returned)):
            raise JobError("QueryInformationJobObject", self.api.last_error())
        require(returned.value == ctypes.sizeof(accounting), "incomplete_job_accounting")
        return int(accounting.ActiveProcesses)

    def terminate(self):
        positive_handle(self.handle)
        if not self.api.terminate(self.handle, 1):
            raise JobError("TerminateJobObject", self.api.last_error())

    def close(self):
        if self.handle is not None:
            positive_handle(self.handle)
            if not self.api.close(self.handle):
                raise JobError("CloseJobHandle", self.api.last_error())
            self.handle = None


def source_snapshot(root):
    root = Path(root).resolve(strict=True)
    paths = {
        "Cargo.toml", "Cargo.lock", "rust-toolchain.toml", "server/Cargo.toml",
        "server/tests/decoder_signal.rs", ".harness/suites.yaml",
        "tools/windows_resource_job.py", "tools/test_windows_resource_job.py",
        "tools/windows_process_metrics.py", "tools/test_windows_process_metrics.py",
    }
    for directory in ("server/src", "fixtures/decoder"):
        paths.update(path.relative_to(root).as_posix() for path in (root / directory).rglob("*")
                     if path.is_file() and "__pycache__" not in path.parts and
                     path.suffix not in (".pyc", ".pyo"))
    result = {}
    for relative in sorted(paths):
        path = root / relative
        require(path.is_file() and path.resolve(strict=True).is_relative_to(root),
                "invalid_source_input")
        result[relative] = digest(path)
    return result


def source_inventory(source):
    text = Path(source).read_text(encoding="utf-8")
    require('#![cfg(not(debug_assertions))]' in text.splitlines()[:3], "missing_release_guard")
    matches = re.findall(r"(?m)^#\[test\]\r?\n((?:#\[[^\n]*\]\r?\n)*)fn (\w+)\(", text)
    names, ignored = [], []
    for attributes, name in matches:
        names.append(name)
        if "#[ignore" in attributes:
            ignored.append(name)
    require(len(names) == 18 and len(set(names)) == 18 and
            set(names) == set(ORDINARY) | {MATRIX, *IGNORED} and
            set(ignored) == set(IGNORED), "source_inventory_mismatch")
    return {"names": sorted(names), "ignored": sorted(ignored)}


def artifact_path(executable, target_dir):
    require(isinstance(executable, str) and bool(executable), "invalid_artifact_path")
    path = Path(executable)
    require(path.is_absolute() and path.is_file(), "invalid_artifact_path")
    actual = path.resolve(strict=True)
    require(actual == path, "noncanonical_artifact_path")
    target = Path(target_dir).resolve()
    allowed = {target / "release" / "deps", target / "x86_64-pc-windows-msvc" / "release" / "deps"}
    require(actual.parent in allowed and actual.suffix.lower() == ".exe" and
            re.fullmatch(r"decoder_signal-[0-9a-f]+\.exe", actual.name) is not None,
            "artifact_outside_release_target")
    return actual


class Coverage:
    def __init__(self, active, ignored, filtered):
        self.active, self.ignored, self.filtered = set(active), set(ignored), filtered
        self.outcomes, self.summary = {}, None

    def accept(self, text):
        outcome = re.fullmatch(r"test (\w+) \.\.\. (ok|FAILED|ignored(?:,.*)?)", text)
        if outcome:
            name, result = outcome.groups()
            require(name not in self.outcomes and name in self.active | self.ignored,
                    "unexpected_test_outcome")
            require((name in self.active and result == "ok") or
                    (name in self.ignored and result.startswith("ignored")), "failed_test_outcome")
            self.outcomes[name] = "ignored" if result.startswith("ignored") else result
        elif text.startswith("test result:"):
            summary = re.fullmatch(
                r"test result: ok\. (\d+) passed; (\d+) failed; (\d+) ignored; "
                r"(\d+) measured; (\d+) filtered out; finished in .+", text)
            require(summary is not None and self.summary is None, "invalid_test_summary")
            self.summary = tuple(int(number) for number in summary.groups())

    def finish(self):
        require(set(self.outcomes) == self.active | self.ignored and
                self.summary == (len(self.active), 0, len(self.ignored), 0, self.filtered),
                "incomplete_test_coverage")
        return {"outcomes": self.outcomes, "summary": list(self.summary)}


def resolve_stream(stream, stream_log, receipt_path, root, target_dir):
    """Consume only supplied bytes; no subprocess or native API is used here."""
    root = Path(root).resolve(strict=True)
    inventory = source_inventory(root / "server/tests/decoder_signal.rs")
    initial = source_snapshot(root)
    environment = {name: os.environ.get(name) for name in INPUT_ENV}
    coverage = Coverage(ORDINARY, IGNORED, 1)
    manifest = root / "server/Cargo.toml"
    package = tomllib.loads(manifest.read_text(encoding="utf-8"))["package"]["name"]
    version = tomllib.loads((root / "Cargo.toml").read_text(encoding="utf-8"))["workspace"]["package"]["version"]
    package_id = manifest.parent.as_uri()
    expected_package = f"path+{package_id}#{package}@{version}"
    artifact, artifact_hash, build_finished, total = None, None, None, 0
    first_error = None
    with Path(stream_log).open("xb") as log:
        while True:
            line = stream.readline(MAX_LINE + 1)
            if not line:
                break
            total += len(line)
            require(len(line) <= MAX_LINE and total <= MAX_STREAM and line.endswith(b"\n"),
                    "producer_stream_limit")
            log.write(line)
            try:
                text = line.decode("utf-8").rstrip("\r\n")
                if text.startswith("{"):
                    message = decode_json(text)
                    require(isinstance(message, dict), "invalid_cargo_record")
                    if message.get("reason") == "build-finished":
                        require(build_finished is None and message.get("success") is True,
                                "unsuccessful_or_duplicate_build")
                        build_finished = message
                    elif message.get("reason") == "compiler-artifact" and (
                            message.get("target", {}).get("name") == "decoder_signal" or
                            message.get("executable") and "decoder_signal-" in str(message["executable"])):
                        target, profile = message.get("target", {}), message.get("profile", {})
                        require(artifact is None and message.get("package_id") == expected_package and
                                Path(message.get("manifest_path", "")).resolve() == manifest and
                                target.get("name") == "decoder_signal" and target.get("kind") == ["test"] and
                                Path(target.get("src_path", "")).resolve() == root / "server/tests/decoder_signal.rs" and
                                profile.get("test") is True and str(profile.get("opt_level")) == "3" and
                                profile.get("debug_assertions") is False, "wrong_or_duplicate_artifact")
                        artifact = artifact_path(message.get("executable", ""), target_dir)
                        artifact_hash = digest(artifact)
                else:
                    coverage.accept(text)
            except Exception as error:
                # Still drain/preserve the bounded producer stream; a bad early JSON
                # record must not turn a later success into a valid handoff.
                if first_error is None:
                    first_error = error
    if first_error is not None:
        raise first_error
    require(build_finished is not None and artifact is not None, "missing_cargo_artifact_or_eof_build")
    covered = coverage.finish()
    require(source_snapshot(root) == initial and digest(artifact) == artifact_hash,
            "producer_inputs_changed")
    receipt = {
        "v": 1, "root": str(root), "target_dir": str(Path(target_dir).resolve()),
        "artifact": str(artifact), "artifact_sha256": artifact_hash, "source_pins": initial,
        "inventory": inventory, "ordinary_argv": list(ORDINARY_ARGV), "coverage": covered,
        "input_environment": environment, "stream": str(Path(stream_log).resolve()),
        "stream_sha256": digest(stream_log), "handoff_nonce": secrets.token_hex(16),
    }
    write_new(receipt_path, receipt)
    return receipt


class Budget:
    def __init__(self, total, reserve, clock=time.monotonic):
        require(total > reserve > 0, "invalid_owner_budget")
        self.clock, self.reserve = clock, reserve
        self.deadline = clock() + total

    def remaining(self, cleanup=False):
        left = self.deadline - self.clock() - (0 if cleanup else self.reserve)
        require(left > 0, "owner_deadline_exhausted")
        return left


def validate_ready(line, case, nonce, pid):
    require(isinstance(line, bytes) and len(line) <= 8192 and line.endswith(b"\n"),
            "invalid_ready_line")
    text = line.decode("utf-8").rstrip("\r\n")
    require(text.startswith(READY_PREFIX), "invalid_ready_prefix")
    ready = decode_json(text[len(READY_PREFIX):])
    require(type(pid) is int and 0 < pid <= 0xFFFFFFFF and
            re.fullmatch(r"[0-9a-f]{32}", nonce) is not None and
            type(ready) is dict and set(ready) == {"v", "case", "nonce", "pid"} and
            type(ready["v"]) is int and ready["v"] == 1 and
            type(ready["pid"]) is int and ready["pid"] == pid and
            ready["case"] == case and ready["nonce"] == nonce, "invalid_ready_context")
    return ready


def prepare_go(child, job, case, nonce, ready_line, state=None):
    state = state if state is not None else {}
    validate_ready(ready_line, case, nonce, child.pid)
    require(child.poll() is None, "parent_exited_before_assignment")
    job.assign(int(child._handle))
    state["assigned"] = True
    require(job.active() == 1, "unexpected_pre_go_activity")
    require(child.poll() is None, "parent_exited_before_go")
    # Treat a failed/partial write as possibly released: cleanup must use the Job.
    state["go_attempted"] = True
    child.stdin.write(GO_PREFIX.encode("ascii") + json_bytes({"v": 1, "case": case, "nonce": nonce}))
    child.stdin.flush()
    state["go_sent"] = True


def load_handoff(receipt_path, root):
    root = Path(root).resolve(strict=True)
    receipt = decode_json(Path(receipt_path).read_bytes())
    require(type(receipt) is dict and receipt.get("v") == 1 and receipt.get("root") == str(root),
            "wrong_handoff_root")
    require(receipt.get("ordinary_argv") == list(ORDINARY_ARGV) and
            receipt.get("inventory") == source_inventory(root / "server/tests/decoder_signal.rs") and
            receipt.get("source_pins") == source_snapshot(root), "handoff_source_changed")
    require(receipt.get("input_environment") == {name: os.environ.get(name) for name in INPUT_ENV},
            "handoff_environment_changed")
    require(re.fullmatch(r"[0-9a-f]{32}", str(receipt.get("handoff_nonce"))) is not None,
            "invalid_handoff_nonce")
    expected = {name: "ok" for name in ORDINARY} | {name: "ignored" for name in IGNORED}
    require(receipt.get("coverage") == {"outcomes": expected, "summary": [len(ORDINARY), 0, 2, 0, 1]},
            "handoff_coverage_mismatch")
    stream = Path(receipt.get("stream", ""))
    require(stream.is_file() and stream.resolve().parent == Path(receipt_path).resolve().parent and
            digest(stream) == receipt.get("stream_sha256"), "handoff_stream_changed")
    artifact = artifact_path(receipt.get("artifact"), receipt.get("target_dir", ""))
    configured = Path(os.environ.get("CARGO_TARGET_DIR", str(root / "target"))).resolve()
    require(Path(receipt["target_dir"]) == configured and
            digest(artifact) == receipt.get("artifact_sha256"), "handoff_artifact_changed")
    return receipt, artifact


def nonnegative(value):
    return type(value) in (int, float) and value >= 0


def matrix_ceiling(mode, long, workers):
    """CL-007-04 per-decode wall ceilings: (cold, timed round) seconds."""
    ceiling = 40.0 if long else 5.0 if mode == "ft8" else 3.0
    return ceiling + 2.0, ceiling * (2.0 if workers == 4 else 1.0)


def check_matrix_attempt(value):
    """Re-check one attempt's budgets, then classify its CPU-quantum qualification.

    Budgets are checked first and bind every attempt: an over-budget attempt is red
    whether or not its 50 ms CPU quantum qualified. Only an unmeasured quantum (a poll
    whose wall time exceeds the sufficient criterion) makes an attempt unqualified.
    """
    workers = value["concurrency"]
    cold_ceiling, round_ceiling = matrix_ceiling(value["mode"], value["long"], workers)
    prepared, unqualified = value.get("prepared"), value.get("unqualified_polls")
    require(type(prepared) is list and len(prepared) == workers and
            all(type(entry) is dict and entry.get("worker") == worker and
                all(nonnegative(entry.get(name)) for name in (
                    "cold_seconds", "cold_max_poll_wall_seconds", "warmup_max_poll_wall_seconds"))
                for worker, entry in enumerate(prepared)) and
            type(unqualified) is list and type(value.get("cpu_quantum_qualified")) is bool and
            all(nonnegative(reply.get("seconds")) and nonnegative(reply.get("max_poll_wall_seconds"))
                for round_value in value["rounds"] for reply in round_value["workers"]),
            "invalid_matrix_attempt")
    require(all(entry["cold_seconds"] <= cold_ceiling for entry in prepared) and
            all(reply["seconds"] <= round_ceiling
                for round_value in value["rounds"] for reply in round_value["workers"]) and
            all(type(metric) is dict and metric.get("absolute_private_peak_within64MiB") is True
                for metric in value["metrics"]), "matrix_budget_exceeded")
    over = sum(entry["cold_max_poll_wall_seconds"] > CPU_QUANTUM_WALL_SECONDS or
               entry["warmup_max_poll_wall_seconds"] > CPU_QUANTUM_WALL_SECONDS
               for entry in prepared)
    over += sum(reply["max_poll_wall_seconds"] > CPU_QUANTUM_WALL_SECONDS
                for round_value in value["rounds"] for reply in round_value["workers"])
    require(value["cpu_quantum_qualified"] is (over == 0) and len(unqualified) == over,
            "inconsistent_cpu_quantum_qualification")
    return over == 0


class CaseTranscript:
    def __init__(self, case):
        require(case in CASES, "unknown_resource_case")
        self.case = case
        self.coverage = Coverage((CASES[case],), (), len(ORDINARY) + len(IGNORED))
        self.configurations, self.configuration_rounds, self.rounds, self.attempts = [], [], {}, {}
        self.matrix_attempts = {}
        self.hosts = 0

    def accept(self, channel, line):
        text = line.decode("utf-8").rstrip("\r\n")
        if channel == "stdout":
            self.coverage.accept(text)
        if channel != "stderr":
            return
        if text.startswith("RESOURCE_HOST "):
            self.hosts += 1
        elif text.startswith("RESOURCE_CONFIGURATION "):
            value = decode_json(text.split(" ", 1)[1])
            workers = value.get("concurrency")
            require(type(workers) is int and workers in (1, 4) and
                    value.get("mode") in ("ft8", "ft4") and
                    type(value.get("scalar")) is bool and type(value.get("long")) is bool and
                    value.get("completed_rounds") == 10 and value.get("warmup_excluded") == 1 and
                    value.get("owned_children_reaped") is True and
                    len(value.get("summaries", [])) == workers and
                    len(value.get("metrics", [])) == workers and
                    len(value.get("rounds", [])) == 10, "invalid_matrix_configuration")
            for round_number, round_value in enumerate(value["rounds"]):
                require(type(round_value) is dict and type(round_value.get("round")) is int and
                        round_value["round"] == round_number and
                        type(round_value.get("workers")) is list and
                        len(round_value["workers"]) == workers and
                        all(type(reply) is dict and reply.get("state") == "completed" and
                            type(reply.get("round")) is int and reply["round"] == round_number
                            for reply in round_value["workers"]) and
                        type(round_value.get("parent_dispatch_offsets_ns")) is list and
                        len(round_value["parent_dispatch_offsets_ns"]) == workers and
                        all(type(offset) is int and offset >= 0
                            for offset in round_value["parent_dispatch_offsets_ns"]),
                        "invalid_matrix_configuration_round")
                qualification = round_value.get("concurrency_qualification")
                require(type(qualification) is dict and qualification.get("qualified") is True and
                        type(qualification.get("workers")) is int and
                        qualification["workers"] == workers, "invalid_matrix_round_qualification")
            identity = (value["mode"], value["scalar"], value["long"], workers)
            qualified = check_matrix_attempt(value)
            index, attempt = value.get("configuration"), value.get("attempt")
            require(type(index) is int and type(attempt) is int, "invalid_matrix_configuration")
            if attempt == 0:
                require(identity not in self.configurations and index == len(self.configurations),
                        "duplicate_matrix_configuration")
                self.configurations.append(identity)
                self.configuration_rounds.append([])
                self.matrix_attempts[identity] = []
            else:
                # A re-qualification attempt directly follows an unqualified attempt of
                # the same configuration, within the fixed attempt bound.
                previous = self.matrix_attempts.get(identity)
                require(previous is not None and self.configurations[-1] == identity and
                        index == len(self.configurations) - 1 and
                        attempt == len(previous) < QUALIFICATION_ATTEMPTS and
                        not previous[-1]["cpu_quantum_qualified"], "invalid_matrix_requalification")
            self.configuration_rounds[index].append(value["rounds"])
            self.matrix_attempts[identity].append({
                "attempt": attempt, "cpu_quantum_qualified": qualified,
                "unqualified_polls": value["unqualified_polls"],
            })
        elif text.startswith("RESOURCE_ROUND "):
            value = decode_json(text.split(" ", 1)[1])
            result = value.get("result", {})
            key = (value.get("configuration"), value.get("attempt"), value.get("worker"),
                   result.get("round"))
            require(all(type(number) is int for number in key) and 0 <= key[0] < 16 and
                    0 <= key[1] < QUALIFICATION_ATTEMPTS and 0 <= key[2] < 4 and
                    0 <= key[3] < 10 and result.get("state") == "completed" and
                    key not in self.rounds, "invalid_matrix_round")
            self.rounds[key] = result
        elif text.startswith("RESOURCE_LIVE_ATTEMPT_END "):
            value = decode_json(text.split(" ", 1)[1])
            context = value.get("context", {})
            key = (context.get("case"), context.get("state"), context.get("origin"))
            require(key not in self.attempts, "duplicate_busy_attempt")
            self.attempts[key] = value

    def finish(self):
        coverage = self.coverage.finish()
        if self.case == "matrix":
            expected = {(mode, scalar, long, workers) for mode in ("ft8", "ft4")
                        for scalar in (False, True) for long in (False, True) for workers in (1, 4)}
            require(set(self.configurations) == expected and self.hosts == 1,
                    "incomplete_matrix_configurations")
            rounds = {(index, attempt, worker, round_number)
                      for index, configuration in enumerate(self.configurations)
                      for attempt in range(len(self.configuration_rounds[index]))
                      for worker in range(configuration[3]) for round_number in range(10)}
            require(set(self.rounds) == rounds, "incomplete_matrix_rounds")
            for index, attempts in enumerate(self.configuration_rounds):
                for attempt, configuration in enumerate(attempts):
                    for round_number, round_value in enumerate(configuration):
                        for worker, reply in enumerate(round_value["workers"]):
                            require(self.rounds[(index, attempt, worker, round_number)] == reply,
                                    "inconsistent_matrix_worker_reply")
            inconclusive = []
            for identity in self.configurations:
                attempts = self.matrix_attempts[identity]
                # Stopping early with an unqualified last attempt is an incomplete run.
                require(attempts[-1]["cpu_quantum_qualified"] or
                        len(attempts) == QUALIFICATION_ATTEMPTS, "incomplete_matrix_requalification")
                if not attempts[-1]["cpu_quantum_qualified"]:
                    mode, scalar, long, workers = identity
                    inconclusive.append({"mode": mode, "scalar": scalar, "long": long,
                                         "concurrency": workers, "attempts": len(attempts),
                                         "unqualified_polls": attempts[-1]["unqualified_polls"]})
            return {"coverage": coverage, "configurations": 16, "workers": 40,
                    "coordinated_rounds": sum(10 * len(attempts)
                                              for attempts in self.configuration_rounds),
                    "measured_worker_completions": len(rounds),
                    "attempts": sum(len(attempts) for attempts in self.configuration_rounds),
                    "outcome": INCONCLUSIVE if inconclusive else QUALIFIED,
                    "inconclusive_configurations": inconclusive}
        expected = {
            ("silence", "fresh", 0), ("single", "fresh", 0),
            ("busy", "retained-first", 0), ("busy", "retained-next", 180000),
            ("busy", "fresh-same-next-window", 180000), ("busy", "cancel-after-real-Pending", 0),
        }
        require(set(self.attempts) == expected, "incomplete_busy_attempts")
        for key, value in self.attempts.items():
            cancelled = key[1] == "cancel-after-real-Pending"
            require(value.get("outcome") == ("Err(Cancelled)" if cancelled else "Ok(())") and
                    value.get("numerical_completion") is (not cancelled), "invalid_busy_outcome")
            if cancelled:
                elapsed = value.get("cancel_to_kernel_return_seconds")
                require(type(value.get("pending")) is int and value["pending"] > 0 and
                        type(elapsed) in (int, float) and 0 <= elapsed <= 0.250,
                        "invalid_busy_cancel_boundary")
        return {"coverage": coverage, "attempts": 6, "numerical_completions": 5,
                "real_pending_cancellations": 1}


def start_readers(child, events, stop, readers):
    def reader(channel, stream):
        try:
            while not stop.is_set():
                line = stream.readline(MAX_RUN_LINE + 1)
                if not line:
                    break
                require(len(line) <= MAX_RUN_LINE and line.endswith(b"\n"), "owner_output_line_limit")
                while not stop.is_set():
                    try:
                        events.put((channel, line, None), timeout=0.1)
                        break
                    except queue.Full:
                        continue
        except BaseException as error:
            while not stop.is_set():
                try:
                    events.put((channel, None, error), timeout=0.1)
                    break
                except queue.Full:
                    continue
        finally:
            stream.close()
            while not stop.is_set():
                try:
                    events.put((channel, None, None), timeout=0.1)
                    break
                except queue.Full:
                    continue

    streams = (("stdout", child.stdout), ("stderr", child.stderr))
    for channel, stream in streams:
        thread = threading.Thread(target=reader, args=(channel, stream), daemon=True)
        # Register before start: even an interrupted/partially successful start
        # cannot make the caller lose its only reader-cleanup reference.
        readers.append(thread)
        thread.start()


def wait_empty(job, budget):
    while job.active() != 0:
        time.sleep(min(0.02, budget.remaining(cleanup=True)))


def run_owned(argv, case, root, output, budget, pins, smoke=False, artifact_identity=None):
    """Internal fixed-case owner; CLI never accepts argv from a caller."""
    child, job, readers = None, None, []
    stop, events, state = threading.Event(), queue.Queue(maxsize=8), {}
    evidence = {"v": 1, "case": case, "complete": False, "cleanup_complete": False,
                "go_attempted": False, "source_pins": pins, "owner_pid": os.getpid()}
    nonce = secrets.token_hex(16)
    total, ended, ready, descendant = 0, set(), False, False
    error = None
    transcript = None if smoke else CaseTranscript(case)
    logs = {}
    try:
        for channel in ("stdout", "stderr"):
            logs[channel] = (output / f"{case}.{channel}.log").open("xb")
        if artifact_identity is not None:
            require(str(argv[0]) == artifact_identity[0] and
                    digest(argv[0]) == artifact_identity[1], "owner_artifact_changed")
        budget.remaining()
        job = OwnedJob()
        environment = dict(os.environ)
        environment["WSTX_RESOURCE_GUARDIAN_CASE"] = case
        environment["WSTX_RESOURCE_GUARDIAN_NONCE"] = nonce
        child = subprocess.Popen(argv, cwd=root, env=environment, stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, close_fds=True,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
        evidence["owned_pid"] = child.pid
        start_readers(child, events, stop, readers)
        while len(ended) < 2:
            remaining = budget.remaining()
            try:
                channel, line, reader_error = events.get(timeout=min(0.1, remaining))
            except queue.Empty:
                continue
            if reader_error is not None:
                raise reader_error
            if line is None:
                ended.add(channel)
                continue
            total += len(line)
            require(total <= MAX_RUN_STREAM, "owner_output_stream_limit")
            logs[channel].write(line)
            if channel == "stderr" and line.startswith(READY_PREFIX.encode("ascii")):
                require(not ready, "duplicate_ready")
                prepare_go(child, job, case, nonce, line, state)
                ready = True
                evidence["ready_assigned_active_one"] = True
            elif not ready:
                # Libtest's harmless banner is permitted; any pre-GO resource output is not.
                require(channel == "stdout" and
                        (line.startswith(b"\nrunning 1 test") or line.startswith(b"running 1 test") or
                         not line.strip()), "output_before_guardian_ready")
            elif smoke and channel == "stderr" and line.startswith(b"WSTX_GUARDIAN_DESCENDANT "):
                value = decode_json(line.split(b" ", 1)[1])
                require(not descendant and type(value) is dict and set(value) == {"pid"} and
                        type(value["pid"]) is int and value["pid"] > 0 and
                        job.active() == 2, "smoke_descendant_not_contained")
                descendant = True
                evidence["contained_parent_and_descendant"] = True
                job.terminate()
                evidence["intentional_smoke_job_termination"] = True
            elif transcript is not None:
                transcript.accept(channel, line)
        require(ready, "missing_ready")
        returncode = child.wait(timeout=budget.remaining())
        evidence["parent_exit"] = returncode
        require((smoke and descendant and returncode != 0) or (not smoke and returncode == 0),
                "resource_parent_failed")
        evidence["transcript"] = ({"fixed_smoke": True} if smoke else transcript.finish())
        require(source_snapshot(root) == pins, "owner_source_changed")
        if artifact_identity is not None:
            require(digest(argv[0]) == artifact_identity[1], "owner_artifact_changed")
        evidence["complete"] = True
    except BaseException as caught:
        error = caught
        evidence["error"] = {"operation": getattr(caught, "operation", type(caught).__name__),
                             "code": getattr(caught, "code", None)}
    finally:
        evidence["go_attempted"] = state.get("go_attempted", False)
        cleanup_errors = []
        if job is not None:
            try:
                if error is not None:
                    job.terminate()
                wait_empty(job, budget)
                evidence["job_active_zero"] = True
            except BaseException as caught:
                cleanup_errors.append(getattr(caught, "operation", type(caught).__name__))
        if child is not None:
            try:
                if not state.get("go_attempted") and child.poll() is None:
                    # Before GO this exact retained parent is a childless waiting leaf.
                    child.kill()
                child.wait(timeout=budget.remaining(cleanup=True))
                evidence["parent_reaped"] = True
            except BaseException as caught:
                cleanup_errors.append(getattr(caught, "operation", type(caught).__name__))
            if child.stdin is not None:
                try:
                    child.stdin.close()
                except OSError:
                    cleanup_errors.append("close_parent_stdin")
        stop.set()
        joined_readers = 0
        for thread in readers:
            try:
                thread.join(timeout=budget.remaining(cleanup=True))
                require(not thread.is_alive(), "reader_join_incomplete")
                joined_readers += 1
            except BaseException as caught:
                cleanup_errors.append(getattr(caught, "operation", type(caught).__name__))
        evidence["readers_registered"] = len(readers)
        evidence["readers_joined_count"] = joined_readers
        evidence["readers_joined"] = joined_readers == len(readers)
        evidence["parent_output_pipes_closed"] = False
        if child is not None and not any(thread.is_alive() for thread in readers):
            try:
                # Also close a pipe whose reader never started. This happens only
                # after retained-child cleanup, not while a reader can hold its I/O lock.
                child.stdout.close()
                child.stderr.close()
                evidence["parent_output_pipes_closed"] = True
            except OSError:
                cleanup_errors.append("close_parent_output_pipes")
        if job is not None:
            try:
                job.close()
                evidence["owned_job_closed"] = True
            except BaseException as caught:
                cleanup_errors.append(getattr(caught, "operation", type(caught).__name__))
        for log in logs.values():
            log.close()
        evidence["cleanup_errors"] = cleanup_errors
        evidence["cleanup_complete"] = bool(job is not None and child is not None and
                                             evidence.get("job_active_zero") and
                                             evidence.get("parent_reaped") and
                                             evidence["readers_joined"] and
                                             evidence["parent_output_pipes_closed"] and
                                             evidence.get("owned_job_closed") and not cleanup_errors)
        evidence["complete"] = evidence["complete"] and evidence["cleanup_complete"]
        write_new(output / f"{case}.receipt.json", evidence)
    require(evidence["complete"], "resource_owner_incomplete")
    return evidence


def run_case(receipt_path, case, root):
    require(case in CASES, "unknown_resource_case")
    budget = Budget(10800 if case == "matrix" else 600, 30)
    root = Path(root).resolve(strict=True)
    receipt, artifact = load_handoff(receipt_path, root)
    budget.remaining()
    output = Path(receipt_path).resolve().parent
    write_new(output / "launch.claim", {"case": case, "nonce": receipt["handoff_nonce"]})
    argv = [str(artifact), "--exact", CASES[case]]
    if case == "busy":
        argv.append("--ignored")
    argv.extend(["--nocapture", "--test-threads=1"])
    return run_owned(argv, case, root, output, budget, receipt["source_pins"],
                     artifact_identity=(str(artifact), receipt["artifact_sha256"]))


def report_outcome(evidence, ordinary_gate, stream=None):
    """Exit status of a complete owned run (#36).

    A qualified run is 0. An inconclusive matrix (some configuration's CPU quantum
    still unmeasured after the bounded re-qualification) is reported visibly; the
    ordinary gate reports it as not run (exit 77), while the default strict mode, used for
    CL-007-04 evidence in the exclusive window, refuses it.
    """
    stream = stream if stream is not None else sys.stderr
    transcript = evidence["transcript"]
    outcome = transcript.get("outcome", QUALIFIED)
    require(outcome in (QUALIFIED, INCONCLUSIVE), "invalid_matrix_outcome")
    if outcome == QUALIFIED:
        if evidence["case"] == "matrix":
            print(f"decoder resource matrix: QUALIFIED ({transcript['attempts']} attempts for "
                  f"{transcript['configurations']} configurations; budgets met)", file=stream)
        return 0
    configurations = ", ".join(
        f"{entry['mode']} scalar={entry['scalar']} long={entry['long']} "
        f"workers={entry['concurrency']}" for entry in transcript["inconclusive_configurations"])
    if ordinary_gate:
        print("decoder resource matrix: INCONCLUSIVE, NOT RUN (50 ms CPU quantum not "
              f"established after {QUALIFICATION_ATTEMPTS} attempts: {configurations}); all "
              "measured budgets met; no CL-007-04 runtime claim from this run", file=stream)
        return NOT_RUN
    print("decoder resource matrix: INCONCLUSIVE, REFUSED (strict: 50 ms CPU quantum not "
          f"established after {QUALIFICATION_ATTEMPTS} attempts: {configurations})", file=stream)
    return INCONCLUSIVE_REFUSED


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="operation", required=True)
    resolver = commands.add_parser("resolve")
    resolver.add_argument("--stream-log", type=Path, required=True)
    resolver.add_argument("--receipt", type=Path, required=True)
    runner = commands.add_parser("run")
    runner.add_argument("--case", choices=tuple(CASES), required=True)
    runner.add_argument("--artifact-receipt", type=Path, required=True)
    runner.add_argument("--ordinary-gate", action="store_true",
                        help="ordinary push gate only: an inconclusive matrix is reported and "
                             "exits 77 (not run); the default strict mode refuses it")
    smoke = commands.add_parser("smoke", help="separately authorized fixed parent/descendant fixture")
    smoke.add_argument("--out", type=Path, required=True)
    arguments = parser.parse_args(argv)
    root = Path(__file__).resolve().parent.parent
    try:
        if arguments.operation == "resolve":
            require(arguments.stream_log.parent.resolve() == arguments.receipt.parent.resolve() and
                    not arguments.receipt.exists(), "invalid_fresh_handoff_paths")
            target_dir = os.environ.get("CARGO_TARGET_DIR", str(root / "target"))
            resolve_stream(sys.stdin.buffer, arguments.stream_log, arguments.receipt, root, target_dir)
        elif arguments.operation == "run":
            require(not arguments.ordinary_gate or arguments.case == "matrix",
                    "ordinary_gate_matrix_only")
            evidence = run_case(arguments.artifact_receipt, arguments.case, root)
            return report_outcome(evidence, arguments.ordinary_gate)
        else:
            budget = Budget(30, 10)
            arguments.out.mkdir(parents=True, exist_ok=False)
            pins = source_snapshot(root)
            command = [sys.executable, str(root / "tools/test_windows_resource_job.py"), "--smoke-child"]
            run_owned(command, "smoke", root, arguments.out.resolve(), budget, pins, smoke=True)
        return 0
    except Exception as error:
        print(json.dumps({"v": 1, "error": getattr(error, "operation", type(error).__name__),
                          "code": getattr(error, "code", None)}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

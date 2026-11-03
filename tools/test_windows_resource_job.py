"""API-free guardian ABI, ownership, artifact and protocol fault controls.

Default unittest discovery uses fakes only: no DLL, Popen or Rust execution.
"""

import ctypes
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

with patch.object(ctypes, "WinDLL", side_effect=AssertionError("import must be API-free"),
                  create=True), patch.object(subprocess, "Popen",
                                              side_effect=AssertionError("import must not launch")):
    import windows_resource_job as guardian


class ApiFreeCase(unittest.TestCase):
    def setUp(self):
        dll = patch.object(guardian.ctypes, "WinDLL",
                           side_effect=AssertionError("unit tests must be API-free"), create=True)
        process = patch.object(guardian.subprocess, "Popen",
                               side_effect=AssertionError("unit tests must not launch"))
        dll.start()
        process.start()
        self.addCleanup(dll.stop)
        self.addCleanup(process.stop)


class FakeFunction:
    def __init__(self):
        self.argtypes = self.restype = None

    def __call__(self, *_args):
        raise AssertionError("native function execution is forbidden in unit tests")


class FakeDll:
    def __init__(self):
        for name in ("CreateJobObjectW", "SetInformationJobObject", "AssignProcessToJobObject",
                     "QueryInformationJobObject", "TerminateJobObject", "CloseHandle"):
            setattr(self, name, FakeFunction())


class FakeApi:
    def __init__(self, fault=None, active=1):
        self.fault, self.count = fault, active
        self.calls, self.closed = [], []

    def create(self, security, name):
        self.calls.append(("create", security, name))
        if self.fault == "create":
            return None
        return 123

    def set(self, handle, information, limits, size):
        self.calls.append(("set", handle, information, size))
        expected = guardian.ExtendedLimit()
        expected.BasicLimitInformation.LimitFlags = guardian.KILL_ON_JOB_CLOSE
        assert bytes(limits._obj) == bytes(expected)
        assert information == 9 and size == 144
        return 0 if self.fault == "set" else 1

    def assign(self, job, process):
        self.calls.append(("assign", job, process))
        return 0 if self.fault == "assign" else 1

    def query(self, handle, information, accounting, size, returned):
        self.calls.append(("query", handle, information, size))
        assert handle == 123 and information == 1 and size == 48
        if self.fault == "query":
            return 0
        accounting._obj.ActiveProcesses = self.count
        returned._obj.value = 47 if self.fault == "short_query" else 48
        return 1

    def terminate(self, handle, exit_code):
        self.calls.append(("terminate", handle, exit_code))
        return 0 if self.fault == "terminate" else 1

    def close(self, handle):
        self.calls.append(("close", handle))
        self.closed.append(handle)
        return 0 if self.fault == "close" else 1

    @staticmethod
    def last_error():
        return 5


class AbiAndJobTests(ApiFreeCase):
    def test_exact_complete_layout_and_offsets(self):
        guardian.checked_layout()
        for structure, size, offsets in (
            (guardian.BasicLimit, 64, [0, 8, 16, 24, 32, 40, 48, 56, 60]),
            (guardian.IoCounters, 48, [0, 8, 16, 24, 32, 40]),
            (guardian.ExtendedLimit, 144, [0, 64, 112, 120, 128, 136]),
            (guardian.BasicAccounting, 48, [0, 8, 16, 24, 32, 36, 40, 44]),
        ):
            self.assertEqual(ctypes.sizeof(structure), size)
            self.assertEqual(ctypes.alignment(structure), 8)
            self.assertEqual([getattr(structure, name).offset
                              for name, _kind in structure._fields_], offsets)

    def test_unsupported_layout_refuses_before_native_binding(self):
        original = ctypes.sizeof
        with patch.object(guardian.ctypes, "sizeof", side_effect=lambda value:
                          4 if value is guardian.HANDLE else original(value)), \
                patch.object(guardian, "NativeApi", side_effect=AssertionError("DLL forbidden")):
            with self.assertRaises(guardian.JobError):
                guardian.OwnedJob()

    def test_exact_native_prototypes_are_bound_to_fake_functions_only(self):
        dll = FakeDll()
        with patch.object(guardian.sys, "platform", "win32"), \
                patch.object(guardian.ctypes, "WinDLL", return_value=dll, create=True) as load:
            api = guardian.NativeApi()
        load.assert_called_once_with("kernel32", use_last_error=True)
        for attribute, arguments, result in (
            ("create", [ctypes.c_void_p, ctypes.c_wchar_p], guardian.HANDLE),
            ("set", [guardian.HANDLE, ctypes.c_int, ctypes.c_void_p, guardian.DWORD], guardian.BOOL),
            ("assign", [guardian.HANDLE, guardian.HANDLE], guardian.BOOL),
            ("query", [guardian.HANDLE, ctypes.c_int, ctypes.c_void_p, guardian.DWORD,
                       ctypes.POINTER(guardian.DWORD)], guardian.BOOL),
            ("terminate", [guardian.HANDLE, ctypes.c_uint], guardian.BOOL),
            ("close", [guardian.HANDLE], guardian.BOOL),
        ):
            self.assertEqual(getattr(api, attribute).argtypes, arguments)
            self.assertIs(getattr(api, attribute).restype, result)

    def test_create_is_unnamed_noninheritable_and_only_kill_on_close_is_set(self):
        api = FakeApi()
        job = guardian.OwnedJob(api)
        self.assertEqual(api.calls[:2], [("create", None, None), ("set", 123, 9, 144)])
        job.assign(456)
        self.assertEqual(job.active(), 1)
        job.terminate()
        job.close()
        job.close()
        self.assertEqual(api.closed, [123])
        self.assertNotIn(456, api.closed)
        self.assertEqual(api.calls[-2:], [("terminate", 123, 1), ("close", 123)])

    def test_failed_create_never_closes_a_borrowed_or_null_handle(self):
        api = FakeApi("create")
        with self.assertRaises(guardian.JobError):
            guardian.OwnedJob(api)
        self.assertEqual(api.closed, [])

    def test_failed_set_closes_the_new_job_only(self):
        api = FakeApi("set")
        with self.assertRaises(guardian.JobError) as error:
            guardian.OwnedJob(api)
        self.assertEqual(error.exception.operation, "SetInformationJobObject")
        self.assertEqual(api.closed, [123])

    def test_native_failures_and_short_accounting_are_not_success(self):
        for fault, operation in (("assign", "AssignProcessToJobObject"),
                                 ("query", "QueryInformationJobObject"),
                                 ("short_query", "incomplete_job_accounting"),
                                 ("terminate", "TerminateJobObject")):
            with self.subTest(fault=fault):
                api = FakeApi(fault)
                job = guardian.OwnedJob(api)
                call = {"assign": lambda: job.assign(456), "query": job.active,
                        "short_query": job.active, "terminate": job.terminate}[fault]
                with self.assertRaises(guardian.JobError) as error:
                    call()
                self.assertEqual(error.exception.operation, operation)
                job.close()

    def test_zero_activity_is_valid_accounting_but_not_a_substitute_for_active_one(self):
        job = guardian.OwnedJob(FakeApi(active=0))
        self.assertEqual(job.active(), 0)
        job.close()

    def test_close_failure_retains_ownership_and_can_never_be_called_success(self):
        api = FakeApi("close")
        job = guardian.OwnedJob(api)
        with self.assertRaises(guardian.JobError) as error:
            job.close()
        self.assertEqual(error.exception.operation, "CloseJobHandle")
        self.assertEqual(job.handle, 123)

    def test_null_or_borrowed_pseudohandles_refuse_before_api_use(self):
        for invalid in (None, 0, -1, True, (1 << 64) - 1, 1 << 64):
            with self.subTest(handle=invalid):
                with self.assertRaises(guardian.JobError):
                    guardian.positive_handle(invalid)
        api = FakeApi()
        job = guardian.OwnedJob(api)
        job.close()
        before = list(api.calls)
        for call in (job.active, job.terminate, lambda: job.assign(456)):
            with self.assertRaises(guardian.JobError):
                call()
        self.assertEqual(api.calls, before)


def ready_line(case="matrix", nonce="a" * 32, pid=456, **extra):
    value = {"v": 1, "case": case, "nonce": nonce, "pid": pid, **extra}
    return guardian.READY_PREFIX.encode() + guardian.json_bytes(value)


class FakePipe(io.BytesIO):
    def __init__(self):
        super().__init__()
        self.flushes = 0

    def flush(self):
        self.flushes += 1


class FakeChild:
    def __init__(self, polls=(None, None), handle=789):
        self.pid, self._handle = 456, handle
        self.stdin = FakePipe()
        self.polls, self.index = list(polls), 0

    def poll(self):
        value = self.polls[min(self.index, len(self.polls) - 1)]
        self.index += 1
        return value


class FakeJob:
    def __init__(self, active=1, fault=None):
        self.count, self.fault, self.calls = active, fault, []

    def assign(self, handle):
        self.calls.append(("assign", handle))
        if self.fault == "assign":
            raise guardian.JobError("AssignProcessToJobObject", 5)

    def active(self):
        self.calls.append(("active",))
        if self.fault == "query":
            raise guardian.JobError("QueryInformationJobObject", 5)
        return self.count


class ReadyAndDeadlineTests(ApiFreeCase):
    def test_ready_exact_identity_and_one_go_after_assignment_and_active_one(self):
        child, job = FakeChild(), FakeJob()
        guardian.validate_ready(ready_line(), "matrix", "a" * 32, 456)
        guardian.prepare_go(child, job, "matrix", "a" * 32, ready_line())
        self.assertEqual(job.calls, [("assign", 789), ("active",)])
        self.assertEqual(child.stdin.flushes, 1)
        self.assertEqual(child.stdin.getvalue(), guardian.GO_PREFIX.encode() +
                         guardian.json_bytes({"v": 1, "case": "matrix", "nonce": "a" * 32}))

    def test_wrong_ready_has_no_go_or_assignment(self):
        cases = [b"", b"{}\n", guardian.READY_PREFIX.encode() + b"not JSON\n",
                 ready_line(case="busy"), ready_line(nonce="b" * 32), ready_line(pid=123),
                 ready_line(unexpected=True), ready_line(pid=True),
                 guardian.READY_PREFIX.encode() + b'{"v":1,"v":1,"case":"matrix",'
                 b'"nonce":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","pid":456}\n']
        for line in cases:
            with self.subTest(line=line):
                child, job = FakeChild(), FakeJob()
                with self.assertRaises((guardian.JobError, ValueError, UnicodeError)):
                    guardian.prepare_go(child, job, "matrix", "a" * 32, line)
                self.assertEqual(job.calls, [])
                self.assertEqual(child.stdin.getvalue(), b"")
                self.assertEqual(child.stdin.flushes, 0)

    def test_child_exit_assignment_refusal_or_wrong_activity_never_sends_go(self):
        for polls, count, fault in (((0,), 1, None), ((None, 0), 1, None),
                                    ((None, None), 1, "assign"),
                                    ((None, None), 1, "query"),
                                    ((None, None), 0, None), ((None, None), 2, None)):
            with self.subTest(polls=polls, active=count, fault=fault):
                child, job = FakeChild(polls), FakeJob(count, fault)
                with self.assertRaises(guardian.JobError):
                    guardian.prepare_go(child, job, "matrix", "a" * 32, ready_line())
                self.assertEqual(child.stdin.getvalue(), b"")
                self.assertEqual(child.stdin.flushes, 0)

    def test_deadline_is_global_and_cleanup_reserve_is_inside_total(self):
        now = [100.]
        budget = guardian.Budget(100, 10, clock=lambda: now[0])
        self.assertAlmostEqual(budget.remaining(), 90)
        now[0] = 105.
        self.assertAlmostEqual(budget.remaining(), 85)
        self.assertAlmostEqual(budget.remaining(cleanup=True), 95)
        now[0] = 190.
        with self.assertRaises(guardian.JobError):
            budget.remaining()
        self.assertAlmostEqual(budget.remaining(cleanup=True), 10)
        now[0] = 200.
        with self.assertRaises(guardian.JobError):
            budget.remaining(cleanup=True)


class ArtifactTests(ApiFreeCase):
    def setUp(self):
        super().setUp()
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.target = self.root / "target"
        self.executable = self.target / "x86_64-pc-windows-msvc/release/deps/decoder_signal-ab12.exe"
        self.executable.parent.mkdir(parents=True)
        self.executable.write_bytes(b"MZ fixed test artifact; never executable")
        for relative in ("Cargo.lock", "rust-toolchain.toml", ".harness/suites.yaml",
                         "tools/windows_resource_job.py", "tools/test_windows_resource_job.py",
                         "tools/windows_process_metrics.py", "tools/test_windows_process_metrics.py",
                         "server/src/decoder/payload.rs", "fixtures/decoder/independent.json"):
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixed input\n", encoding="utf-8")
        (self.root / "Cargo.toml").write_text('[workspace.package]\nversion = "0.1.0"\n',
                                             encoding="utf-8")
        (self.root / "server/Cargo.toml").write_text('[package]\nname = "wstx-rust"\n',
                                                    encoding="utf-8")
        self.source = self.root / "server/tests/decoder_signal.rs"
        self.source.parent.mkdir(parents=True)
        declarations = ['#![forbid(unsafe_code)]', '#![cfg(not(debug_assertions))]']
        for name in (*guardian.ORDINARY, guardian.MATRIX, *guardian.IGNORED):
            declarations.append("#[test]")
            if name in guardian.IGNORED:
                declarations.append('#[ignore = "fixed source inventory"]')
            declarations.append(f"fn {name}() {{}}")
        self.source.write_text("\n".join(declarations) + "\n", encoding="utf-8")
        self.counter = 0
        environment = patch.dict(guardian.os.environ, {"CARGO_TARGET_DIR": str(self.target)})
        environment.start()
        self.addCleanup(environment.stop)

    def artifact(self):
        return {"reason": "compiler-artifact", "fresh": True,
                "package_id": f"path+{(self.root / 'server').as_uri()}#wstx-rust@0.1.0",
                "manifest_path": str(self.root / "server/Cargo.toml"),
                "target": {"name": "decoder_signal", "kind": ["test"],
                           "src_path": str(self.source)},
                "profile": {"test": True, "opt_level": "3", "debug_assertions": False},
                "executable": str(self.executable)}

    @staticmethod
    def coverage_lines():
        return [*(f"test {name} ... ok\n".encode() for name in guardian.ORDINARY),
                *(f"test {name} ... ignored, fixed reason\n".encode() for name in guardian.IGNORED),
                b"test result: ok. 17 passed; 0 failed; 2 ignored; 0 measured; 1 filtered out; "
                b"finished in 1.00s\n"]

    def producer(self, artifact=None, build=True, coverage=None):
        return b"".join([
            guardian.json_bytes({"reason": "compiler-message", "message": {"level": "note"}}),
            guardian.json_bytes(self.artifact() if artifact is None else artifact),
            guardian.json_bytes({"reason": "build-finished", "success": build}),
            b"\nrunning 16 tests\n", *(self.coverage_lines() if coverage is None else coverage),
        ])

    def resolve(self, stream, receipt=None):
        self.counter += 1
        folder = self.root / f"run-{self.counter}"
        folder.mkdir()
        receipt = folder / "artifact.json" if receipt is None else receipt
        result = guardian.resolve_stream(stream, folder / "ordinary.log", receipt,
                                         self.root, self.target)
        return result, folder, receipt

    def test_complete_mixed_stream_accepts_cached_artifact_and_exact_named_coverage(self):
        raw = self.producer()
        receipt, folder, path = self.resolve(io.BytesIO(raw))
        self.assertEqual((folder / "ordinary.log").read_bytes(), raw)
        self.assertEqual(json.loads(path.read_bytes()), receipt)
        self.assertEqual(receipt["artifact_sha256"], guardian.digest(self.executable))
        self.assertEqual(receipt["ordinary_argv"], list(guardian.ORDINARY_ARGV))
        self.assertEqual(receipt["coverage"]["summary"], [17, 0, 2, 0, 1])
        self.assertEqual(set(receipt["coverage"]["outcomes"]),
                         set(guardian.ORDINARY) | set(guardian.IGNORED))
        self.assertEqual(len(receipt["inventory"]["names"]), 20)
        self.assertEqual(set(receipt["inventory"]["ignored"]), set(guardian.IGNORED))
        self.assertIn("tools/windows_process_metrics.py", receipt["source_pins"])
        self.assertIn("tools/test_windows_process_metrics.py", receipt["source_pins"])

    def test_wrong_target_package_source_profile_and_artifact_path_are_rejected(self):
        mutations = (
            lambda value: value.update(package_id="path+file:///wrong#wstx-rust@0.1.0"),
            lambda value: value.update(manifest_path=str(self.root / "Cargo.toml")),
            lambda value: value["target"].update(name="different_test"),
            lambda value: value["target"].update(kind=["bin"]),
            lambda value: value["target"].update(src_path=str(self.root / "server/src/decoder/payload.rs")),
            lambda value: value["profile"].update(test=False),
            lambda value: value["profile"].update(opt_level="0"),
            lambda value: value["profile"].update(debug_assertions=True),
            lambda value: value.update(executable=str(self.root / "decoder_signal-ab12.exe")),
        )
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                artifact = self.artifact()
                mutate(artifact)
                with self.assertRaises(guardian.JobError):
                    self.resolve(io.BytesIO(self.producer(artifact)))

    def test_build_failure_and_duplicate_or_missing_artifact_never_publish_receipt(self):
        artifact_line = guardian.json_bytes(self.artifact())
        finished = guardian.json_bytes({"reason": "build-finished", "success": True})
        for raw in (self.producer(build=False), self.producer() + finished,
                    artifact_line + self.producer(),
                    finished + b"".join(self.coverage_lines()),
                    artifact_line + b"".join(self.coverage_lines())):
            with self.subTest(stream=raw[:80]):
                with self.assertRaises(guardian.JobError):
                    self.resolve(io.BytesIO(raw))
        self.assertEqual(list(self.root.glob("run-*/artifact.json")), [])

    def test_failed_duplicate_unknown_or_incomplete_named_outcomes_refuse(self):
        valid = self.coverage_lines()
        variants = [valid[:-1], valid[1:], [valid[0], *valid],
                    [valid[0].replace(b"ok", b"FAILED"), *valid[1:]],
                    [b"test unreviewed ... ok\n", *valid],
                    [*valid[:-1], valid[-1].replace(b"17 passed", b"16 passed")],
                    [*valid[:-1], valid[-1].replace(b"1 filtered", b"2 filtered")]]
        for coverage in variants:
            with self.subTest(coverage=coverage[:1]):
                with self.assertRaises(guardian.JobError):
                    self.resolve(io.BytesIO(self.producer(coverage=coverage)))

    def test_partial_utf8_or_truncated_or_oversized_stream_is_not_a_successful_eof(self):
        for raw in (self.producer()[:-1], b"\xff\n", b"x" * (guardian.MAX_LINE + 1) + b"\n"):
            with self.subTest(prefix=raw[:20]):
                with self.assertRaises((guardian.JobError, UnicodeError)):
                    self.resolve(io.BytesIO(raw))
        with patch.object(guardian, "MAX_STREAM", 16):
            with self.assertRaises(guardian.JobError):
                self.resolve(io.BytesIO(self.producer()))

    def test_source_inventory_refuses_extra_missing_duplicate_or_unignored_worker(self):
        original = self.source.read_text(encoding="utf-8")
        for text in (original + "#[test]\nfn added() {}\n",
                     original.replace("fn quality_corpus()", "fn independent_waveforms_decode()"),
                     original.replace('#[ignore = "fixed source inventory"]\n', "", 1),
                     original.replace('#![cfg(not(debug_assertions))]', "")):
            with self.subTest(source=text[-50:]):
                self.source.write_text(text, encoding="utf-8")
                with self.assertRaises(guardian.JobError):
                    guardian.source_inventory(self.source)
        self.source.write_text(original, encoding="utf-8")

    def test_executable_and_source_changes_between_artifact_and_eof_refuse(self):
        owner = self

        class ChangedAtEof(io.BytesIO):
            def __init__(self, data, mutate):
                super().__init__(data)
                self.mutate = mutate

            def readline(self, size=-1):
                line = super().readline(size)
                if not line:
                    self.mutate()
                return line

        for path in (self.executable, self.root / "server/src/decoder/payload.rs"):
            with self.subTest(path=path):
                original = path.read_bytes()
                stream = ChangedAtEof(owner.producer(), lambda: path.write_bytes(b"changed input"))
                with self.assertRaises(guardian.JobError) as error:
                    self.resolve(stream)
                self.assertEqual(error.exception.operation, "producer_inputs_changed")
                path.write_bytes(original)

    def test_existing_receipt_or_stream_is_never_overwritten(self):
        _receipt, folder, path = self.resolve(io.BytesIO(self.producer()))
        original = path.read_bytes()
        with self.assertRaises(FileExistsError):
            self.resolve(io.BytesIO(self.producer()), receipt=path)
        self.assertEqual(path.read_bytes(), original)
        log = folder / "ordinary.log"
        raw = log.read_bytes()
        with self.assertRaises(FileExistsError):
            guardian.resolve_stream(io.BytesIO(self.producer()), log, folder / "second.json",
                                    self.root, self.target)
        self.assertEqual(log.read_bytes(), raw)

    def test_noncanonical_or_nonrelease_artifact_does_not_become_a_launch_target(self):
        for path in (Path("relative.exe"), self.root / "missing.exe", self.source):
            with self.subTest(path=path):
                with self.assertRaises(guardian.JobError):
                    guardian.artifact_path(str(path), self.target)

    def test_handoff_rechecks_identity_input_stream_and_coverage_before_any_launch(self):
        receipt, folder, path = self.resolve(io.BytesIO(self.producer()))
        accepted, artifact = guardian.load_handoff(path, self.root)
        self.assertEqual(accepted, receipt)
        self.assertEqual(artifact, self.executable)
        mutations = (
            lambda value: value.update(root=str(self.root.parent)),
            lambda value: value.update(ordinary_argv=["cargo", "test"]),
            lambda value: value.update(inventory={"names": [], "ignored": []}),
            lambda value: value.update(source_pins={}),
            lambda value: value.update(input_environment={}),
            lambda value: value.update(coverage={"outcomes": {}, "summary": [17, 0, 2, 0, 1]}),
            lambda value: value.update(handoff_nonce="not a nonce"),
            lambda value: value.update(stream_sha256="0" * 64),
            lambda value: value.update(artifact_sha256="0" * 64),
        )
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                changed = json.loads(json.dumps(receipt))
                mutate(changed)
                path.write_bytes(guardian.json_bytes(changed))
                with self.assertRaises(guardian.JobError):
                    guardian.load_handoff(path, self.root)
        path.write_bytes(guardian.json_bytes(receipt))
        (folder / "ordinary.log").write_bytes(b"replaced stream\n")
        with self.assertRaises(guardian.JobError):
            guardian.load_handoff(path, self.root)

    def test_exclusive_launch_claim_refuses_replay_before_owned_job(self):
        _receipt, folder, path = self.resolve(io.BytesIO(self.producer()))
        (folder / "launch.claim").write_bytes(b"already consumed\n")
        with patch.object(guardian, "OwnedJob", side_effect=AssertionError("must not create job")):
            with self.assertRaises(FileExistsError):
                guardian.run_case(path, "matrix", self.root)


class CaseTranscriptTests(ApiFreeCase):
    """Synthetic protocol transcripts, not decoded-signal or resource acceptance."""

    @staticmethod
    def attempt_events(index, mode, scalar, long, workers, attempt=0, slow=None):
        """One attempt of one configuration; slow=(worker, round, poll, seconds) or None."""
        events, rounds, unqualified = [], [], []
        for number in range(10):
            replies = []
            for worker in range(workers):
                start = 1_000_000_000 + number * 100_000_000 + worker * 1000
                poll, seconds = 0.001, 0.020
                if slow is not None and slow[:2] == (worker, number):
                    poll, seconds = slow[2], slow[3]
                result = {
                    "state": "completed", "round": number, "seconds": seconds,
                    "started_unix_ns": start, "ended_unix_ns": start + 20_000_000,
                    "monotonic_duration_ns": 20_000_000,
                    "records": (8 if mode == "ft8" else 16) if long else 1,
                    "max_poll_wall_seconds": poll,
                }
                if poll > 0.050:
                    unqualified.append({"worker": worker, "phase": "round", "round": number,
                                        "max_poll_wall_seconds": poll})
                replies.append(result)
                events.append(("RESOURCE_ROUND", {
                    "configuration": index, "attempt": attempt, "worker": worker,
                    "pid": 10000 + index * 4 + worker, "result": result,
                }))
            rounds.append({
                "round": number,
                "parent_dispatch_offsets_ns": [worker * 1000 for worker in range(workers)],
                "workers": replies,
                "concurrency_qualification": {
                    "qualified": True, "workers": workers,
                    "dispatch_skew_ns": (workers - 1) * 1000,
                    "actual_start_spread_ns": (workers - 1) * 1000,
                    "wall_monotonic_discrepancy_ns": [0] * workers,
                    "boundary_margin_ns": 5_000_000,
                    "qualified_common_overlap_ns":
                        10_000_000 - (workers - 1) * 1000 if workers == 4 else None,
                    "measurement_qualification_only": True,
                    "padding_or_serialized_work_used": False,
                },
            })
        events.append(("RESOURCE_CONFIGURATION", {
            "mode": mode, "scalar": scalar, "long": long, "concurrency": workers,
            "configuration": index, "attempt": attempt,
            "cpu_quantum_qualified": not unqualified, "unqualified_polls": unqualified,
            "prepared": [{"worker": worker, "cold_seconds": 0.030,
                          "cold_max_poll_wall_seconds": 0.002,
                          "warmup_max_poll_wall_seconds": 0.002} for worker in range(workers)],
            "warmup_excluded": 1, "completed_rounds": 10,
            "summaries": [{"min": 0.020, "median": 0.020, "p95": 0.020,
                           "max": 0.020} for _ in range(workers)],
            "metrics": [{"absolute_private_peak_within64MiB": True,
                         "whole_workspace_proved": False} for _ in range(workers)],
            "rounds": rounds, "owned_children_reaped": True,
            "full_station_proof": False,
        }))
        return events

    @classmethod
    def matrix_events(cls, extra=None):
        """All 16 configurations; extra maps an index to its leading unqualified-or-not
        attempts as (attempt slow tuples), followed by one final attempt of its own."""
        extra = extra or {}
        events = [("RESOURCE_HOST", {"fixture": "API-free source-shaped transcript"})]
        index = 0
        for mode in ("ft8", "ft4"):
            for scalar in (False, True):
                for long in (False, True):
                    for workers in (1, 4):
                        attempts = extra.get(index, [None])
                        for attempt, slow in enumerate(attempts):
                            events += cls.attempt_events(index, mode, scalar, long, workers,
                                                         attempt, slow)
                        index += 1
        return events

    @staticmethod
    def busy_events():
        events = []
        for case, state, origin in (
            ("silence", "fresh", 0), ("single", "fresh", 0),
            ("busy", "retained-first", 0), ("busy", "retained-next", 180000),
            ("busy", "fresh-same-next-window", 180000),
            ("busy", "cancel-after-real-Pending", 0),
        ):
            cancelled = state == "cancel-after-real-Pending"
            events.append(("RESOURCE_LIVE_ATTEMPT_END", {
                "context": {"case": case, "state": state, "origin": origin,
                            "mode": "ft8", "backend": "planned"},
                "outcome": "Err(Cancelled)" if cancelled else "Ok(())",
                "numerical_completion": not cancelled, "wall_seconds": 0.020,
                "polls": 3, "pending": 2, "maximum_poll_wall_seconds": 0.010,
                "wall_sufficient_for50ms_cpu": True, "cpu_time_measured": False,
                "cancel_to_kernel_return_seconds": 0.010 if cancelled else None,
                "history_records_after_future_drop": 0, "records": [],
                "manager_ack_release_terminal_or_status_proved": False,
                "new_busy_total_deadline": False,
            }))
        return events

    @staticmethod
    def parse(case, events):
        transcript = guardian.CaseTranscript(case)
        transcript.accept("stdout", f"test {guardian.CASES[case]} ... ok\n".encode())
        transcript.accept("stdout", b"test result: ok. 1 passed; 0 failed; 0 ignored; "
                                    b"0 measured; 19 filtered out; finished in 1.00s\n")
        for prefix, value in events:
            transcript.accept("stderr", prefix.encode() + b" " + guardian.json_bytes(value))
        return transcript.finish()

    def test_actual_nested_matrix_shape_accepts_all_16_configurations_and_400_completions(self):
        result = self.parse("matrix", self.matrix_events())
        self.assertEqual(result["configurations"], 16)
        self.assertEqual(result["workers"], 40)
        self.assertEqual(result["coordinated_rounds"], 160)
        self.assertEqual(result["measured_worker_completions"], 400)

    def test_nested_matrix_qualification_and_worker_correspondence_are_required(self):
        original = self.matrix_events()
        first = next(index for index, (prefix, _value) in enumerate(original)
                     if prefix == "RESOURCE_CONFIGURATION")
        mutations = (
            lambda value: value["rounds"][0]["concurrency_qualification"].update(qualified=False),
            lambda value: value["rounds"][0]["concurrency_qualification"].update(workers=4),
            lambda value: value["rounds"][0].update(workers=[]),
            lambda value: value["rounds"][1].update(round=0),
            lambda value: value["rounds"][0]["workers"][0].update(seconds=0.123),
            lambda value: value["rounds"][0].update(parent_dispatch_offsets_ns=[]),
        )
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                events = json.loads(json.dumps(original))
                mutate(events[first][1])
                with self.assertRaises(guardian.JobError):
                    self.parse("matrix", events)

    def test_duplicate_missing_and_wrong_matrix_configuration_round_or_worker_refuse(self):
        original = self.matrix_events()
        configuration = next(index for index, (prefix, _value) in enumerate(original)
                             if prefix == "RESOURCE_CONFIGURATION")
        completion = next(index for index, (prefix, _value) in enumerate(original)
                          if prefix == "RESOURCE_ROUND")
        variants = [original + [original[configuration]], original + [original[completion]],
                    original[:configuration] + original[configuration + 1:],
                    original[:completion] + original[completion + 1:]]
        changed = json.loads(json.dumps(original))
        changed[completion][1]["worker"] = 3
        variants.append(changed)
        for events in variants:
            with self.subTest(events=len(events)):
                with self.assertRaises(guardian.JobError):
                    self.parse("matrix", events)

    def test_all_six_actual_busy_attempt_shapes_and_pending_cancel_are_required(self):
        result = self.parse("busy", self.busy_events())
        self.assertEqual(result["attempts"], 6)
        self.assertEqual(result["numerical_completions"], 5)
        self.assertEqual(result["real_pending_cancellations"], 1)

    def test_busy_duplicate_missing_wrong_outcome_or_cancel_boundary_refuse(self):
        original = self.busy_events()
        variants = [original + [original[0]], original[:-1]]
        for key, value in (("outcome", "Ok(())"), ("pending", 0),
                           ("cancel_to_kernel_return_seconds", 0.251)):
            changed = json.loads(json.dumps(original))
            changed[-1][1][key] = value
            variants.append(changed)
        for events in variants:
            with self.subTest(events=events[-1]):
                with self.assertRaises(guardian.JobError):
                    self.parse("busy", events)


class MatrixQualificationTests(ApiFreeCase):
    """#36 outcome classification: qualified, bounded re-qualification, inconclusive,
    and budgets that stay red in every attempt. Synthetic transcripts only."""

    parse = staticmethod(CaseTranscriptTests.parse)
    matrix_events = staticmethod(CaseTranscriptTests.matrix_events)
    SLOW = (0, 3, 0.0556, 0.020)  # the observed 55.6 ms poll; decode well within budget

    def test_requalified_configuration_is_qualified_with_all_attempts_recorded(self):
        # Proves: CL-007-04 (#36 bounded re-qualification).
        result = self.parse("matrix", self.matrix_events({5: [self.SLOW, self.SLOW, None]}))
        self.assertEqual(result["outcome"], guardian.QUALIFIED)
        self.assertEqual(result["attempts"], 18)
        self.assertEqual(result["measured_worker_completions"], 400 + 2 * 40)
        self.assertEqual(result["inconclusive_configurations"], [])

    def test_three_unqualified_attempts_are_inconclusive_not_failed(self):
        # Proves: CL-007-04 (#36 inconclusive outcome).
        result = self.parse("matrix", self.matrix_events({5: [self.SLOW] * 3}))
        self.assertEqual(result["outcome"], guardian.INCONCLUSIVE)
        self.assertEqual(len(result["inconclusive_configurations"]), 1)
        entry = result["inconclusive_configurations"][0]
        self.assertEqual((entry["mode"], entry["scalar"], entry["long"], entry["concurrency"],
                          entry["attempts"]), ("ft8", True, False, 4, 3))
        self.assertEqual(entry["unqualified_polls"][0]["max_poll_wall_seconds"], 0.0556)

    def test_ordinary_gate_reports_inconclusive_as_not_run_and_strict_refuses_it(self):
        # Proves: CL-007-04 (#36 ordinary gate vs exclusive window).
        evidence = {"case": "matrix",
                    "transcript": self.parse("matrix", self.matrix_events({5: [self.SLOW] * 3}))}
        ordinary, strict = io.StringIO(), io.StringIO()
        self.assertEqual(guardian.report_outcome(evidence, True, ordinary), guardian.NOT_RUN)
        self.assertEqual(guardian.NOT_RUN, 77)
        self.assertIn("INCONCLUSIVE, NOT RUN", ordinary.getvalue())
        self.assertIn("ft8 scalar=True long=False workers=4", ordinary.getvalue())
        self.assertEqual(guardian.report_outcome(evidence, False, strict),
                         guardian.INCONCLUSIVE_REFUSED)
        self.assertIn("INCONCLUSIVE, REFUSED", strict.getvalue())
        qualified = {"case": "matrix", "transcript": self.parse("matrix", self.matrix_events())}
        for ordinary_gate in (True, False):
            output = io.StringIO()
            self.assertEqual(guardian.report_outcome(qualified, ordinary_gate, output), 0)
            self.assertIn("QUALIFIED", output.getvalue())

    def test_cli_default_is_strict_and_ordinary_gate_is_matrix_only(self):
        # Proves: CL-007-04 (#36 exclusive window stays strict by default).
        evidence = {"case": "matrix",
                    "transcript": self.parse("matrix", self.matrix_events({5: [self.SLOW] * 3}))}
        receipt = ["--artifact-receipt", "unused.json"]
        with patch.object(guardian, "run_case", return_value=evidence), \
                patch.object(sys, "stderr", io.StringIO()):
            self.assertEqual(guardian.main(["run", "--case", "matrix", *receipt]),
                             guardian.INCONCLUSIVE_REFUSED)
            self.assertEqual(guardian.main(["run", "--case", "matrix", "--ordinary-gate",
                                            *receipt]), 77)
        with patch.object(guardian, "run_case",
                          side_effect=AssertionError("must refuse before launch")), \
                patch.object(sys, "stderr", io.StringIO()):
            self.assertEqual(guardian.main(["run", "--case", "busy", "--ordinary-gate",
                                            *receipt]), 1)

    def test_qualified_or_unqualified_budget_violation_is_still_red(self):
        # Proves: CL-007-04 (#36: a qualified run over budget stays red).
        # Injected slow decodes: ft8 short single worker has 5 s rounds and 7 s cold.
        over_round = (0, 3, 0.001, 5.5)
        cases = {
            "qualified slow round": {0: [over_round]},
            "slow round in an unqualified attempt": {0: [(0, 3, 0.0556, 5.5), None]},
            "slow round in a requalification": {0: [self.SLOW, over_round]},
            "slow round with four workers over the 2x bound": {1: [(2, 7, 0.001, 10.5)]},
        }
        for name, extra in cases.items():
            with self.subTest(name):
                with self.assertRaises(guardian.JobError) as caught:
                    self.parse("matrix", self.matrix_events(extra))
                self.assertEqual(caught.exception.operation, "matrix_budget_exceeded")
        within = self.parse("matrix", self.matrix_events({1: [(2, 7, 0.001, 9.9)]}))
        self.assertEqual(within["outcome"], guardian.QUALIFIED)
        original = self.matrix_events()
        first = next(index for index, (prefix, _value) in enumerate(original)
                     if prefix == "RESOURCE_CONFIGURATION")
        for name, mutate in (
            ("slow cold decode", lambda value: value["prepared"][0].update(cold_seconds=7.5)),
            ("worker over 64 MiB", lambda value: value["metrics"][0].update(
                absolute_private_peak_within64MiB=False)),
        ):
            with self.subTest(name):
                events = json.loads(json.dumps(original))
                mutate(events[first][1])
                with self.assertRaises(guardian.JobError) as caught:
                    self.parse("matrix", events)
                self.assertEqual(caught.exception.operation, "matrix_budget_exceeded")

    def test_false_qualification_claims_and_unbounded_or_early_stop_refuse(self):
        # Proves: CL-007-04 (#36: inconclusive cannot be forged or stopped early).
        original = self.matrix_events()
        first = next(index for index, (prefix, _value) in enumerate(original)
                     if prefix == "RESOURCE_CONFIGURATION")
        claims = (
            lambda value: value["rounds"][0]["workers"][0].update(max_poll_wall_seconds=0.06),
            lambda value: value["prepared"][0].update(warmup_max_poll_wall_seconds=0.06),
            lambda value: value.update(cpu_quantum_qualified=False),
            lambda value: value.update(unqualified_polls=[{}]),
            lambda value: value.pop("prepared"),
        )
        for mutate in claims:
            with self.subTest(mutation=mutate):
                events = json.loads(json.dumps(original))
                mutate(events[first][1])
                rounds = events[first][1]["rounds"]
                for prefix, value in events:
                    if prefix == "RESOURCE_ROUND" and value["configuration"] == 0:
                        value["result"] = rounds[value["result"]["round"]]["workers"][
                            value["worker"]]
                with self.assertRaises(guardian.JobError):
                    self.parse("matrix", events)
        for extra in ({5: [self.SLOW, self.SLOW]}, {5: [self.SLOW] * 4},
                      {5: [None, self.SLOW]}):
            with self.subTest(extra=extra):
                with self.assertRaises(guardian.JobError):
                    self.parse("matrix", self.matrix_events(extra))


class FakeRunPipe(FakePipe):
    def __init__(self, fail_flush=False):
        super().__init__()
        self.fail_flush = fail_flush
        self.close_called = False

    def flush(self):
        super().flush()
        if self.fail_flush:
            raise OSError("controlled partial GO/flush failure")

    def close(self):
        self.close_called = True


class FakeRunChild:
    def __init__(self, fail_flush=False, fail_wait=False):
        self.pid, self._handle, self.code = 456, 789, None
        self.stdin = FakeRunPipe(fail_flush)
        self.stdout, self.stderr = io.BytesIO(), io.BytesIO()
        self.kills, self.waits, self.fail_wait = 0, [], fail_wait

    def poll(self):
        return self.code

    def kill(self):
        self.kills += 1
        self.code = -1

    def wait(self, timeout):
        self.waits.append(timeout)
        if self.fail_wait:
            raise TimeoutError("controlled reap uncertainty")
        if self.code is None:
            self.code = 0
        return self.code


class FakeRunJob:
    def __init__(self, child, fault=None):
        self.child, self.fault = child, fault
        self.queries, self.assignments, self.terminations, self.closes = 0, [], 0, 0

    def assign(self, handle):
        self.assignments.append(handle)

    def active(self):
        self.queries += 1
        if self.fault == "query":
            raise guardian.JobError("QueryInformationJobObject", 5)
        return 1 if self.queries == 1 and self.terminations == 0 else 0

    def terminate(self):
        self.terminations += 1
        if self.fault == "terminate":
            raise guardian.JobError("TerminateJobObject", 5)
        if self.assignments:
            self.child.code = 1

    def close(self):
        self.closes += 1
        if self.fault == "close":
            raise guardian.JobError("CloseJobHandle", 5)


class FakeReader:
    def __init__(self, alive=False):
        self.alive, self.joins = alive, []

    def join(self, timeout):
        self.joins.append(timeout)

    def is_alive(self):
        return self.alive


class OwnerCleanupTests(ApiFreeCase):
    def run_fake(self, root, fail_flush=False, fail_wait=False, job_fault=None, reader_alive=False):
        child = FakeRunChild(fail_flush, fail_wait)
        job = FakeRunJob(child, job_fault)
        readers = [FakeReader(reader_alive), FakeReader()]
        pins = {"owned fixture": "fixed source pin"}

        def fake_readers(_child, events, _stop, owned):
            owned.extend(readers)
            events.put(("stderr", ready_line(), None))
            events.put(("stdout", None, None))
            events.put(("stderr", None, None))

        with patch.object(guardian, "OwnedJob", return_value=job), \
                patch.object(guardian.subprocess, "Popen", return_value=child), \
                patch.object(guardian.subprocess, "CREATE_NO_WINDOW", 0, create=True), \
                patch.object(guardian, "start_readers", side_effect=fake_readers), \
                patch.object(guardian, "CaseTranscript") as transcript, \
                patch.object(guardian, "source_snapshot", return_value=pins), \
                patch.object(guardian.secrets, "token_hex", return_value="a" * 32):
            transcript.return_value.finish.return_value = {"fixed API-free transcript": True}
            budget = guardian.Budget(100, 10, clock=lambda: 0.)
            try:
                result = guardian.run_owned(["fixed nonexecuted fixture"], "matrix", root, root,
                                             budget, pins)
            except guardian.JobError:
                result = None
        evidence = json.loads((root / "matrix.receipt.json").read_bytes())
        return result, evidence, child, job, readers

    def test_normal_owner_requires_zero_activity_reap_readers_and_own_handle_close(self):
        with tempfile.TemporaryDirectory() as directory:
            result, evidence, child, job, readers = self.run_fake(Path(directory))
        self.assertIsNotNone(result)
        self.assertTrue(evidence["complete"])
        self.assertTrue(evidence["cleanup_complete"])
        self.assertTrue(evidence["job_active_zero"])
        self.assertTrue(evidence["parent_reaped"])
        self.assertTrue(evidence["readers_joined"])
        self.assertEqual(job.assignments, [789])
        self.assertEqual(job.closes, 1)
        self.assertEqual(job.terminations, 0)
        self.assertEqual(child.kills, 0)
        self.assertEqual(child.stdin.flushes, 1)
        self.assertTrue(all(reader.joins for reader in readers))

    def test_partial_go_failure_uses_owned_job_not_leaf_pid_kill(self):
        with tempfile.TemporaryDirectory() as directory:
            result, evidence, child, job, _readers = self.run_fake(Path(directory), fail_flush=True)
        self.assertIsNone(result)
        self.assertFalse(evidence["complete"])
        self.assertTrue(evidence["go_attempted"])
        self.assertEqual(job.terminations, 1)
        self.assertEqual(child.kills, 0)

    def test_cleanup_uncertainty_never_becomes_complete_evidence(self):
        for fault in ("query", "terminate", "close", "reader", "reap"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                result, evidence, _child, _job, _readers = self.run_fake(
                    Path(directory), fail_flush=fault == "terminate", fail_wait=fault == "reap",
                    job_fault=fault if fault in ("query", "terminate", "close") else None,
                    reader_alive=fault == "reader")
                self.assertIsNone(result)
                self.assertFalse(evidence["complete"])
                self.assertFalse(evidence["cleanup_complete"])
                self.assertTrue(evidence["cleanup_errors"])

    def test_second_reader_start_failure_retains_and_joins_first_reader(self):
        created = []

        class StartFailureThread:
            def __init__(self, target, args, daemon):
                self.target, self.args, self.daemon = target, args, daemon
                self.index = len(created)
                self.started = self.joined = False
                created.append(self)

            def start(self):
                if self.index == 1:
                    raise RuntimeError("controlled second reader start failure")
                self.started = True

            def join(self, timeout):
                if not self.started:
                    raise RuntimeError("cannot join unstarted reader")
                self.joined = True

            def is_alive(self):
                return self.started and not self.joined

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            child = FakeRunChild()
            job = FakeRunJob(child)
            pins = {"fixed ownership fixture": "no target execution"}
            with patch.object(guardian, "OwnedJob", return_value=job), \
                    patch.object(guardian.subprocess, "Popen", return_value=child), \
                    patch.object(guardian.subprocess, "CREATE_NO_WINDOW", 0, create=True), \
                    patch.object(guardian.threading, "Thread", side_effect=StartFailureThread), \
                    patch.object(guardian, "CaseTranscript"), \
                    patch.object(guardian, "source_snapshot", return_value=pins), \
                    patch.object(guardian.secrets, "token_hex", return_value="a" * 32):
                with self.assertRaises(guardian.JobError):
                    guardian.run_owned(["fixed nonexecuted fixture"], "matrix", root, root,
                                         guardian.Budget(100, 10, clock=lambda: 0.), pins)
            self.assertEqual(len(created), 2)
            self.assertTrue(created[0].joined, "a started first reader must remain owned on failure")
            self.assertFalse(created[1].started)
            self.assertTrue(child.stdout.closed)
            self.assertTrue(child.stderr.closed, "unstarted stderr reader must not retain its pipe")
            self.assertEqual(child.kills, 1, "the pre-GO unassigned parent is still an owned leaf")
            self.assertEqual(job.assignments, [])
            evidence = json.loads((root / "matrix.receipt.json").read_bytes())
            self.assertFalse(evidence["go_attempted"])
            self.assertFalse(evidence["readers_joined"])
            self.assertFalse(evidence["cleanup_complete"])
            self.assertFalse(evidence["complete"])
            self.assertTrue(evidence["cleanup_errors"])


class RegistryTests(ApiFreeCase):
    def test_registry_keeps_pipefail_full_ordinary_inventory_and_guarded_matrix_pair(self):
        root = Path(__file__).resolve().parents[1]
        source = (root / ".harness/suites.yaml").read_text(encoding="utf-8")
        entry = source.split("- suite: decoder-quality\n", 1)[1].split("\n- suite:", 1)[0]
        self.assertIn("set -euo pipefail", entry)
        self.assertIn("cargo test --release --locked --test decoder_signal --message-format=json", entry)
        self.assertIn("--test-threads=1 --skip release_runtime_and_overlapping_window_history", entry)
        self.assertIn("| python tools/windows_resource_job.py resolve", entry)
        self.assertIn("python tools/windows_resource_job.py run --case matrix", entry)
        # #36: only the ordinary gate tolerates an inconclusive matrix.
        self.assertIn("run --case matrix --ordinary-gate --artifact-receipt", entry)
        for name in ("tools/windows_resource_job.py", "tools/test_windows_resource_job.py",
                     "tools/windows_process_metrics.py", "tools/test_windows_process_metrics.py"):
            self.assertGreaterEqual(entry.count("- " + name), 2)
        self.assertIn("test_windows_resource_job.py", entry)
        self.assertIn("test_windows_process_metrics.py", entry)


def smoke_child():
    """One fixed separately authorized containment fixture, never a unit test."""
    case = os.environ.get("WSTX_RESOURCE_GUARDIAN_CASE")
    nonce = os.environ.get("WSTX_RESOURCE_GUARDIAN_NONCE", "")
    guardian.require(case == "smoke" and len(nonce) == 32 and
                     all(character in "0123456789abcdef" for character in nonce), "smoke_context")
    sys.stderr.write(guardian.READY_PREFIX +
                     guardian.json_bytes({"v": 1, "case": case, "nonce": nonce,
                                          "pid": os.getpid()}).decode("utf-8"))
    sys.stderr.flush()
    line = sys.stdin.buffer.readline(8193)
    prefix = guardian.GO_PREFIX.encode()
    guardian.require(len(line) <= 8192 and line.endswith(b"\n") and line.startswith(prefix),
                     "smoke_go_line")

    def unique_object(pairs):
        result = {}
        for name, value in pairs:
            if name in result:
                raise guardian.JobError("smoke_duplicate_go_key")
            result[name] = value
        return result

    go = json.loads(line[len(prefix):], object_pairs_hook=unique_object)
    guardian.require(isinstance(go, dict) and set(go) == {"v", "case", "nonce"} and
                     type(go["v"]) is int and go["v"] == 1 and
                     go["case"] == case and go["nonce"] == nonce, "smoke_go_identity")
    descendant = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(120)"],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        close_fds=True,
        creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0,
    )
    sys.stderr.write("WSTX_GUARDIAN_DESCENDANT " +
                     guardian.json_bytes({"pid": descendant.pid}).decode("utf-8"))
    sys.stderr.flush()
    descendant.wait()


if __name__ == "__main__":
    if sys.argv[1:] == ["--smoke-child"]:
        smoke_child()
    else:
        unittest.main()

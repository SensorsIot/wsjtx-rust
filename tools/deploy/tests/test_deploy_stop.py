"""station-update.ps1's stop path: delivery of each signal, the forced stop and the PTT check after it.

TC-178-01 to TC-178-07. The station, the Ctrl+C helper and the station's GET /transmit are the mocks of
test_deploy_flow.py on the drill's clock: the helper's exit and Windows error per signal, a
station that stays after a delivered signal, and the readings of each boot. The update's log
lines, the flow log (one `stop` per stop) and the install record are the oracle.
"""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_deploy_flow as flow  # noqa: E402
from station_drill import COMMIT, CURRENT, PREVIOUS  # noqa: E402
import station_drill  # noqa: E402

UNDELIVERED = {"c": [3, 6], "b": [3, 6]}
STAYS = {"stay": True}
OK = "released,false,not_needed"
PENDING = "released,false,pending"
PROBE_FAIL = ("PROBE FAIL listener PID 4242 runs another image", "1")
PAGE_RED = ("LIVE PAGE CHECK RED see the PAGE CHECK line", "1")
PAGE_ERROR = ("LIVE PAGE CHECK ERROR the check exited with 9", "2")
BEFORE = "before the forced stop: ptt released, transmitting false, arm_state disarmed"


def lines_of(out):
    """The update's log lines without their HH:mm:ss stamp."""
    return [re.sub(r"^\d\d:\d\d:\d\d ", "", line) for line in out.splitlines()]


class StopPathTests(flow.FlowCase):
    def assert_in_order(self, out, expected):
        got = lines_of(out)
        at = -1
        for line in expected:
            self.assertIn(line, got[at + 1:], f"{line!r} not after line {at}\n{out}")
            at = got.index(line, at + 1)

    def reads(self, boot):
        """The clock (s) of each GET /transmit of that boot."""
        return [int(line.rsplit(" t=", 1)[1]) for line in self.flow if line.startswith(f"transmit boot={boot} ")]

    def record(self, n=171):
        lines = self.post(n).splitlines()
        self.assert_postable("\n".join(lines))
        return lines

    def stop_lines(self, lines):
        return [line for line in lines if line.startswith("Station stop:")]

    # Proves: TC-178-01
    def test_graceful_stop_reads_nothing_after_the_start(self):
        rc, out, steps = self.deploy()
        self.assertEqual(rc, 0, out)
        self.assertIn("graceful stop (Ctrl+C) sent to PID 4242: helper exit 0", lines_of(out))
        self.assertNotIn("Ctrl+Break", out)
        self.assertNotIn("FORCED STOP", out)
        self.assertEqual(self.reads(1), [], self.flow)
        lines = self.record()
        self.assertEqual(lines[1:3], [f"Previous version: {CURRENT}", "Station stop: graceful"])

    # Proves: TC-178-02
    def test_undelivered_ctrl_c_names_the_failed_call_and_its_error(self):
        cases = [("AttachConsole error 6", UNDELIVERED, "helper exit 3, AttachConsole error 6"),
                 ("GenerateConsoleCtrlEvent error 5", {"c": [4, 5], "b": [4, 5]}, "helper exit 4, GenerateConsoleCtrlEvent error 5"),
                 ("no error code readable", {"c": [3, None], "b": [3, None]}, "helper exit 3, AttachConsole error unknown")]
        for name, stop, text in cases:
            with self.subTest(name):
                self.tearDown()
                self.setUp()
                rc, out, steps = self.deploy(stops=[stop], reads={1: [OK]})
                self.assertEqual(rc, 0, out)
                self.assert_in_order(out, [f"graceful stop (Ctrl+C) NOT DELIVERED to PID 4242: {text}",
                                           f"Ctrl+Break sent to PID 4242 after an undelivered Ctrl+C: {text}",
                                           BEFORE,
                                           "FORCED STOP of PID 4242: Ctrl+C not delivered, Ctrl+Break not delivered"])
                self.assertNotIn("ignored", out)
                self.assertEqual([s for s in steps if s.startswith("stop")], ["stop ccccccccc lock=held"], self.flow)
                self.assertIn("FORCED STOP", steps)

    # Proves: TC-178-03
    def test_delivered_ctrl_c_with_the_station_still_running(self):
        rc, out, steps = self.deploy(stops=[STAYS], reads={1: [OK]})
        self.assertEqual(rc, 0, out)
        self.assert_in_order(out, ["graceful stop (Ctrl+C) sent to PID 4242: helper exit 0",
                                   "Ctrl+C delivered, PID 4242 still runs after 8 s; Ctrl+Break sent: helper exit 0",
                                   BEFORE, "FORCED STOP of PID 4242: Ctrl+C delivered, Ctrl+Break delivered"])
        self.assertIn("Station stop: forced (Ctrl+C delivered), PTT after it: confirmed released (startup_release not_needed)",
                      self.record())
        # The same Ctrl+C with helper exit 3 is not called delivered.
        self.tearDown()
        self.setUp()
        rc, out, steps = self.deploy(stops=[dict(UNDELIVERED, stay=True)], reads={1: [OK]})
        self.assertNotIn("Ctrl+C delivered, PID 4242 still runs", out)
        self.assertIn("Ctrl+Break sent to PID 4242 after an undelivered Ctrl+C: helper exit 3, AttachConsole error 6", lines_of(out))

    # Proves: TC-178-04
    def test_forced_stop_confirmed_from_the_next_start(self):
        for value in ("not_needed", "released"):
            with self.subTest(value):
                self.tearDown()
                self.setUp()
                rc, out, steps = self.deploy(stops=[UNDELIVERED], reads={1: [PENDING, PENDING, f"released,false,{value}"]})
                self.assertEqual(rc, 0, out)
                self.assert_in_order(out, [BEFORE, "FORCED STOP of PID 4242: Ctrl+C not delivered, Ctrl+Break not delivered",
                                           "start new version",
                                           f"PTT after the forced stop: confirmed released (startup_release {value})"])
                t = self.reads(1)
                self.assertEqual(len(t), 3, self.flow)
                self.assertEqual([b - a for a, b in zip(t, t[1:])], [2, 2], t)
                self.assertEqual([s for s in steps if s.startswith(("probe", "page-check"))], ["probe lock=held", "page-check lock=free"])
                lines = self.record()
                self.assertEqual(lines[0], f"Install record: {COMMIT} installed")
                self.assertEqual(self.stop_lines(lines), [
                    f"Station stop: forced (Ctrl+C not delivered, AttachConsole error 6), PTT after it: confirmed released (startup_release {value})"])

    # Proves: TC-178-04
    def test_unreadable_state_before_the_forced_stop_does_not_stop_the_update(self):
        rc, out, steps = self.deploy(stops=[UNDELIVERED], reads={1: [PENDING, OK]}, before_throw=True)
        self.assertEqual(rc, 0, out)
        self.assert_in_order(out, ["before the forced stop: transmit state unreadable (WebException)",
                                   "FORCED STOP of PID 4242: Ctrl+C not delivered, Ctrl+Break not delivered",
                                   "start new version", "PTT after the forced stop: confirmed released (startup_release not_needed)"])
        self.assertIn("FORCED STOP", steps)
        self.assertTrue([s for s in steps if s.startswith("start 123456789")], steps)

    # Proves: TC-178-05
    def test_forced_stop_not_confirmed_installs_with_exit_1_and_no_second_stop(self):
        cases = [("failed", ["released,false,failed"], "ptt released, transmitting false, startup_release failed"),
                 ("keyed", ["keyed,false,not_needed"], "ptt keyed, transmitting false, startup_release not_needed"),
                 ("indeterminate", ["indeterminate,false,not_needed"], "ptt indeterminate, transmitting false, startup_release not_needed"),
                 ("transmitting", ["released,true,not_needed"], "ptt released, transmitting true, startup_release not_needed"),
                 ("pending 30 s", [PENDING], "startup_release still pending after 30 s"),
                 ("unreadable", ["throw"], "transmit state unreadable")]
        for name, readings, reason in cases:
            with self.subTest(name):
                self.tearDown()
                self.setUp()
                record_call = self.cr_state_at("harness", "general")
                rc, out, steps = self.deploy(stops=[UNDELIVERED], reads={1: readings})
                self.assertEqual(rc, 1, out)
                self.assertIn(f"PTT RELEASE NOT CONFIRMED after the forced stop: {reason}; check the radio", lines_of(out))
                self.assertEqual([s for s in steps if s.startswith("stop")], ["stop ccccccccc lock=held"], self.flow)
                self.assertIn("probe lock=held", steps)
                self.assertIn("page-check lock=free", steps)
                self.assertIn(record_call, steps)
                if name == "pending 30 s":
                    t = self.reads(1)
                    self.assertEqual(t[-1] - t[0], 30, t)
                lines = self.record()
                self.assertEqual(lines[0], f"Install record: {COMMIT} installed")
                self.assertIn(f"Station stop: forced (Ctrl+C not delivered, AttachConsole error 6), PTT after it: NOT CONFIRMED ({reason})", lines)
                self.assertIn("Return to the previous version: none", lines)

    # Proves: TC-178-05
    def test_failed_proof_after_an_unconfirmed_release_makes_no_return(self):
        cases = [("probe exit 1", PROBE_FAIL, flow.PAGE_PASS), ("page check exit 1", flow.PROBE_PASS, PAGE_RED),
                 ("page check exit 2", flow.PROBE_PASS, PAGE_ERROR)]
        for result, probe, page in cases:
            with self.subTest(result):
                self.tearDown()
                self.setUp()
                rc, out, steps = self.deploy(probe, page, stops=[UNDELIVERED], reads={1: ["released,false,failed"]})
                self.assertEqual(rc, 1, out)
                self.assertIn(f"NO RETURN: {result} after a PTT release that was not confirmed; 123456789 stays running, "
                              "check the radio and run station-update.ps1 -Rollback", lines_of(out))
                self.assertEqual([s for s in steps if s.startswith("stop")], ["stop ccccccccc lock=held"], self.flow)
                self.assertNotIn("returning to the previous version", out)
                self.assertNotIn("switching back", out)
                self.assertNotIn("waiting for update.lock", out)
                self.assertEqual([s for s in steps if s.startswith("python")], [], steps)
                self.assertEqual(self.active(), COMMIT)
                self.assertEqual(sorted(os.listdir(self.posts)), ["171.txt"], out)
                lines = self.record()
                self.assertEqual(lines[0], f"Install record: {COMMIT} not returned")
                self.assertIn(f"Return to the previous version: none ({result}, PTT release not confirmed, no second stop)", lines)

    # Proves: TC-178-06
    def test_the_return_confirms_the_release_after_its_forced_stop(self):
        stops = [{}, UNDELIVERED]
        rc, out, steps = self.deploy(PROBE_FAIL, stops=stops, reads={2: [PENDING, OK]})
        self.assertEqual(rc, 1, out)
        self.assert_in_order(out, ["returning to the previous version: probe exit 1", "switching back to ccccccccc",
                                   "FORCED STOP of PID 4242: Ctrl+C not delivered, Ctrl+Break not delivered",
                                   "PTT after the forced stop: confirmed released (startup_release not_needed)"])
        self.assertEqual(len(self.reads(2)), 2, self.flow)
        self.assertEqual(self.active(), CURRENT)
        lines = self.record()
        self.assertEqual(lines[0], f"Install record: {COMMIT} returned")
        self.assertEqual(self.stop_lines(lines), [
            "Station stop: graceful",
            "Station stop: forced (Ctrl+C not delivered, AttachConsole error 6), PTT after it: confirmed released (startup_release not_needed)"])
        # The confirmation fails: no further stop, exit 1, the previous version stays.
        self.tearDown()
        self.setUp()
        rc, out, steps = self.deploy(PROBE_FAIL, stops=stops, reads={2: ["released,false,failed"]})
        self.assertEqual(rc, 1, out)
        self.assertIn("PTT RELEASE NOT CONFIRMED after the forced stop: ptt released, transmitting false, startup_release failed; check the radio",
                      lines_of(out))
        self.assertEqual([s for s in steps if s.startswith("stop")], ["stop ccccccccc lock=held", "stop 123456789 lock=held"], self.flow)
        self.assertEqual(self.active(), CURRENT)
        self.assertEqual(len(self.stop_lines(self.record())), 2)

    # Proves: TC-178-07
    def test_rollback_with_a_forced_stop_reads_nothing_and_exits_1(self):
        station_drill.rollback_previous(self.s)
        rc, out, steps = self.deploy(stops=[UNDELIVERED], rollback=True)
        self.assertEqual(rc, 1, out)
        self.assert_in_order(out, ["before the forced stop: transmit state not read (-Rollback has no agent client)",
                                   "FORCED STOP of PID 4242: Ctrl+C not delivered, Ctrl+Break not delivered",
                                   "PTT after the forced stop not read (-Rollback has no agent client); check the radio"])
        self.assertEqual([line for line in self.flow if line.startswith("transmit ")], [], self.flow)
        self.assertEqual(self.active(), PREVIOUS)


if __name__ == "__main__":
    unittest.main()

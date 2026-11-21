"""The Ctrl+C helper of station-update.ps1, run for real on Windows (TC-178-08).

Send-CtrlC is taken from station-process.ps1 and Signal-Text from station-update.ps1 by the
PowerShell parser, and run as the update runs them (Start-Process of the helper, hidden). The targets are only processes this test
starts: one that has exited (no such process) and a hidden powershell.exe sleeping in its own
console. The oracle is Windows: AttachConsole on a process that does not exist fails with
ERROR_INVALID_PARAMETER (87); a delivered Ctrl+C ends the sleeping powershell.exe.
"""
import base64
import os
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import station_drill  # noqa: E402

# The helper's error report, the one line per failed call that the negative removes.
REPORT = "[IO.File]::WriteAllText(`$f, [string]`$e); "

RUNNER = r"""
param([string]$Process, [string]$Script, [string]$Station, [int]$TargetPid)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
$CtrlErrFile = Join-Path $Station 'logs\helper-test-ctrl.txt'
foreach ($from in @(@($Process, 'Send-CtrlC'), @($Script, 'Signal-Text'))) {
  $tokens = $null; $errs = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($from[0], [ref]$tokens, [ref]$errs)
  foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $from[1] }, $true)) {
    . ([scriptblock]::Create($f.Extent.Text)) } }
$s = Send-CtrlC $TargetPid
"RC $($s.Rc)"
if ($s.Delivered) { "LINE graceful stop (Ctrl+C) sent to PID ${TargetPid}: $(Signal-Text $s)" }
else { "LINE graceful stop (Ctrl+C) NOT DELIVERED to PID ${TargetPid}: $(Signal-Text $s)" }
"""


def hidden_console():
    """Flags and startup info for a process in its own console, its window hidden."""
    info = subprocess.STARTUPINFO()
    info.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    info.wShowWindow = 0  # SW_HIDE
    return subprocess.CREATE_NEW_CONSOLE, info


@unittest.skipUnless(os.name == "nt", "the helper uses the Windows console API")
class CtrlHelperTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.station = os.path.join(self.tmp.name, "station")
        os.makedirs(os.path.join(self.station, "logs"))
        self.children = []

    def tearDown(self):
        for child in self.children:
            if child.poll() is None:
                child.kill()
                child.wait(10)
        self.tmp.cleanup()

    def process(self, report=True):
        """A copy of station-process.ps1, without the helper's error report for the negative."""
        with open(station_drill.PROCESS, encoding="utf-8-sig") as f:
            text = f.read()
        self.assertEqual(text.count(REPORT), 2, "the helper's error report is not where the test expects it")
        if not report:
            text = text.replace(REPORT, "")
        path = os.path.join(self.tmp.name, "station-process.ps1" if report else "no-report.ps1")
        with open(path, "w", encoding="utf-8-sig") as f:
            f.write(text)
        return path

    def send(self, pid, report=True):
        runner = os.path.join(self.tmp.name, "runner.ps1")
        with open(runner, "w", encoding="utf-8-sig") as f:
            f.write(RUNNER)
        proc = subprocess.run([station_drill.POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", runner,
                               "-Process", self.process(report), "-Script", station_drill.SCRIPT, "-Station", self.station,
                               "-TargetPid", str(pid)],
                              capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
        out = proc.stdout + proc.stderr
        self.assertEqual(proc.returncode, 0, out)
        rc = next(line for line in out.splitlines() if line.startswith("RC "))
        line = next(line for line in out.splitlines() if line.startswith("LINE "))
        return int(rc[3:]), line[5:], out

    def gone_pid(self):
        """The PID of a process this test started and that has exited."""
        flags, info = hidden_console()
        child = subprocess.Popen(["cmd.exe", "/c", "exit 0"], creationflags=flags, startupinfo=info)
        child.wait(30)
        return child.pid

    def assert_names_the_error(self, line, pid):
        self.assertEqual(line, f"graceful stop (Ctrl+C) NOT DELIVERED to PID {pid}: helper exit 3, AttachConsole error 87")

    # Proves: TC-178-08
    def test_no_such_process_is_attachconsole_error_87(self):
        pid = self.gone_pid()
        rc, line, out = self.send(pid)
        self.assertEqual(rc, 3, out)
        self.assert_names_the_error(line, pid)
        # Negative: without the helper's error report the line has no error code and fails.
        rc, line, out = self.send(pid, report=False)
        self.assertEqual(rc, 3, out)
        self.assertIn("error unknown", line)
        with self.assertRaises(AssertionError):
            self.assert_names_the_error(line, pid)

    # Proves: TC-178-08
    def test_ctrl_c_reaches_a_process_in_its_own_console(self):
        # The "ignore Ctrl+C" flag is inherited from whatever started this test; the child clears
        # it for itself, so the test proves the helper's delivery, then says it is ready.
        ready = os.path.join(self.tmp.name, "ready.txt")
        command = ("Add-Type -Namespace T -Name K -MemberDefinition '[DllImport(\"kernel32.dll\")] public static extern bool "
                   "SetConsoleCtrlHandler(System.IntPtr h, bool a);'; [T.K]::SetConsoleCtrlHandler([IntPtr]::Zero, $false) | Out-Null; "
                   f"Set-Content -LiteralPath '{ready}' -Value ready; Start-Sleep 60")
        encoded = base64.b64encode(command.encode("utf-16-le")).decode("ascii")
        flags, info = hidden_console()
        child = subprocess.Popen([station_drill.POWERSHELL, "-NoProfile", "-EncodedCommand", encoded], creationflags=flags,
                                 startupinfo=info)
        self.children.append(child)
        deadline = time.monotonic() + 60
        while not os.path.exists(ready) and child.poll() is None and time.monotonic() < deadline:
            time.sleep(0.2)
        self.assertTrue(os.path.exists(ready), "the sleeping powershell.exe did not become ready")
        time.sleep(0.5)
        self.assertIsNone(child.poll(), "the sleeping powershell.exe ended before the Ctrl+C")
        rc, line, out = self.send(child.pid)
        self.assertEqual(rc, 0, out)
        self.assertEqual(line, f"graceful stop (Ctrl+C) sent to PID {child.pid}: helper exit 0")
        child.wait(8)


if __name__ == "__main__":
    unittest.main()

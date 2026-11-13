"""Run a Windows PowerShell script in a child process with mock functions loaded first.

Functions shadow cmdlets of the same name, so a prelude can replace every command that
reaches the system (scheduled task, firewall, processes, network) for a test.
"""
import os
import subprocess
import tempfile

POWERSHELL = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), r"System32\WindowsPowerShell\v1.0\powershell.exe")


def ps_quote(text):
    return "'" + str(text).replace("'", "''") + "'"


def run(script, args=(), prelude="", env=None, timeout=120):
    """Return (exit code, stdout+stderr) of `& script @args` after dot-sourcing the prelude."""
    with tempfile.TemporaryDirectory() as tmp:
        pre = os.path.join(tmp, "prelude.ps1")
        with open(pre, "w", encoding="utf-8-sig") as f:
            f.write(prelude)
        call = "& " + ps_quote(script) + "".join(" " + (a if a.startswith("-") else ps_quote(a)) for a in args)
        command = f". {ps_quote(pre)}; {call}; exit $LASTEXITCODE"
        proc = subprocess.run([POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
                              capture_output=True, text=True, encoding="utf-8", errors="replace",
                              env=dict(os.environ, **(env or {})), timeout=timeout)
        return proc.returncode, proc.stdout + proc.stderr

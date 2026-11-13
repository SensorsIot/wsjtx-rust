"""station_drill.py (#34): the drill refuses unknown commands and catches a lost refusal."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import station_drill  # noqa: E402


def real_script():
    return station_drill.SCRIPT


def read(path):
    with open(path, encoding="utf-8-sig") as f:
        return f.read()


def case(name):
    return next(c for c in station_drill.CASES if c[0] == name)


class ClassifyTests(unittest.TestCase):
    def test_unknown_command_or_type_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "s.ps1")
            with open(path, "w", encoding="utf-8") as f:
                f.write("Get-Content x\nRestart-Computer -Force\n[Diagnostics.Process]::Start('x')\n")
            self.assertEqual(station_drill.classify(path), ["Restart-Computer", "[Diagnostics.Process]"])
            self.assertEqual(station_drill.main(["--script", path]), 2)

    def test_call_of_a_path_or_variable_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "s.ps1")
            for call in ("& \"$PSHOME\\powershell.exe\" -File x", ". $r", "& $r"):
                with open(path, "w", encoding="utf-8") as f:
                    f.write(f"$r=Get-Content x; $r.Length\n{call}\n")
                self.assertEqual(station_drill.classify(path), ["(call-without-name)"], call)

    def test_escape_routes_of_the_review_are_refused(self):
        """Add-Type P/Invoke, engine script invocation, other environment and live paths."""
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "s.ps1")
            with open(path, "w", encoding="utf-8") as f:
                f.write("$t = Add-Type -MemberDefinition 'x' -Name C -PassThru\n"
                        "$ExecutionContext.InvokeCommand.InvokeScript('Start-ScheduledTask')\n"
                        "Copy-Item x -Destination 'C:\\Users\\HB9BLA\\AppData\\Local\\WstxRust\\station\\active.json'\n"
                        "Get-Content \"$env:USERPROFILE\\x\"\n"
                        "Get-Content '\\\\server\\share\\x'\n"
                        "Write-Output \"$(Restart-Computer)\"\n")
            self.assertEqual(station_drill.classify(path), [
                "(path-C:\\Users\\HB9BLA\\AppData\\Local\\WstxRust\\station\\active.json)",
                "(path-\\\\server\\share\\x)", "(variable-ExecutionContext)", "(variable-env:USERPROFILE)", "Add-Type",
                "Restart-Computer"])

    def test_here_string_content_is_not_a_command(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "s.ps1")
            with open(path, "w", encoding="utf-8") as f:
                f.write("$c=@\"\nRestart-Computer\n\"@\nStart-Process -FilePath powershell.exe -ArgumentList $c\n")
            self.assertEqual(station_drill.classify(path), [])


class LostRefusalTests(unittest.TestCase):
    def run_one(self, script_text, name):
        with tempfile.TemporaryDirectory() as tmp:
            script = os.path.join(tmp, "station-update.ps1")
            with open(script, "w", encoding="utf-8") as f:
                f.write(script_text)
            root = os.path.join(tmp, "case")
            os.makedirs(root)
            return station_drill.run_case(root, script, case(name))

    def test_real_script_refuses_a_tampered_artifact(self):
        text = read(real_script())
        problems, out = self.run_one(text, "tampered artifact")
        self.assertEqual(problems, [], out)

    def test_removed_refusal_fails_the_case(self):
        text = read(real_script())
        line = 'if ((Hash $src) -ne $f.sha256) { throw "Package file $($f.path) does not match the manifest." }'
        self.assertIn(line, text)
        problems, out = self.run_one(text.replace(line, ""), "tampered artifact")
        self.assertTrue(problems, out)
        # The script still refuses later for another reason; that does not count as this refusal.
        self.assertIn("expected message", problems[0])


if __name__ == "__main__":
    unittest.main()

"""TR-22: comments, docstrings and Markdown prose hold no issue pointer, date or change story;
test and tool strings, Markdown code and test function names hold no issue pointer; an
exception holds only its own text in its own file.

Each case builds a temporary git repository from hand-written fixtures. The accepted fixture
(one file per syntax) stands in every case, so each negative file is refused beside it with
exactly its own fault lines, written by hand. A fixture text is joined at run time: `t()`
drops each `~`, so this file holds none of the texts it checks.
"""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("comment_rule_tool", Path(__file__).resolve().parents[2] / "sysml.py")
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

LIST = "tools/sysml/comment-exceptions.json"


def t(text: str) -> str:
    return text.replace("~", "")


POINTER, DATE = t("#~12"), t("20~26-11-18")
COMMON = (
    "Keeps the station time for FR-001, CL-001-01, TC-001-001 and TR-14.",
    "Proves: TC-001-001",
    "Adapted from WSJT-X 2.7.0 lib/ft8/ft8b.f90, licensed GPL-3.0-or-later.",
    "WSJT-X lib/ft8/sync8.f90 lines 40-72 compute the same sync.",
    t("See https://github.com/owner/repo/issues/1~2#issuecomment-3456~789 for the format."),
    t("&#10227; marks a refresh; ##~12 and #~12a are no pointers, nor is review 12345."),
    "The callsigns CR6L and PR7AB and the rig ICR10 are no pointers.",
)


def lines(prefix: str, end: str = "") -> str:
    return "".join(f"{prefix}{line}{end}\n" for line in COMMON)


HARNESS_CONFIG = "harness_paths:\n  - harness/\n  - .github/workflows/harness.yml\n"
ACCEPTED = {
    "server/src/clock.rs": lines("// ") + "/* " + COMMON[0] + " */\n" + t(
        "/// Seconds since 19~70-01-01.\n"
        'pub const RANK: &str = "rank #~12";\n'
        'pub const SLASHES: &str = "a // b";\n'
        "#[cfg(test)]\nmod tests {\n    // Proves: TC-001-001\n    #[test]\n    fn ticks_after_15_s() {}\n}\n"),
    "server/tests/clock.rs": lines("// ") + t(
        "// The capture of 20~26-11-18 holds the decodes.\n"
        'const RAW: &str = r#"a "quoted" // part"#; const AFTER: u8 = 1;\n'
        'const NOTE: &str = "recorded 20~26-11-18 in the leg~acy form";\n'
        '#[test]\nfn decodes_after_15_s() {\n    let _ = "a // b";\n}\n'),
    "server/src/mcp.rs": t("// MCP 20~25-11-25 is the leg~acy protocol version.\n"),
    "server/src/open.rs": t("// Waits for #~12.\n"),
    "server/third-party/lib/lib.rs": t("// See #~12, recorded 20~26-11-18.\n"),
    "client/app.js": lines("// ") + "/* " + COMMON[0] + " */\n" + t("const RANK='rank #~12',SLASHES=\"a // b\";\n"),
    "tests/clock.test.cjs": lines("// ") + t(
        "const quoted=/\"#~12/,klass=/[/]#~12'/g;\n"
        "const DATA='recorded 20~26-11-18, leg~acy',ranked='Most Wanted #~3';\n"
        "test('the clock ticks after 15 s',()=>{const s=`a ${'b'} // c`;});\n"),
    "client/style.css": "/*\n" + lines(" * ") + " */\n" + t("a{color:#~123456}\n"),
    "client/index.html": "<!doctype html>\n<!--\n" + lines("  ") + "-->\n<p>&#10227; refresh</p>\n"
                         '<script src="/app.js"></script>\n',
    "tools/clock.py": '"""' + "\n".join(COMMON) + '\n"""\n' + lines("# ") + t(
        'SLASHES = "a // b"\nNOTE = "recorded 20~26-11-18, leg~acy"\n\n\n'
        'def test_ticks_after_15_s():\n    """The clock ticks."""\n'),
    "tools/deploy/clock.ps1": lines("# ") + "<#\n" + lines("  ") + "#>\n" + t(
        "$note = 'recorded 20~26-11-18, leg~acy'\n$here = @\"\na // b\n\"@\n"),
    "Cargo.toml": lines("# ") + '[package]\nname = "clock"\n',
    ".github/workflows/product.yml": lines("# ") + "name: product\non: push\njobs:\n  a:\n"
                                     "    runs-on: windows-latest\n    steps:\n      - run: |\n          echo a\n",
    ".github/workflows/harness.yml": t("# See #~12, recorded 20~26-11-18.\nname: harness\n"),
    "harness/project/config.yaml": HARNESS_CONFIG,
    "tools/sysml/Clock.java": lines("// ") + "/**\n" + lines(" * ") + " */\nclass Clock { String s = \"a // b\"; }\n",
    "tests/fixtures/clock/Clock.sysml": lines("// ") + "package Clock {\n    doc /* " + COMMON[0]
                                        + " */\n    attribute a : String = \"a // b\";\n}\n",
    "tools/clock.md": "# Clock\n\n" + "\n".join(COMMON) + "\n\n" + t("Run `cargo test` on the recorded data:\n\n"
                                                                   "```text\nrecorded 20~26-11-18\n```\n"),
}
# One entry of each kind; lines 2 to 7 of the list.
ENTRIES = [
    {"path": "server/src/clock.rs", "text": t("19~70-01-01"), "kind": "D1"},
    {"path": "server/src/mcp.rs", "text": t("20~25-11-25"), "kind": "D2"},
    {"path": "server/tests/clock.rs", "text": DATE, "kind": "D3"},
    {"path": "server/src/mcp.rs", "text": t("leg~acy"), "kind": "M"},
    {"path": "tests/clock.test.cjs", "text": t("Most Wanted #~3"), "kind": "S"},
    {"path": "server/src/open.rs", "text": POINTER, "kind": "I"},
]


def listing(entries) -> str:
    """The exception list, one entry per line from line 2."""
    return "[\n" + ",\n".join("  " + json.dumps(entry) for entry in entries) + "\n]\n"


def check(files: dict, entries=None, raw=None) -> tuple[list[str], int, int]:
    """(fault lines, files read, exceptions used) of TR-22 on a repository of `files`."""
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        subprocess.run(["git", "-c", "core.autocrlf=false", "init", "-q", str(root)], check=True, env=env)
        written = dict(files)
        if raw is not None:
            written[LIST] = raw
        elif entries is not None:
            written[LIST] = listing(entries)
        for key, text in written.items():
            path = root / key
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(text if isinstance(text, bytes) else text.encode("utf-8"))
        subprocess.run(["git", "-c", "core.autocrlf=false", "-C", str(root), "add", "-A"], check=True, env=env,
                       capture_output=True)
        faults, read, used = tool.history_faults(root)
        return tool.fault_lines(faults), read, used


class CommentRuleTest(unittest.TestCase):
    def refused(self, files: dict, expected: dict, entries=ENTRIES):
        """`files` beside the accepted fixture: each file gives exactly its own expected lines."""
        found, _read, _used = check({**ACCEPTED, **files}, entries)
        for key in sorted(expected):
            with self.subTest(key):
                self.assertEqual([line for line in found if re.search(rf": {re.escape(key)}(?::\d+)?$", line)],
                                 expected[key])
        self.assertEqual(sorted(found), sorted(line for lines_of in expected.values() for line in lines_of))

    def test_this_repository(self):
        """TV-163 (TR-22): `traces` on this repository passes and every exception entry is used."""
        entries = json.loads((ROOT / LIST).read_text(encoding="utf-8"))
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(tool.main(["traces"]), 0, output.getvalue())
        self.assertIn(f", {len(entries)} comment exceptions used;", output.getvalue())

    def test_accepted(self):
        """TV-164 (TR-22): one fixture per syntax with present-tense comments, tags, identities, a licence
        header, a WSJT-X reference, a URL, `#[test]`, a raw string, a regular expression, a CSS colour,
        callsigns, a timed test name, strings of product code, a third-party file, a harness workflow
        and one exception entry of each kind gives no fault."""
        found, read, used = check(ACCEPTED, ENTRIES)
        self.assertEqual(found, [])
        self.assertEqual((read, used), (15, 6))

    def test_pointer_in_each_comment_syntax(self):
        """TV-165 (TR-22): `#N` in a comment of each syntax is refused at its line."""
        cases = {
            "server/src/n1_line.rs": ("fn a() {}\n// see #~12\n", 2),
            "server/src/n1_doc.rs": ("/// see #~12\nfn a() {}\n", 1),
            "server/src/n1_block.rs": ("/* one\n   two\n   see #~12 */\nfn a() {}\n", 3),
            "server/src/n1_after.rs": ("fn a() {} // see #~12\n", 1),
            "client/n1.js": ("const a=1;\n// see #~12\n", 2),
            "client/n1.css": ("/* see #~12 */\na{color:red}\n", 1),
            "client/n1.html": ("<p>a</p>\n<!-- see #~12 -->\n", 2),
            "tools/n1_comment.py": ("A = 1  # see #~12\n", 1),
            "tools/n1_doc.py": ('"""The clock.\n\nSee #~12.\n"""\n', 3),
            "tools/n1_line.ps1": ("# see #~12\n$a = 1\n", 1),
            "tools/n1_block.ps1": ("<# one\n   see #~12 #>\n$a = 1\n", 2),
            "tools/n1.toml": ("a = 1\n# see #~12\n", 2),
            ".github/workflows/n1.yml": ("name: a # see #~12\non: push\n", 1),
            "tools/n1/N1.java": ("class N1 {} // see #~12\n", 1),
            "tests/fixtures/n1/N1.sysml": ("package N1 {\n    doc /* see #~12 */\n}\n", 2),
            "tools/n1.md": ("# N1\n\nSee #~12 here.\n", 3),
        }
        self.refused({key: t(text) for key, (text, _) in cases.items()},
                     {key: [f"history in a comment: issue pointer {POINTER}: {key}:{line}"]
                      for key, (_, line) in cases.items()})

    def test_each_pointer_form_in_a_comment(self):
        """TV-166 (TR-22): each further pointer form in a comment, in letter-case variants, is refused with
        its text; `PR #N` and `Issue #N` with the text `#N`."""
        # (written form, fault text); a form whose fault text is the whole form has none.
        forms = [("harness#~12", None), ("Harness#~12", None), ("Owner/Repo#~12", None), ("owner/repo#~12", None),
                 ("issue ~12", None), ("ISSUE ~12", None), ("Issue-~12", None), ("issue_~12", None), ("CR~12", None),
                 ("cr ~12", None), ("Cr#~12", None), ("cr~12_x", "cr~12"), ("CR~12-x", "CR~12"), ("PR_~12", None),
                 ("pr_~12", None), ("Review 1234~56", None), ("REVIEW 1234~56", None), ("PR #~5", "#~5"),
                 ("Issue #~66", "#~66")]
        key = "server/src/n2.rs"
        text = "".join(f"// The rule of {t(form)} holds.\n" for form, _ in forms)
        self.refused({key: text}, {key: [f"history in a comment: issue pointer {t(shown or form)}: {key}:{number}"
                                         for number, (form, shown) in enumerate(forms, 1)]})

    def test_pointer_in_a_test_or_tool_string(self):
        """TV-167 (TR-22): a pointer in each string syntax and at each place of test and tool code, and in a
        Markdown code span and fenced block, is refused."""
        cases = {
            "server/tests/n3.rs": ('const A: &str = "see #~12";\nconst B: &str = r#"a "b" #~12"#;\n', [1, 2]),
            "tests/n3.cjs": ("const a='see #~12';\nconst b=\"see #~12\";\nconst c=`a ${a} #~12`;\n"
                             "test('ticks #~12',()=>{});\n", [1, 2, 3, 4]),
            "server/src/n3_tests.rs": ('const A: &str = "see #~12";\n', [1]),
            "server/src/n3_test.rs": ('const A: &str = "see #~12";\n', [1]),
            "tools/n3.py": ('A = "see #~12"\n', [1]),
            "fixtures/n3.py": ('A = "see #~12"\n', [1]),
            "tools/n3.ps1": ("$a = 'see #~12'\n$b = @\"\nsee #~12\n\"@\n", [1, 3]),
        }
        expected = {key: [f"issue pointer in a string: {POINTER}: {key}:{line}" for line in found]
                    for key, (_, found) in cases.items()}
        expected["tools/n3.md"] = [f"issue pointer in Markdown code: {POINTER}: tools/n3.md:{line}" for line in (3, 6)]
        files = {key: t(text) for key, (text, _) in cases.items()}
        files["tools/n3.md"] = t("# N3\n\nRun `see #~12` here.\n\n```text\nsee #~12\n```\n")
        self.refused(files, expected)

    def test_pointer_in_a_test_name(self):
        """TV-168 (TR-22): a Rust or Python test function whose name joins issue, cr or pr to a number is
        refused with its name."""
        rust, python = "server/src/n4.rs", "tools/test_n4.py"
        self.refused({
            rust: t("#[test]\nfn issue~_41_ticks() {}\n\n#[test]\nfn cr~18_ticks() {}\n\n"
                    "#[tokio::test]\nasync fn ticks_pr~_5() {}\n"),
            python: t("def test_ticks_issue~_41():\n    pass\n\n\ndef test_cr~_18_ticks():\n    pass\n\n\n"
                      "def test_pr~5_ticks():\n    pass\n"),
        }, {
            rust: [f"issue pointer in a test name: {t(name)}: {rust}:{line}"
                   for name, line in (("issue~_41_ticks", 2), ("cr~18_ticks", 5), ("ticks_pr~_5", 8))],
            python: [f"issue pointer in a test name: {t(name)}: {python}:{line}"
                     for name, line in (("test_ticks_issue~_41", 1), ("test_cr~_18_ticks", 5), ("test_pr~5_ticks", 9))],
        })

    def test_date_in_a_comment(self):
        """TV-169 (TR-22): a date in a comment of each reader, and a date with its time, is refused."""
        cases = {
            "server/src/n5.rs": ("// recorded 20~26-11-18\n", 1),
            "client/n5.js": ("// recorded 20~26-11-18\n", 1),
            "client/n5.css": ("/* recorded 20~26-11-18 */\n", 1),
            "tools/n5/N5.java": ("// recorded 20~26-11-18\nclass N5 {}\n", 1),
            "tests/fixtures/n5/N5.sysml": ("package N5 {\n    doc /* recorded 20~26-11-18 */\n}\n", 2),
            "tools/n5_comment.py": ("# recorded 20~26-11-18\n", 1),
            "tools/n5_doc.py": ('"""Recorded 20~26-11-18."""\n', 1),
            "tools/n5.ps1": ("# recorded 20~26-11-18\n", 1),
            "tools/n5.toml": ("# recorded 20~26-11-18\n", 1),
            ".github/workflows/n5.yml": ("# recorded 20~26-11-18\nname: n5\n", 1),
            "tools/n5.md": ("Recorded 20~26-11-18.\n", 1),
            "server/src/n5_time.rs": ("// recorded 20~26-11-18T10:00Z\n", 1),
        }
        self.refused({key: t(text) for key, (text, _) in cases.items()},
                     {key: [f"history in a comment: date {DATE}: {key}:{line}"] for key, (_, line) in cases.items()})

    def test_change_story_in_a_comment_and_in_prose(self):
        """TV-170 (TR-22): each word and phrase of the change-story list, in lower, upper and mixed case, at
        line start and mid-line, is refused in a comment and in Markdown prose."""
        phrases = [t(phrase) for phrase in (
            "form~erly", "previ~ously", "no lon~ger", "any m~ore", "anym~ore", "as bef~ore", "used t~o",
            "origi~nally", "reti~red", "leg~acy", "was chan~ged", "were chan~ged", "red on the par~ent",
            "review find~ing", "finding ~3", "round ~4", "operator gr~ill", "operator dec~ision",
            "coordinator dec~ision", "coordinator's dec~ision", "live def~ect", "live find~ing")]
        shown = [variant for phrase in phrases
                 for variant in (phrase, phrase.upper(), " ".join(word[:1].upper() + word[1:] for word in phrase.split(" ")))]
        texts = [text for variant in shown for text in (f"{variant} holds here.", f"Here {variant} holds.")]
        found = [variant for variant in shown for _ in range(2)]
        comment, prose = "server/src/n6.rs", "tools/n6.md"
        self.refused({comment: "".join(f"// {text}\n" for text in texts), prose: "".join(f"{text}\n" for text in texts)},
                     {key: [f"history in a comment: change story {variant}: {key}:{number}"
                            for number, variant in enumerate(found, 1)] for key in (comment, prose)})

    def test_pointer_after_a_url(self):
        """TV-171 (TR-22): a pointer after a URL on the same line is refused; the URL's digits are not."""
        key = "server/src/n7.rs"
        self.refused({key: t("// See https://example.org/a/1~2/b#3~4 and #~12.\n")},
                     {key: [f"history in a comment: issue pointer {POINTER}: {key}:1"]})

    def test_exception_holds_only_its_file_and_text(self):
        """TV-172 (TR-22): a listed date in another file, and a second trigger on the listed line, are refused."""
        listed, other = "server/src/n8_a.rs", "server/src/n8_b.rs"
        self.refused({listed: t("// Recorded 20~26-11-18, see #~12.\n"), other: t("// Recorded 20~26-11-18.\n")},
                     {listed: [f"history in a comment: issue pointer {POINTER}: {listed}:1"],
                      other: [f"history in a comment: date {DATE}: {other}:1"]},
                     ENTRIES + [{"path": listed, "text": DATE, "kind": "D3"}])

    def test_unused_exception(self):
        """TV-173 (TR-22): an exception entry that matches nothing is refused at its line."""
        unused = t("20~26-01-01")
        self.refused({}, {LIST: [f"comment exception unused: server/src/clock.rs {unused}: {LIST}:8"]},
                     ENTRIES + [{"path": "server/src/clock.rs", "text": unused, "kind": "D3"}])

    def test_malformed_exception(self):
        """TV-174 (TR-22): an entry without path or text or with a kind outside D1, D2, D3, M, S, I, and a
        list that is no JSON array, are refused."""
        self.refused({}, {LIST: [f"comment exception malformed: no path: {LIST}:8",
                                 f"comment exception malformed: no text: {LIST}:9",
                                 f"comment exception malformed: kind D4 is not one of D1, D2, D3, M, S, I: {LIST}:10"]},
                     ENTRIES + [{"text": "x", "kind": "D3"}, {"path": "server/src/clock.rs", "kind": "D3"},
                                {"path": "server/src/clock.rs", "text": "x", "kind": "D4"}])
        for raw in ('{"path": "server/src/a.rs", "text": "x", "kind": "D3"}\n',
                    '[\n  {"path": "server/src/a.rs", "text": "x", "kind": "D3"},\n]\n'):
            with self.subTest(raw):
                found, _read, _used = check({"server/src/a.rs": "// Keeps the time.\n"}, raw=raw)
                self.assertEqual(found, [f"comment exception malformed: not a JSON array: {LIST}:1"])

    def test_source_not_utf8(self):
        """TV-175 (TR-22): a read file that is not UTF-8 is refused by its path; so is a text its reader
        cannot read."""
        self.refused({"server/src/n11.rs": b"// caf\xe9 time\n", "tests/n11.cjs": "const a=(/abc\n);\n"},
                     {"server/src/n11.rs": ["source not UTF-8: server/src/n11.rs"],
                      "tests/n11.cjs": ["source not readable: a / that opens no regular expression the line closes: "
                                        "tests/n11.cjs:1"]})

    def test_each_place_read(self):
        """TV-176 (TR-22): `#N` in a comment is refused at each place read."""
        comment = t("# see #~12\n")
        cases = {
            "server/src/n12.rs": t("// see #~12\n"),
            "client/n12.js": t("// see #~12\n"),
            "tests/n12.cjs": t("// see #~12\n"),
            "tools/n12.py": comment,
            "fixtures/n12.py": comment,
            ".github/workflows/n12.yml": comment + "name: n12\n",
            "README.md": t("See #~12.\n"),
            "Cargo.toml": comment + ACCEPTED["Cargo.toml"],
            "server/Cargo.toml": comment,
            "rust-toolchain.toml": comment,
        }
        self.refused(cases, {key: [f"history in a comment: issue pointer {POINTER}: {key}:1"] for key in cases})


if __name__ == "__main__":
    unittest.main()

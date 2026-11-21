"""TR-24: `test-hooks` lists the product files that hold a test item, a test switch or a hook.

Each case builds a scratch git repository from hand-written fixtures: a passing product, one
form added, and the files the command is expected to list, written by hand. The output and the
refusals run the tool as a process whose repository is the fixture, as the ratchet runs it.
"""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[2] / "sysml.py"
ROOT = TOOL.parents[1]
LIST = ROOT / "tools/sysml/product-knows-no-test.txt"
spec = importlib.util.spec_from_file_location("test_hooks_tool", TOOL)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)

RUNNER = ("import importlib.util, sys\nfrom pathlib import Path\n"
          "spec = importlib.util.spec_from_file_location('sysml_tool', sys.argv[1])\n"
          "tool = importlib.util.module_from_spec(spec)\nspec.loader.exec_module(tool)\n"
          "root = tool.ROOT = Path(sys.argv[2])\ntool.MODELS, tool.FSD = root / 'docs/sysml', root / 'docs/WSTX Rust FSD.md'\n"
          "raise SystemExit(tool.main(sys.argv[3:]))\n")

MODEL = "\n".join([
    "package Model {",
    "    doc /* The station keeps its profile below LOCALAPPDATA. */",
    '    attribute variable = "WSTX_NAMED";',
    '    attribute port = "WSTX_X_PORT";',
    "}",
    "",
])
PRODUCT = "\n".join([
    "pub struct Pair {",
    "    pub left: u32,",
    "}",
    "",
    "pub fn double(x: u32) -> u32 {",
    "    let y = x * 2;",
    "    y",
    "}",
    "",
])
APP = "\n".join([
    "const state = {};",
    "function start() {}",
    "window.wstxApp = Object.freeze({ start, snapshot: () => state });",
    "",
])
PAGE = "\n".join([
    "window.wstxApp.start();",
    "window.wstxApp?.snapshot();",
    "",
])
BASE = {
    "docs/sysml/Model.sysml": MODEL,
    "server/src/main.rs": "mod a;\n\nfn main() {}\n",
    "server/src/a.rs": PRODUCT,
    "client/app.js": APP,
    "client/page.js": PAGE,
}
# Every listed form, in files that are no product files.
RUST_FORMS = "\n".join([
    "#[cfg(test)]",
    "mod inline {}",
    "#[cfg(debug_assertions)]",
    "#[doc(hidden)]",
    "pub fn hook() {",
    '    let _ = std::env::var("WSTX_UNNAMED");',
    "    let _ = cfg!(test);",
    "}",
    "mod k_tests;",
    "",
])
JS_FORMS = "\n".join([
    "module.exports = {};",
    "exports.x = 1;",
    "const v = process.env.X;",
    "window.wstxOnlyTests = Object.freeze({ load });",
    "",
])


def environment() -> dict:
    return {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}


def git(root: Path, *args: str) -> None:
    subprocess.run(["git", "-c", "core.autocrlf=false", "-C", str(root), *args], check=True, capture_output=True,
                   env=environment())


def edit(files: dict, key: str, old: str, new: str) -> dict:
    assert old in files[key], (key, old)
    return {**files, key: files[key].replace(old, new, 1)}


class Fixture(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.folder, ignore_errors=True)
        self.count = 0

    def repository(self, files: dict, untracked: dict | None = None) -> Path:
        """A scratch repository whose index and working tree hold `files`, beside `untracked`."""
        self.count += 1
        root = self.folder / f"r{self.count}"
        root.mkdir()
        git(root, "init", "-q", "-b", "master")
        for key, text in files.items():
            target = root / key
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(text if isinstance(text, bytes) else text.encode("utf-8"))
        git(root, "add", "-A")
        for key, text in (untracked or {}).items():
            target = root / key
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(text.encode("utf-8"))
        return root

    def found(self, files: dict) -> list[tuple]:
        return tool.test_hooks(self.repository(files))

    def paths(self, files: dict) -> list[str]:
        return sorted({key for key, _line, _form, _text in self.found(files)})

    def forms(self, files: dict) -> list[tuple[str, str]]:
        return [(form, text) for _key, _line, form, text in self.found(files)]

    def run_tool(self, root: Path, *argv: str) -> tuple[int, list[str], str]:
        result = subprocess.run([sys.executable, "-c", RUNNER, str(TOOL), str(root), *argv], cwd=root,
                                capture_output=True, env=environment(), timeout=300)
        return (result.returncode, result.stdout.decode("utf-8", "replace").splitlines(),
                result.stderr.decode("utf-8", "replace").replace("\r\n", "\n"))

    def assert_listed_alone(self, files: dict, key: str, form: str):
        found = self.found(files)
        self.assertEqual(sorted({item[0] for item in found}), [key], found)
        self.assertEqual({item[2] for item in found}, {form}, found)


class AcceptedTests(Fixture):
    def test_tv245_accepted_forms(self):
        """TV-245 (TR-24): test-file declarations, forms in comments and strings, product
        variables, debug_assert!, forms in test, tool and fixture files and read client
        globals print nothing, with and without --lines, exit 0."""
        main = "\n".join([
            "//! The station.",
            "//!",
            "//! ```",
            "//! #[cfg(test)]",
            "//! let x = cfg!(test);",
            "//! #[doc(hidden)]",
            '//! let y = std::env::var("WSTX_X");',
            "//! ```",
            "mod a;",
            "mod b;",
            "mod c;",
            "#[cfg(all(test, not(debug_assertions)))]",
            "mod d_tests;",
            "#[cfg(test)]",
            "mod tests;",
            "#[cfg(test)]",
            "mod e_tests;",
            "#[cfg(test)]",
            "mod f_test;",
            "",
            '// #[cfg(test)] cfg!(test) #[doc(hidden)] env::var("WSTX_X")',
            "/* #[cfg(test)] cfg!(test) #[doc(hidden)] env::var(\"WSTX_X\") */",
            "fn main() {",
            '    let s = "#[cfg(test)] cfg!(test) #[doc(hidden)] env::var(\\"WSTX_X\\")";',
            '    let r = r#"#[cfg(test)] cfg!(test) #[doc(hidden)] env::var("WSTX_X")"#;',
            '    let named = std::env::var("WSTX_NAMED");',
            '    let local = std::env::var_os("LOCALAPPDATA");',
            '    let version = env!("CARGO_PKG_VERSION");',
            '    let servers = option_env!("WSTX_NAMED");',
            "    debug_assert!(s.len() > 0);",
            "    let _ = (r, named, local, version, servers);",
            "}",
            "",
        ])
        files = {
            **BASE,
            "server/src/main.rs": main,
            "server/src/a.rs": '#[cfg(test)] #[path = "a_tests.rs"] pub(crate) mod tests;\n' + PRODUCT,
            "server/src/a_tests.rs": RUST_FORMS,
            "server/src/b.rs": "#[cfg(test)] mod b_tests;\n",
            "server/src/b/b_tests.rs": RUST_FORMS,
            "server/src/c.rs": '#[cfg(test)]\n#[cfg(not(debug_assertions))]\n#[path = "c_test.rs"] pub(super) mod tests;\n',
            "server/src/c_test.rs": RUST_FORMS,
            "server/src/d_tests.rs": RUST_FORMS,
            "server/src/tests.rs": RUST_FORMS,
            "server/src/e_tests.rs": RUST_FORMS,
            "server/src/f_test.rs": RUST_FORMS,
            "server/tests/g.rs": RUST_FORMS,
            "tests/h.test.cjs": JS_FORMS + "window.wstxApp.load();\n",
            "tools/i.py": "import os\nprint(os.environ.get('WSTX_UNNAMED'))\n",
            "fixtures/j.rs": RUST_FORMS,
            "client/view.js": "globalThis.wstxView = { render };\nfunction render() {}\nif (window.x == y) {}\n"
                              "const f = window.x => 1;\n",
            "client/page.js": PAGE + "globalThis.wstxView.render();\n",
        }
        root = self.repository(files)
        self.assertEqual(self.run_tool(root, "test-hooks"), (0, [], ""))
        self.assertEqual(self.run_tool(root, "test-hooks", "--lines"), (0, [], ""))


class TestPredicateTests(Fixture):
    def test_tv246_test_predicates(self):
        """TV-246 (TR-24): each test predicate added to a passing product file lists exactly
        that file; a test file declared without a test predicate is `test file declared`."""
        cases = {
            "field": edit(BASE, "server/src/a.rs", "    pub left: u32,", "    #[cfg(test)]\n    pub right: u32,\n    pub left: u32,"),
            "function": edit(BASE, "server/src/a.rs", "pub fn double", "#[cfg(test)]\nfn helper() {}\n\npub fn double"),
            "statement": edit(BASE, "server/src/a.rs", "    let y", "    #[cfg(test)]\n    let z = 1;\n    let y"),
            "not test": edit(BASE, "server/src/a.rs", "pub fn double", "#[cfg(not(test))]\nfn helper() {}\n\npub fn double"),
            "macro": edit(BASE, "server/src/a.rs", "    let y", "    let t = cfg!(test);\n    let y"),
            "any": edit(BASE, "server/src/a.rs", "pub fn double", "#[cfg(any(windows, test))]\nfn helper() {}\n\npub fn double"),
            "cfg_attr": edit(BASE, "server/src/a.rs", "pub struct", "#[cfg_attr(test, derive(Debug))]\npub struct"),
            "inner": edit(BASE, "server/src/a.rs", "pub struct", "#![cfg(test)]\n\npub struct"),
            "inline module": edit(BASE, "server/src/a.rs", "pub struct", "#[cfg(test)]\nmod tests {}\n\npub struct"),
            "use": edit(BASE, "server/src/a.rs", "pub struct", "#[cfg(test)]\nuse std::fmt;\n\npub struct"),
            "three lines": edit(BASE, "server/src/a.rs", "pub fn double", "#[cfg(\n    test\n)]\nfn helper() {}\n\npub fn double"),
        }
        for name, files in cases.items():
            with self.subTest(name):
                self.assert_listed_alone(files, "server/src/a.rs", "cfg test")
        helpers = {**edit(BASE, "server/src/a.rs", "pub struct", "#[cfg(test)]\nmod helpers;\n\npub struct"),
                   "server/src/a/helpers.rs": "pub fn helper() {}\n"}
        self.assert_listed_alone(helpers, "server/src/a.rs", "cfg test")
        for declaration in ("mod k_tests;", "#[cfg(windows)]\nmod k_tests;"):
            with self.subTest(declaration):
                files = {**edit(BASE, "server/src/a.rs", "pub struct", declaration + "\n\npub struct"),
                         "server/src/a/k_tests.rs": "fn check() {}\n"}
                self.assert_listed_alone(files, "server/src/a.rs", "test file declared")


class BuildProfileTests(Fixture):
    def test_tv247_build_profile_branches(self):
        """TV-247 (TR-24): each predicate naming debug_assertions is listed alone."""
        cases = {
            "function": edit(BASE, "server/src/a.rs", "pub fn double", "#[cfg(debug_assertions)]\nfn helper() {}\n\npub fn double"),
            "statement": edit(BASE, "server/src/a.rs", "    let y", "    #[cfg(not(debug_assertions))]\n    let z = 1;\n    let y"),
            "macro": edit(BASE, "server/src/a.rs", "    let y", "    let t = cfg!(debug_assertions);\n    let y"),
            "cfg_attr": edit(BASE, "server/src/a.rs", "pub fn double", "#[cfg_attr(debug_assertions, allow(dead_code))]\npub fn double"),
            "all": edit(BASE, "server/src/a.rs", "pub struct", "#[cfg(all(windows, not(debug_assertions)))]\nconst LIMIT: u32 = 1;\n\npub struct"),
        }
        for name, files in cases.items():
            with self.subTest(name):
                self.assert_listed_alone(files, "server/src/a.rs", "debug_assertions")


class HiddenItemTests(Fixture):
    def test_tv248_hidden_items(self):
        """TV-248 (TR-24): a doc attribute holding hidden is listed, public or private."""
        cases = {
            "public": edit(BASE, "server/src/a.rs", "pub fn double", "#[doc(hidden)]\npub fn double"),
            "private": edit(BASE, "server/src/a.rs", "pub struct", "#[doc(hidden)]\nfn helper() {}\n\npub struct"),
            "alias": edit(BASE, "server/src/a.rs", "pub fn double", '#[doc(hidden, alias = "x")]\npub fn double'),
        }
        for name, files in cases.items():
            with self.subTest(name):
                self.assert_listed_alone(files, "server/src/a.rs", "doc(hidden)")


class EnvironmentTests(Fixture):
    def test_tv249_environment_reads(self):
        """TV-249 (TR-24): each read of a variable the model does not name, each vars read, a
        name that is no literal and the use of an environment function is listed alone; the
        reads of WSTX_UNNAMED pass once the model names it."""
        def read(statement: str) -> dict:
            return edit(BASE, "server/src/a.rs", "    let y", f"    {statement}\n    let y")

        unnamed = {
            "var": read('let e = env::var("WSTX_UNNAMED");'),
            "var_os": read('let e = std::env::var_os("WSTX_UNNAMED");'),
            "option_env": read('let e = option_env!("WSTX_UNNAMED");'),
            "leading colons": read('let e = ::std::env::var("WSTX_UNNAMED");'),
            "std option_env": read('let e = std::option_env!("WSTX_UNNAMED");'),
            "std env": read('let e = std::env!("WSTX_UNNAMED");'),
            "core option_env": read('let e = core::option_env!("WSTX_UNNAMED");'),
        }
        others = {
            "whole word": read('let e = env::var("WSTX_X");'),
            "vars": read("let e = env::vars();"),
            "vars_os": read("let e = std::env::vars_os();"),
            "constant": {**read("let e = env::var(NAME);"),
                         "server/src/a.rs": read("let e = env::var(NAME);")["server/src/a.rs"]
                         + 'const NAME: &str = "WSTX_X";\n'},
            "manifest": read('let e = env!("CARGO_MANIFEST_DIR");'),
            "run time": read('let e = env::var("CARGO_PKG_VERSION");'),
            "use": edit(BASE, "server/src/a.rs", "pub struct", "use std::env::var;\n\npub struct"),
        }
        for name, files in {**unnamed, **others}.items():
            with self.subTest(name):
                self.assert_listed_alone(files, "server/src/a.rs", "environment")
        for name, files in unnamed.items():
            with self.subTest(name + " named"):
                named = {**files, "docs/sysml/Model.sysml": MODEL.replace("WSTX_NAMED", "WSTX_UNNAMED")}
                self.assertEqual(self.found(named), [])


class ClientTests(Fixture):
    def test_tv250_client_modules(self):
        """TV-250 (TR-24): CommonJS exports, process.env, a global no client file reads and an
        object member no client file reads through its global are each listed alone."""
        def extra(text: str, reader: str = "", test: str = "") -> dict:
            files = {**BASE, "client/extra.js": text}
            if reader:
                files["client/reader.js"] = reader
            if test:
                files["tests/extra.test.cjs"] = test
            return files

        cases = {
            "module.exports": (extra("module.exports = {};\n"), "CommonJS export"),
            "exports": (extra("exports.x = 1;\n"), "CommonJS export"),
            "typeof": (extra("if (typeof module !== 'undefined') {}\n"), "CommonJS export"),
            "process.env": (extra("const v = process.env.X;\n"), "process.env"),
            "window": (extra("window.wstxOnlyTests = 1;\n", test="window.wstxOnlyTests;\n"), "unread global"),
            "globalThis": (extra("const f = 1;\nglobalThis.y = f;\n", test="globalThis.y;\n"), "unread global"),
            "freeze": (extra("window.a = Object.freeze({load, snapshot: () => s});\n", "window.a?.snapshot();\n"),
                       "unread member"),
            "object": (extra("window.b = {annotate, loadHistory};\n", "window.b.loadHistory();\n"), "unread member"),
            "through a variable": (extra("window.a = Object.freeze({load});\n", "const c = window.a;\nc.load();\n"),
                                   "unread member"),
        }
        for name, (files, form) in cases.items():
            with self.subTest(name):
                self.assert_listed_alone(files, "client/extra.js", form)
        self.assertEqual(self.forms(cases["freeze"][0]), [("unread member", "a.load")])
        self.assertEqual(self.forms(cases["object"][0]), [("unread member", "b.annotate")])


class OutputTests(Fixture):
    FILES = {
        **BASE,
        "server/src/a.rs": "\n".join([
            "#[cfg(not(",
            "    test",
            "))]",
            "pub fn one() {}",
            "",
            "#[doc(hidden)]",
            "pub fn two() {}",
            "",
            "pub fn three() {",
            '    let _ = std::env::var("WSTX_UNNAMED");',
            "}",
            "",
        ]),
        "client/app.js": APP + "const v = process.env.X;\n",
    }

    def test_tv251_paths_and_lines(self):
        """TV-251 (TR-24): one sorted path per file, one line per form at its first line, exit 0
        with and without findings."""
        root = self.repository(self.FILES)
        self.assertEqual(self.run_tool(root, "test-hooks"), (0, ["client/app.js", "server/src/a.rs"], ""))
        self.assertEqual(self.run_tool(root, "test-hooks", "--lines"), (0, [
            "client/app.js:4: process.env: process.env",
            "server/src/a.rs:1: cfg test: #[cfg(not(test))]",
            "server/src/a.rs:6: doc(hidden): #[doc(hidden)]",
            'server/src/a.rs:10: environment: std::env::var("WSTX_UNNAMED")',
        ], ""))
        self.assertEqual(self.run_tool(self.repository(BASE), "test-hooks"), (0, [], ""))

    def test_tv251_files_not_read(self):
        """TV-251 (TR-24): an untracked product file, a tracked file deleted on disk and a file
        below server/examples/ are not listed."""
        form = "#[cfg(test)]\nfn helper() {}\n"
        untracked = self.repository(BASE, untracked={"server/src/b.rs": form})
        self.assertEqual(tool.test_hooks(untracked), [])
        deleted = self.repository({**BASE, "server/src/b.rs": form})
        (deleted / "server/src/b.rs").unlink()
        self.assertEqual(tool.test_hooks(deleted), [])
        self.assertEqual(self.found({**BASE, "server/examples/b.rs": form}), [])


class RefusalTests(Fixture):
    def test_tv252_refusals(self):
        """TV-252 (TR-24): a product file in Latin-1, a raw string without its end and a folder
        with no git work tree exit 2 with their message and an empty stdout."""
        latin = self.repository({**BASE, "server/src/a.rs": "// café\n".encode("latin-1") + PRODUCT.encode()})
        self.assertEqual(self.run_tool(latin, "test-hooks"),
                         (2, [], "SysML check failed: source not readable: server/src/a.rs:1: source not UTF-8\n"))
        raw = self.repository({**BASE, "server/src/a.rs": PRODUCT + 'pub fn open() {\n    let s = r#"open;\n}\n'})
        self.assertEqual(self.run_tool(raw, "test-hooks", "--lines"),
                         (2, [], "SysML check failed: source not readable: server/src/a.rs:10: a raw string without its end\n"))
        bare = self.folder / "bare"
        bare.mkdir()
        code, stdout, stderr = self.run_tool(bare, "test-hooks")
        self.assertEqual((code, stdout), (2, []))
        self.assertTrue(stderr.startswith("SysML check failed: "), stderr)


class ThisRepositoryTests(unittest.TestCase):
    def test_tv253_this_repository_matches_its_exception_list(self):
        """TV-253 (TR-24): test-hooks on this repository prints exactly the paths of
        tools/sysml/product-knows-no-test.txt."""
        listed = sorted(line.split("#", 1)[0].strip() for line in LIST.read_text(encoding="utf-8").splitlines()
                        if line.split("#", 1)[0].strip())
        found = tool.test_hooks(ROOT)
        self.assertEqual(sorted({key for key, _line, _form, _text in found}), listed,
                         "\n".join(f"{key}:{line}: {form}: {text}" for key, line, form, text in found))


if __name__ == "__main__":
    unittest.main()

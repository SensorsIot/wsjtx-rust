//! The Rust model-value reader on the fixture tree `tests/fixtures/model-values/` (TC-DOC-014),
//! against the hand-written list of expected values there.
#[allow(dead_code)]
#[path = "../src/model_values.rs"]
mod model_values;

use model_values::{Literal, Model, Number};
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

fn fixture() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../tests/fixtures/model-values")
}

fn expected() -> Value {
    let text = std::fs::read_to_string(fixture().join("expected.json")).unwrap();
    serde_json::from_str(&text).unwrap()
}

/// A fresh scratch folder, removed by the caller's `Scratch` guard.
struct Scratch(PathBuf);

impl Scratch {
    fn new() -> Scratch {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let dir = std::env::temp_dir().join(format!(
            "wstx-model-values-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        Scratch(dir)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Copies `from` to `to`, every file with the line ends `eol`.
fn copy_tree(from: &Path, to: &Path, eol: &str) {
    std::fs::create_dir_all(to).unwrap();
    for entry in std::fs::read_dir(from).unwrap() {
        let path = entry.unwrap().path();
        let target = to.join(path.file_name().unwrap());
        if path.is_dir() {
            copy_tree(&path, &target, eol);
        } else {
            let text = std::fs::read_to_string(&path).unwrap();
            let text = text.replace("\r\n", "\n").replace('\n', eol);
            std::fs::write(target, text).unwrap();
        }
    }
}

/// The fixture tree in a scratch folder, with line ends `eol` and the changes `change`.
fn tree(scratch: &Scratch, eol: &str, change: Option<&Value>) -> PathBuf {
    let root = scratch.0.join("model");
    let source = fixture().join(expected()["tree"].as_str().unwrap());
    match change.and_then(|c| c["folder"].as_str()) {
        Some("missing") => return root,
        Some("empty") => {
            std::fs::create_dir_all(&root).unwrap();
            return root;
        }
        Some(other) => panic!("unknown folder change {other}"),
        None => copy_tree(&source, &root, eol),
    }
    let Some(change) = change else { return root };
    for path in change["remove"].as_array().into_iter().flatten() {
        std::fs::remove_file(root.join(path.as_str().unwrap())).unwrap();
    }
    for (path, text) in change["write"].as_object().into_iter().flatten() {
        let target = root.join(path);
        std::fs::create_dir_all(target.parent().unwrap()).unwrap();
        std::fs::write(target, text.as_str().unwrap()).unwrap();
    }
    for (path, hex) in change["writeBytes"].as_object().into_iter().flatten() {
        let hex = hex.as_str().unwrap();
        let bytes: Vec<u8> = (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect();
        let target = root.join(path);
        std::fs::create_dir_all(target.parent().unwrap()).unwrap();
        std::fs::write(target, bytes).unwrap();
    }
    root
}

/// The expected value of the list as a literal.
fn literal(expect: &Value) -> Literal {
    let (kind, value) = expect.as_object().unwrap().iter().next().unwrap();
    match kind.as_str() {
        "integer" => Literal::Number(Number::Integer(value.as_i64().unwrap())),
        "real" => Literal::Number(Number::Real(value.as_f64().unwrap())),
        "null" => Literal::Null,
        "string" => Literal::String(value.as_str().unwrap().to_string()),
        "boolean" => Literal::Boolean(value.as_bool().unwrap()),
        "enum" => Literal::Enum(
            value[0].as_str().unwrap().to_string(),
            value[1].as_str().unwrap().to_string(),
        ),
        other => panic!("unknown expected kind {other}"),
    }
}

fn number(value: Option<Number>) -> Literal {
    value.map_or(Literal::Null, Literal::Number)
}

/// Reads `name` from `model` in the way `read` names.
fn read(model: &Model, name: &str, read: &str) -> Result<Literal, model_values::Error> {
    Ok(match read {
        "plain" => number(model.number(name)?),
        "unit" => number(model.number_with_unit(name)?),
        "string" => Literal::String(model.string(name)?),
        "boolean" => Literal::Boolean(model.boolean(name)?),
        "enum" => {
            let (def, member) = model.enum_value(name)?;
            Literal::Enum(def, member)
        }
        other => panic!("unknown read {other}"),
    })
}

fn read_field(
    usage: &model_values::Usage<'_>,
    field: &str,
    read: &str,
) -> Result<Literal, model_values::Error> {
    Ok(match read {
        "plain" => number(usage.number(field)?),
        "unit" => number(usage.number_with_unit(field)?),
        "string" => Literal::String(usage.string(field)?),
        other => panic!("unknown field read {other}"),
    })
}

/// Every value, member list and table of the list, read from the tree with line ends `eol`.
fn accepted(eol: &str) -> usize {
    let list = expected();
    let scratch = Scratch::new();
    let model = Model::at(tree(&scratch, eol, None));
    let mut count = 0;
    for case in list["values"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let actual = read(&model, name, case["read"].as_str().unwrap());
        assert_eq!(actual, Ok(literal(&case["expect"])), "{name}");
        count += 1;
    }
    for case in list["members"].as_array().unwrap() {
        let name = case["name"].as_str().unwrap();
        let expect: Vec<String> = serde_json::from_value(case["expect"].clone()).unwrap();
        assert_eq!(model.enum_members(name), Ok(expect), "{name}");
        count += 1;
    }
    for case in list["tables"].as_array().unwrap() {
        let (container, definition) = (
            case["container"].as_str().unwrap(),
            case["definition"].as_str().unwrap(),
        );
        let usages = model.table(container, definition).unwrap();
        let expect = case["expect"].as_array().unwrap();
        assert_eq!(
            usages.iter().map(|u| u.name.as_str()).collect::<Vec<_>>(),
            expect
                .iter()
                .map(|u| u["name"].as_str().unwrap())
                .collect::<Vec<_>>(),
            "{container} table of {definition}"
        );
        for (usage, want) in usages.iter().zip(expect) {
            let fields = want["fields"].as_array().unwrap();
            assert_eq!(
                usage.field_names(),
                fields
                    .iter()
                    .map(|f| f[0].as_str().unwrap())
                    .collect::<Vec<_>>(),
                "{}",
                usage.qualified
            );
            for field in fields {
                let name = field[0].as_str().unwrap();
                let actual = read_field(usage, name, field[1].as_str().unwrap());
                assert_eq!(
                    actual,
                    Ok(literal(&field[2])),
                    "{}::{name}",
                    usage.qualified
                );
                count += 1;
            }
        }
    }
    count
}

// Proves: CL-014-16; TC-DOC-014 (the Rust reader accepts every value of the fixture list).
#[test]
fn model_values_reads_every_fixture_value_in_lf_and_crlf() {
    let lf = accepted("\n");
    let crlf = accepted("\r\n");
    assert!(lf > 0, "the fixture list names no value");
    assert_eq!(lf, crlf);
}

// Proves: CL-014-16; TC-DOC-014 (the Rust reader refuses every fault of the fixture list).
#[test]
fn model_values_refuses_every_fixture_fault_naming_name_and_reason() {
    let list = expected();
    let cases = list["refused"].as_array().unwrap();
    assert!(!cases.is_empty(), "the fixture list names no fault");
    for eol in ["\n", "\r\n"] {
        for case in cases {
            let scratch = Scratch::new();
            let model = Model::at(tree(&scratch, eol, case.get("tree")));
            let reason = case["reason"].as_str().unwrap();
            let (name, failure) = if let Some(table) = case.get("table") {
                let container = table["container"].as_str().unwrap();
                let definition = table["definition"].as_str().unwrap();
                (
                    container,
                    model.table(container, definition).map(|_| ()).err(),
                )
            } else {
                let name = case["name"].as_str().unwrap();
                (
                    name,
                    read(&model, name, case["read"].as_str().unwrap())
                        .map(|_| ())
                        .err(),
                )
            };
            let failure = failure.unwrap_or_else(|| panic!("{name}: accepted, expected {reason}"));
            assert_eq!(failure.name, name, "{failure}");
            assert!(
                failure.reason.contains(reason),
                "{name}: reason {:?}, expected {reason:?}",
                failure.reason
            );
        }
    }
}

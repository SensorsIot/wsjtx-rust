//! The model-value reader of the Rust tests (Project-Specifics, "Model values read by
//! tests"; CL-014-16). A contract test names a value the model holds as data by its
//! qualified name `Package::Element(::Feature)*`, and this module finds it in the `.sysml`
//! text at run time. It reads only the subset of that section and fails on anything else;
//! the pinned Pilot of `tools/sysml.py check` validates the SysML itself.
//!
//! Test-only: the library registers it under `cfg(test)`, test modules of the station
//! executable and integration tests include it by `#[path]`. Its own tests are
//! `server/tests/model_values.rs`. The JavaScript reader `tests/model-values.cjs` gives the
//! same values and the same reasons.
use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

/// The enumeration that lists the unit suffixes.
const UNIT_SUFFIXES: &str = "WstxUnits::UnitSuffix";

/// Words that lead a declaration of a named element.
const KINDS: &str = "package library standard part attribute enum item port action state \
    requirement verification constraint calc interface connection metadata occurrence flow \
    view viewpoint use case analysis concern allocation rendering def actor stakeholder \
    subject objective exhibit perform snapshot timeslice event message";

/// Words that may stand before the kind of a declaration.
const MODIFIERS: &str = "private public protected abstract readonly derived constant ref in \
    out inout end variation individual nonunique ordered var composite portion";

fn listed(words: &str, word: &str) -> bool {
    words.split_whitespace().any(|w| w == word)
}

/// A read failure: the qualified name asked for and the reason.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error {
    pub name: String,
    pub reason: String,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.name, self.reason)
    }
}

impl std::error::Error for Error {}

fn error(name: &str, reason: impl Into<String>) -> Error {
    Error {
        name: name.to_string(),
        reason: reason.into(),
    }
}

/// A number literal.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Number {
    Integer(i64),
    Real(f64),
}

/// One literal of the read subset.
#[derive(Debug, Clone, PartialEq)]
pub enum Literal {
    Number(Number),
    String(String),
    Boolean(bool),
    Null,
    /// An enumeration value `Def::member`: the definition as written, and the member.
    Enum(String, String),
}

impl Literal {
    fn kind(&self) -> &'static str {
        match self {
            Literal::Number(_) => "a number",
            Literal::String(_) => "a string",
            Literal::Boolean(_) => "a Boolean",
            Literal::Null => "null",
            Literal::Enum(..) => "an enumeration value",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Word(String),
    /// A quoted name, with its quotes.
    Quoted(String),
    /// A string literal as written, with its quotes and escapes.
    Str(String),
    Num(String),
    Punct(String),
    /// A block comment; it ends a `doc` or `comment` statement.
    Comment,
}

impl Tok {
    fn is_punct(&self, p: &str) -> bool {
        matches!(self, Tok::Punct(q) if q == p)
    }
    fn is_word(&self, w: &str) -> bool {
        matches!(self, Tok::Word(q) if q == w)
    }
    fn name(&self) -> Option<&str> {
        match self {
            Tok::Word(w) | Tok::Quoted(w) => Some(w),
            _ => None,
        }
    }
}

fn tokens(text: &str) -> Vec<Tok> {
    let text = text.replace("\r\n", "\n");
    let chars: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    let at = |i: usize| chars.get(i).copied();
    while let Some(c) = at(i) {
        if c.is_whitespace() {
            i += 1;
        } else if c == '/' && at(i + 1) == Some('/') {
            while at(i).is_some_and(|c| c != '\n') {
                i += 1;
            }
        } else if c == '/' && at(i + 1) == Some('*') {
            i += 2;
            while at(i).is_some() && !(at(i) == Some('*') && at(i + 1) == Some('/')) {
                i += 1;
            }
            i = (i + 2).min(chars.len());
            out.push(Tok::Comment);
        } else if c == '"' || c == '\'' {
            let start = i;
            i += 1;
            while let Some(d) = at(i) {
                i += 1;
                if d == '\\' {
                    i += 1;
                } else if d == c {
                    break;
                }
            }
            let raw: String = chars[start..i.min(chars.len())].iter().collect();
            out.push(if c == '"' {
                Tok::Str(raw)
            } else {
                Tok::Quoted(raw)
            });
        } else if c.is_ascii_digit() {
            let start = i;
            let digits = |i: &mut usize| {
                while at(*i).is_some_and(|c| c.is_ascii_digit()) {
                    *i += 1;
                }
            };
            digits(&mut i);
            if at(i) == Some('.') && at(i + 1).is_some_and(|c| c.is_ascii_digit()) {
                i += 1;
                digits(&mut i);
            }
            if matches!(at(i), Some('e' | 'E')) {
                let sign = usize::from(matches!(at(i + 1), Some('+' | '-')));
                if at(i + 1 + sign).is_some_and(|c| c.is_ascii_digit()) {
                    i += 1 + sign;
                    digits(&mut i);
                }
            }
            out.push(Tok::Num(chars[start..i].iter().collect()));
        } else if c.is_ascii_alphabetic() || c == '_' {
            let start = i;
            while at(i).is_some_and(|c| c.is_ascii_alphanumeric() || c == '_') {
                i += 1;
            }
            out.push(Tok::Word(chars[start..i].iter().collect()));
        } else {
            let rest: String = chars[i..(i + 3).min(chars.len())].iter().collect();
            let punct = [
                ":>>", "::", ":>", ":=", "==", "!=", "<=", ">=", "..", "->", "=>",
            ]
            .into_iter()
            .find(|p| rest.starts_with(p))
            .map_or_else(|| c.to_string(), str::to_string);
            i += punct.chars().count();
            out.push(Tok::Punct(punct));
        }
    }
    out
}

/// One statement of a body: its leading tokens (comments left out), and the token range of
/// its own body.
struct Stmt {
    head: Vec<Tok>,
    body: Option<(usize, usize)>,
    doc: bool,
}

/// The statements of the body `toks[start..end]`.
fn statements(toks: &[Tok], start: usize, end: usize) -> Vec<Stmt> {
    let mut out = Vec::new();
    let mut i = start;
    while i < end {
        if toks[i] == Tok::Comment || toks[i].is_punct(";") {
            i += 1;
            continue;
        }
        if toks[i].is_word("doc") || toks[i].is_word("comment") {
            let mut head = Vec::new();
            while i < end && toks[i] != Tok::Comment && !toks[i].is_punct(";") {
                head.push(toks[i].clone());
                i += 1;
            }
            i += 1;
            out.push(Stmt {
                head,
                body: None,
                doc: true,
            });
            continue;
        }
        let mut head = Vec::new();
        let mut body = None;
        let mut depth = 0usize;
        while i < end {
            let t = &toks[i];
            if *t == Tok::Comment {
                i += 1;
            } else if t.is_punct(";") && depth == 0 {
                i += 1;
                break;
            } else if t.is_punct("{") {
                let open = i;
                let mut braces = 0usize;
                while i < end {
                    if toks[i].is_punct("{") {
                        braces += 1;
                    } else if toks[i].is_punct("}") {
                        braces -= 1;
                        if braces == 0 {
                            break;
                        }
                    }
                    i += 1;
                }
                body = Some((open + 1, i.min(end)));
                i += 1;
                break;
            } else if t.is_punct("}") {
                i += 1;
                break;
            } else {
                if t.is_punct("(") || t.is_punct("[") {
                    depth += 1;
                } else if t.is_punct(")") || t.is_punct("]") {
                    depth = depth.saturating_sub(1);
                }
                head.push(t.clone());
                i += 1;
            }
        }
        if !head.is_empty() || body.is_some() {
            out.push(Stmt {
                head,
                body,
                doc: false,
            });
        }
    }
    out
}

/// What a statement declares: its kind words, its name, whether it is a redefinition, and
/// the index of the head after the name.
struct Decl {
    kinds: Vec<String>,
    name: Option<String>,
    redefinition: bool,
    rest: usize,
}

fn declaration(stmt: &Stmt) -> Decl {
    let head = &stmt.head;
    let mut decl = Decl {
        kinds: Vec::new(),
        name: None,
        redefinition: false,
        rest: head.len(),
    };
    if stmt.doc {
        return decl;
    }
    let mut i = 0;
    loop {
        match head.get(i) {
            Some(Tok::Word(w)) if listed(MODIFIERS, w) => i += 1,
            Some(t) if t.is_punct("#") => {
                i += 2;
                while head.get(i).is_some_and(|t| t.is_punct("::")) {
                    i += 2;
                }
            }
            _ => break,
        }
    }
    while let Some(Tok::Word(w)) = head.get(i) {
        if !listed(KINDS, w) {
            break;
        }
        decl.kinds.push(w.clone());
        i += 1;
    }
    if decl.kinds.is_empty() {
        return decl;
    }
    if head.get(i).is_some_and(|t| t.is_punct("<")) {
        while head.get(i).is_some_and(|t| !t.is_punct(">")) {
            i += 1;
        }
        i += 1;
    }
    let redefinition = head
        .get(i)
        .is_some_and(|t| t.is_punct(":>>") || t.is_word("redefines"));
    if redefinition {
        i += 1;
    }
    if let Some(name) = head.get(i).and_then(Tok::name)
        && !head.get(i + 1).is_some_and(|t| t.is_punct("::"))
    {
        decl.name = Some(name.to_string());
        decl.redefinition = redefinition;
        decl.rest = i + 1;
    }
    decl
}

fn is_attribute(decl: &Decl) -> bool {
    decl.kinds.len() == 1 && decl.kinds[0] == "attribute" && decl.name.is_some()
}

/// A qualified name `a::b::c` read from `head[i..]`; returns it and the index after it.
fn qualified(head: &[Tok], mut i: usize) -> Option<(String, usize)> {
    let mut name = head.get(i)?.name()?.to_string();
    i += 1;
    while head.get(i).is_some_and(|t| t.is_punct("::")) {
        name.push_str("::");
        name.push_str(head.get(i + 1)?.name()?);
        i += 2;
    }
    Some((name, i))
}

/// The type of an attribute declaration (`: Type`), if it states one, and the index after
/// its type and multiplicity.
fn declared_type(head: &[Tok], rest: usize) -> (Option<String>, usize) {
    let mut i = rest;
    let mut ty = None;
    if head.get(i).is_some_and(|t| t.is_punct(":"))
        && let Some((name, next)) = qualified(head, i + 1)
    {
        ty = Some(name);
        i = next;
    }
    if head.get(i).is_some_and(|t| t.is_punct("[")) {
        while head.get(i).is_some_and(|t| !t.is_punct("]")) {
            i += 1;
        }
        i += 1;
    }
    (ty, i)
}

/// The value of an attribute declaration: `= <literal>` after its name and type.
fn attribute_value(stmt: &Stmt, decl: &Decl) -> Result<Literal, String> {
    if !is_attribute(decl) {
        return Err("not an attribute value".into());
    }
    let (_, i) = declared_type(&stmt.head, decl.rest);
    match stmt.head.get(i) {
        None => Err("value missing".into()),
        Some(t) if t.is_punct("=") => literal(&stmt.head[i + 1..]),
        Some(_) => Err("not one literal: the declaration is not in the read form".into()),
    }
}

fn literal(toks: &[Tok]) -> Result<Literal, String> {
    let number = |sign: &str, raw: &str| -> Result<Literal, String> {
        let text = format!("{sign}{raw}");
        if raw.bytes().all(|b| b.is_ascii_digit()) {
            text.parse::<i64>()
                .map(|n| Literal::Number(Number::Integer(n)))
                .map_err(|_| "not one literal: an integer out of range".to_string())
        } else {
            text.parse::<f64>()
                .map(|n| Literal::Number(Number::Real(n)))
                .map_err(|_| "not one literal: a malformed number".to_string())
        }
    };
    match toks {
        [] => return Err("value missing".into()),
        [Tok::Str(raw)] => {
            return serde_json::from_str::<String>(raw)
                .map(Literal::String)
                .map_err(|_| "not one literal: an unreadable string".into());
        }
        [Tok::Num(raw)] => return number("", raw),
        [Tok::Punct(sign), Tok::Num(raw)] if sign == "-" || sign == "+" => {
            return number(sign, raw);
        }
        [Tok::Word(w)] if w == "true" || w == "false" => return Ok(Literal::Boolean(w == "true")),
        [Tok::Word(w)] if w == "null" => return Ok(Literal::Null),
        _ => {}
    }
    if let Some((name, end)) = qualified(toks, 0)
        && end == toks.len()
        && let Some((def, member)) = name.rsplit_once("::")
    {
        return Ok(Literal::Enum(def.to_string(), member.to_string()));
    }
    let shape =
        if toks.iter().any(|t| t.is_punct("+")) && toks.iter().any(|t| matches!(t, Tok::Str(_))) {
            "a + join"
        } else if toks[0].is_punct("(") {
            "a list"
        } else if toks.iter().any(|t| t.is_punct("[")) {
            "a unit expression"
        } else {
            "an expression"
        };
    Err(format!("not one literal: {shape}"))
}

/// Splits a qualified name at `::` outside quoted names.
fn segments(name: &str) -> Vec<String> {
    let mut out = vec![String::new()];
    let mut quoted = false;
    let mut chars = name.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\'' {
            quoted = !quoted;
        } else if c == ':' && !quoted && chars.peek() == Some(&':') {
            chars.next();
            out.push(String::new());
            continue;
        }
        if let Some(last) = out.last_mut() {
            last.push(c);
        }
    }
    out
}

/// Whether `name` ends in `suffix`: its last characters are the suffix and the character
/// before them is a lowercase letter or a digit.
fn ends_in(name: &str, suffix: &str) -> bool {
    name.strip_suffix(suffix)
        .and_then(|rest| rest.chars().last())
        .is_some_and(|c| c.is_ascii_lowercase() || c.is_ascii_digit())
}

struct File {
    key: String,
    text: String,
    toks: Vec<Tok>,
    /// The file's package and the token range of its body.
    package: Option<(String, usize, usize)>,
}

impl File {
    fn new(key: String, text: String) -> File {
        let toks = tokens(&text);
        let package = (0..toks.len()).find_map(|i| {
            if !toks[i].is_word("package") {
                return None;
            }
            let Some(Tok::Word(name)) = toks.get(i + 1) else {
                return None;
            };
            let open = (i + 2..toks.len()).find(|&j| toks[j] != Tok::Comment)?;
            if !toks[open].is_punct("{") {
                return None;
            }
            let mut braces = 0usize;
            let mut j = open;
            while j < toks.len() {
                if toks[j].is_punct("{") {
                    braces += 1;
                } else if toks[j].is_punct("}") {
                    braces -= 1;
                    if braces == 0 {
                        break;
                    }
                }
                j += 1;
            }
            Some((name.clone(), open + 1, j))
        });
        File {
            key,
            text,
            toks,
            package,
        }
    }
}

/// The model files of one folder, read at run time.
pub struct Model {
    files: Result<Vec<File>, String>,
    suffixes: OnceLock<Result<Vec<String>, String>>,
}

/// The attribute usages of one table: a named body's usages typed by one definition.
pub struct Usage<'m> {
    model: &'m Model,
    /// The usage's qualified name.
    pub qualified: String,
    pub name: String,
    fields: Vec<(String, Result<Literal, String>)>,
}

/// The model folder `docs/sysml` of this checkout.
pub fn model_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../docs/sysml")
}

fn model_files(dir: &Path) -> Result<Vec<File>, String> {
    if !dir.is_dir() {
        return Err(format!("model folder missing: {}", dir.display()));
    }
    fn walk(dir: &Path, base: &Path, out: &mut Vec<(String, PathBuf)>) -> Result<(), String> {
        let entries = std::fs::read_dir(dir)
            .map_err(|e| format!("model folder unreadable: {}: {e}", dir.display()))?;
        for entry in entries {
            let path = entry
                .map_err(|e| format!("model folder unreadable: {}: {e}", dir.display()))?
                .path();
            if path.is_dir() {
                walk(&path, base, out)?;
            } else if path.is_file() && path.extension().is_some_and(|e| e == "sysml") {
                let key = path
                    .strip_prefix(base)
                    .unwrap_or(&path)
                    .components()
                    .map(|c| c.as_os_str().to_string_lossy().into_owned())
                    .collect::<Vec<_>>()
                    .join("/");
                out.push((key, path));
            }
        }
        Ok(())
    }
    let mut found = Vec::new();
    walk(dir, dir, &mut found)?;
    if found.is_empty() {
        return Err(format!(
            "model folder holds no model file: {}",
            dir.display()
        ));
    }
    found.sort();
    found
        .into_iter()
        .map(|(key, path)| {
            let bytes =
                std::fs::read(&path).map_err(|e| format!("model file unreadable: {key}: {e}"))?;
            let text =
                String::from_utf8(bytes).map_err(|_| format!("model file not UTF-8: {key}"))?;
            Ok(File::new(key, text))
        })
        .collect()
}

impl Model {
    /// The model of this checkout.
    pub fn load() -> Model {
        Model::at(model_dir())
    }

    /// The model files below `dir`. A folder that cannot be read fails every read.
    pub fn at(dir: impl AsRef<Path>) -> Model {
        Model {
            files: model_files(dir.as_ref()),
            suffixes: OnceLock::new(),
        }
    }

    fn files(&self, name: &str) -> Result<&[File], Error> {
        self.files.as_deref().map_err(|reason| error(name, reason))
    }

    fn package_file(&self, package: &str, name: &str) -> Result<&File, Error> {
        let holding: Vec<&File> = self
            .files(name)?
            .iter()
            .filter(|f| f.package.as_ref().is_some_and(|p| p.0 == package))
            .collect();
        match holding.as_slice() {
            [] => Err(error(
                name,
                format!("no model file has the package {package}"),
            )),
            [file] => Ok(file),
            more => Err(error(
                name,
                format!(
                    "more than one model file has the package {package}: {}",
                    more.iter()
                        .map(|f| f.key.as_str())
                        .collect::<Vec<_>>()
                        .join(", ")
                ),
            )),
        }
    }

    /// The text of the model file whose package is `package`.
    pub fn package_text(&self, package: &str) -> Result<&str, Error> {
        Ok(&self.package_file(package, package)?.text)
    }

    /// This model with the file of `package` replaced by `text` (a damaged copy).
    pub fn with_package_text(&self, package: &str, text: &str) -> Result<Model, Error> {
        let key = self.package_file(package, package)?.key.clone();
        let files = self
            .files(package)?
            .iter()
            .map(|f| {
                let text = if f.key == key { text } else { &f.text };
                File::new(f.key.clone(), text.to_string())
            })
            .collect();
        Ok(Model {
            files: Ok(files),
            suffixes: OnceLock::new(),
        })
    }

    /// The statement a qualified name declares, with the tokens of its file.
    fn resolve(&self, name: &str) -> Result<(&[Tok], Stmt), Error> {
        let parts = segments(name);
        if parts.len() < 2 || parts.iter().any(String::is_empty) {
            return Err(error(name, "not a qualified name Package::Element"));
        }
        let file = self.package_file(&parts[0], name)?;
        let Some((_, mut start, mut end)) = file.package else {
            return Err(error(name, "no model file has the package"));
        };
        for (k, part) in parts.iter().enumerate().skip(1) {
            let mut found: Vec<Stmt> = statements(&file.toks, start, end)
                .into_iter()
                .filter(|s| declaration(s).name.as_deref() == Some(part.as_str()))
                .collect();
            if found.len() > 1 {
                return Err(error(
                    name,
                    format!("declared twice in one body: {}", parts[..=k].join("::")),
                ));
            }
            let Some(stmt) = found.pop() else {
                return Err(error(
                    name,
                    format!("not declared: {}", parts[..=k].join("::")),
                ));
            };
            if k + 1 == parts.len() {
                return Ok((&file.toks, stmt));
            }
            match stmt.body {
                Some((s, e)) => (start, end) = (s, e),
                None => {
                    return Err(error(
                        name,
                        format!("not declared: {}", parts[..=k + 1].join("::")),
                    ));
                }
            }
        }
        Err(error(name, "not a qualified name Package::Element"))
    }

    /// The body range of a package or a named element.
    fn body(&self, name: &str) -> Result<(&[Tok], usize, usize), Error> {
        if segments(name).len() == 1 {
            let file = self.package_file(name, name)?;
            let (_, s, e) = file
                .package
                .clone()
                .ok_or_else(|| error(name, "no model file has the package"))?;
            return Ok((&file.toks, s, e));
        }
        let (toks, stmt) = self.resolve(name)?;
        Ok(match stmt.body {
            Some((s, e)) => (toks, s, e),
            None => (toks, 0, 0),
        })
    }

    /// The literal value of an attribute.
    pub fn literal(&self, name: &str) -> Result<Literal, Error> {
        let (_, stmt) = self.resolve(name)?;
        attribute_value(&stmt, &declaration(&stmt)).map_err(|reason| error(name, reason))
    }

    pub fn string(&self, name: &str) -> Result<String, Error> {
        as_string(name, self.literal(name)?)
    }

    pub fn boolean(&self, name: &str) -> Result<bool, Error> {
        as_boolean(name, self.literal(name)?)
    }

    /// An enumeration value: the definition as written, and the member.
    pub fn enum_value(&self, name: &str) -> Result<(String, String), Error> {
        as_enum(name, self.literal(name)?)
    }

    /// A number without a unit; `None` for `null`.
    pub fn number(&self, name: &str) -> Result<Option<Number>, Error> {
        self.as_number(name, self.literal(name)?, false)
    }

    /// A number with its unit, named by its last segment; `None` for `null`.
    pub fn number_with_unit(&self, name: &str) -> Result<Option<Number>, Error> {
        self.as_number(name, self.literal(name)?, true)
    }

    /// The members of an `enum def`, in declaration order.
    pub fn enum_members(&self, name: &str) -> Result<Vec<String>, Error> {
        let (toks, stmt) = self.resolve(name)?;
        let decl = declaration(&stmt);
        if decl.kinds != ["enum", "def"] {
            return Err(error(name, "not an enumeration definition"));
        }
        let Some((start, end)) = stmt.body else {
            return Ok(Vec::new());
        };
        let mut members = Vec::new();
        for member in statements(toks, start, end) {
            if member.doc {
                continue;
            }
            let short = match member.head.as_slice() {
                [t] => t.name(),
                [k, t] if k.is_word("enum") => t.name(),
                _ => None,
            };
            let doc_only = member
                .body
                .is_none_or(|(s, e)| statements(toks, s, e).iter().all(|m| m.doc));
            match short {
                Some(member_name) if doc_only => members.push(member_name.to_string()),
                _ => return Err(error(name, "not an enumeration member in the read form")),
            }
        }
        Ok(members)
    }

    /// The attribute usages declared directly in `container` (a package or a named
    /// element) and typed by `definition` (its qualified name; a usage may name it short or
    /// qualified), in declaration order.
    pub fn table(&self, container: &str, definition: &str) -> Result<Vec<Usage<'_>>, Error> {
        let (toks, start, end) = self.body(container)?;
        let mut usages = Vec::new();
        for stmt in statements(toks, start, end) {
            let decl = declaration(&stmt);
            if !is_attribute(&decl) || decl.redefinition {
                continue;
            }
            let (Some(ty), _) = declared_type(&stmt.head, decl.rest) else {
                continue;
            };
            if ty != definition && !definition.ends_with(&format!("::{ty}")) {
                continue;
            }
            let name = decl.name.unwrap_or_default();
            let fields = match stmt.body {
                Some((s, e)) => statements(toks, s, e)
                    .into_iter()
                    .filter_map(|field| {
                        let d = declaration(&field);
                        is_attribute(&d).then(|| {
                            let value = attribute_value(&field, &d);
                            (d.name.unwrap_or_default(), value)
                        })
                    })
                    .collect(),
                None => Vec::new(),
            };
            usages.push(Usage {
                model: self,
                qualified: format!("{container}::{name}"),
                name,
                fields,
            });
        }
        if usages.is_empty() {
            return Err(error(
                container,
                format!("table has no usage of {definition}"),
            ));
        }
        Ok(usages)
    }

    fn suffixes(&self) -> Result<&[String], String> {
        self.suffixes
            .get_or_init(|| match self.enum_members(UNIT_SUFFIXES) {
                Ok(members) if members.is_empty() => {
                    Err(format!("unit suffixes: {UNIT_SUFFIXES} has no member"))
                }
                Ok(members) => Ok(members),
                Err(e) => Err(format!("unit suffixes: {UNIT_SUFFIXES}: {}", e.reason)),
            })
            .as_deref()
            .map_err(Clone::clone)
    }

    fn as_number(
        &self,
        name: &str,
        value: Literal,
        with_unit: bool,
    ) -> Result<Option<Number>, Error> {
        let number = match value {
            Literal::Null => None,
            Literal::Number(n) => Some(n),
            other => {
                return Err(error(
                    name,
                    format!("value is {}, not a number", other.kind()),
                ));
            }
        };
        let last = segments(name).pop().unwrap_or_default();
        let suffixes = self.suffixes().map_err(|reason| error(name, reason))?;
        let has_unit = suffixes.iter().any(|s| ends_in(&last, s));
        if with_unit && !has_unit {
            return Err(error(name, "unit suffix not on the list"));
        }
        if !with_unit && has_unit {
            return Err(error(name, "value has a unit; read it with its unit"));
        }
        Ok(number)
    }
}

fn as_string(name: &str, value: Literal) -> Result<String, Error> {
    match value {
        Literal::String(s) => Ok(s),
        other => Err(error(
            name,
            format!("value is {}, not a string", other.kind()),
        )),
    }
}

fn as_boolean(name: &str, value: Literal) -> Result<bool, Error> {
    match value {
        Literal::Boolean(b) => Ok(b),
        other => Err(error(
            name,
            format!("value is {}, not a Boolean", other.kind()),
        )),
    }
}

fn as_enum(name: &str, value: Literal) -> Result<(String, String), Error> {
    match value {
        Literal::Enum(def, member) => Ok((def, member)),
        other => Err(error(
            name,
            format!("value is {}, not an enumeration value", other.kind()),
        )),
    }
}

impl Usage<'_> {
    /// The names of the attributes the usage's own body declares, in order.
    pub fn field_names(&self) -> Vec<&str> {
        self.fields.iter().map(|(n, _)| n.as_str()).collect()
    }

    pub fn literal(&self, field: &str) -> Result<Literal, Error> {
        let name = format!("{}::{field}", self.qualified);
        let mut found = self.fields.iter().filter(|(n, _)| n == field);
        let (Some((_, value)), None) = (found.next(), found.next()) else {
            let count = self.fields.iter().filter(|(n, _)| n == field).count();
            let reason = if count == 0 {
                format!("not declared: {name}")
            } else {
                format!("declared twice in one body: {name}")
            };
            return Err(error(&name, reason));
        };
        value.clone().map_err(|reason| error(&name, reason))
    }

    pub fn string(&self, field: &str) -> Result<String, Error> {
        as_string(
            &format!("{}::{field}", self.qualified),
            self.literal(field)?,
        )
    }

    pub fn boolean(&self, field: &str) -> Result<bool, Error> {
        as_boolean(
            &format!("{}::{field}", self.qualified),
            self.literal(field)?,
        )
    }

    pub fn enum_value(&self, field: &str) -> Result<(String, String), Error> {
        as_enum(
            &format!("{}::{field}", self.qualified),
            self.literal(field)?,
        )
    }

    pub fn number(&self, field: &str) -> Result<Option<Number>, Error> {
        let name = format!("{}::{field}", self.qualified);
        self.model.as_number(&name, self.literal(field)?, false)
    }

    pub fn number_with_unit(&self, field: &str) -> Result<Option<Number>, Error> {
        let name = format!("{}::{field}", self.qualified);
        self.model.as_number(&name, self.literal(field)?, true)
    }
}

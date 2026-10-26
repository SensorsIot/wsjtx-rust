#![forbid(unsafe_code)]
use super::{Error, Operation, Result};
use serde::Deserialize;
use std::collections::HashSet;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Document {
    schema_version: u8,
    revision: String,
    models: Vec<Model>,
    commands: Vec<Command>,
    sources: Vec<Source>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Model {
    id: String,
    protocol: String,
    hamlib_model: u32,
    commands: Vec<String>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Command {
    id: String,
    request_prefix: Vec<u8>,
    unit: String,
    minimum: u64,
    maximum: u64,
    sources: Vec<String>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Source {
    id: String,
    publisher: String,
    url: String,
    revision: String,
    licence: String,
}

pub struct Catalogue {
    revision: String,
    supported: HashSet<String>,
}
impl Catalogue {
    pub fn builtin() -> Result<Self> {
        Self::parse(include_bytes!(
            "../../../fixtures/radio/ic7300-catalogue.json"
        ))
    }
    pub fn parse(bytes: &[u8]) -> Result<Self> {
        if bytes.len() > 262_144 {
            return Err(Error::InvalidConfiguration);
        }
        let doc: Document =
            serde_json::from_slice(bytes).map_err(|_| Error::InvalidConfiguration)?;
        let bounded = |s: &str| !s.is_empty() && s.len() <= 256 && !s.chars().any(char::is_control);
        if doc.schema_version != 1
            || !bounded(&doc.revision)
            || doc.models.is_empty()
            || doc.models.len() > 32
            || doc.commands.len() > 128
            || doc.sources.is_empty()
            || doc.sources.len() > 128
        {
            return Err(Error::InvalidConfiguration);
        }
        let mut sources = HashSet::new();
        for s in &doc.sources {
            if ![&s.id, &s.publisher, &s.url, &s.revision, &s.licence]
                .iter()
                .all(|s| bounded(s))
                || !s.url.starts_with("https://")
                || !sources.insert(&s.id)
            {
                return Err(Error::InvalidConfiguration);
            }
        }
        let mut commands = HashSet::new();
        for command in &doc.commands {
            if !bounded(&command.id)
                || !bounded(&command.unit)
                || command.minimum > command.maximum
                || command.request_prefix.is_empty()
                || command.request_prefix.len() > 2
                || command.sources.is_empty()
                || command.sources.len() > 16
                || !command.sources.iter().all(|id| sources.contains(id))
                || !commands.insert(&command.id)
            {
                return Err(Error::InvalidConfiguration);
            }
            if let Some((expected, unit, min, max)) = compiled(&command.id)
                && (command.request_prefix != expected
                    || command.unit != unit
                    || command.minimum != min
                    || command.maximum != max)
            {
                return Err(Error::InvalidConfiguration);
            }
        }
        let mut ids = HashSet::new();
        let mut supported = HashSet::new();
        for model in &doc.models {
            let unique: HashSet<_> = model.commands.iter().collect();
            if !bounded(&model.id)
                || !bounded(&model.protocol)
                || !ids.insert(&model.id)
                || unique.len() != model.commands.len()
                || model.commands.len() > 128
                || !model.commands.iter().all(|id| commands.contains(id))
            {
                return Err(Error::InvalidConfiguration);
            }
            if model.id == "icom.ic7300" {
                if model.protocol != "icom.civ" || model.hamlib_model != 3073 {
                    return Err(Error::InvalidConfiguration);
                }
                supported.extend(
                    model
                        .commands
                        .iter()
                        .filter(|id| compiled(id).is_some())
                        .cloned(),
                );
            }
        }
        Ok(Self {
            revision: doc.revision,
            supported,
        })
    }
    pub fn revision(&self) -> &str {
        &self.revision
    }
    pub fn supports(&self, operation: &Operation) -> bool {
        if matches!(operation, Operation::ReceiveSetup { .. }) {
            [
                "set_frequency",
                "set_mode",
                "set_data",
                "read_frequency",
                "read_mode",
                "read_data",
            ]
            .iter()
            .all(|key| self.supported.contains(*key))
        } else {
            self.supported.contains(operation.key())
        }
    }
}
fn compiled(key: &str) -> Option<(Vec<u8>, &'static str, u64, u64)> {
    Some(match key {
        "read_frequency" => (vec![3], "Hz", 30000, 74800000),
        "set_frequency" => (vec![5], "Hz", 30000, 74800000),
        "read_mode" => (vec![4], "mode", 0, 255),
        "set_mode" => (vec![6], "mode", 0, 1),
        "read_data" | "set_data" => (vec![0x1a, 6], "boolean", 0, 1),
        "read_rx_tx" => (vec![0x1c, 0], "boolean", 0, 1),
        "read_split" => (vec![0x0f], "boolean", 0, 1),
        _ => return None,
    })
}

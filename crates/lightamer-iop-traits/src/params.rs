// SPDX-License-Identifier: GPL-3.0-or-later
//! Typed parameter readers for module authors.
//!
//! Instance parameters arrive as a JSON object whose values are the tagged
//! shapes the history model writes (`{"type": "float", "value": 0.5}`).
//! These helpers read one type each; a missing name or a wrong shape is
//! [`PipeError::InvalidParams`].

use serde_json::{Map, Value};

use super::PipeError;

/// Reads parameter `name` as a float.
/// # Errors
///
/// [`PipeError::InvalidParams`] when `name` is absent or not
/// `{"type": "float", "value": <number>}`.
pub fn get_float(params: &Map<String, Value>, name: &str) -> Result<f64, PipeError> {
    match tagged(params, name, "float")? {
        Value::Number(number) => number
            .as_f64()
            .ok_or_else(|| mistyped(name, "float", "number")),
        other => Err(mistyped(name, "float", &kind_of(other))),
    }
}

/// Reads parameter `name` as an integer.
///
/// # Errors
///
/// [`PipeError::InvalidParams`] when `name` is absent or not
/// `{"type": "int", "value": <integer>}`.
pub fn get_int(params: &Map<String, Value>, name: &str) -> Result<i64, PipeError> {
    match tagged(params, name, "int")? {
        Value::Number(number) => number
            .as_i64()
            .ok_or_else(|| mistyped(name, "int", "number")),
        other => Err(mistyped(name, "int", &kind_of(other))),
    }
}

/// Reads parameter `name` as a switch.
///
/// # Errors
///
/// [`PipeError::InvalidParams`] when `name` is absent or not
/// `{"type": "bool", "value": <bool>}`.
pub fn get_bool(params: &Map<String, Value>, name: &str) -> Result<bool, PipeError> {
    match tagged(params, name, "bool")? {
        Value::Bool(value) => Ok(*value),
        other => Err(mistyped(name, "bool", &kind_of(other))),
    }
}

/// Reads parameter `name` as text.
///
/// # Errors
///
/// [`PipeError::InvalidParams`] when `name` is absent or not
/// `{"type": "text", "value": <string>}`.
pub fn get_text<'a>(params: &'a Map<String, Value>, name: &str) -> Result<&'a str, PipeError> {
    match tagged(params, name, "text")? {
        Value::String(value) => Ok(value.as_str()),
        other => Err(mistyped(name, "text", &kind_of(other))),
    }
}

/// Reads parameter `name` as a float list.
///
/// # Errors
///
/// [`PipeError::InvalidParams`] when `name` is absent, not
/// `{"type": "floats", "value": [...]}`,
/// or any element is not a number.
pub fn get_floats(params: &Map<String, Value>, name: &str) -> Result<Vec<f64>, PipeError> {
    match tagged(params, name, "floats")? {
        Value::Array(items) => {
            let mut out = Vec::with_capacity(items.len());
            for item in items {
                match item {
                    Value::Number(number) => {
                        if let Some(value) = number.as_f64() {
                            out.push(value);
                        } else {
                            return Err(mistyped(name, "floats", "number"));
                        }
                    }
                    other => return Err(mistyped(name, "floats", &kind_of(other))),
                }
            }
            Ok(out)
        }
        other => Err(mistyped(name, "floats", &kind_of(other))),
    }
}

/// The `value` payload of `{"type": <tag>, "value": ...}` at `name`.
fn tagged<'a>(
    params: &'a Map<String, Value>,
    name: &str,
    tag: &str,
) -> Result<&'a Value, PipeError> {
    let found = params
        .get(name)
        .ok_or_else(|| PipeError::InvalidParams(missing(name)))?;
    let obj = found
        .as_object()
        .ok_or_else(|| mistyped(name, tag, &kind_of(found)))?;
    let actual = obj.get("type").and_then(Value::as_str).unwrap_or("?");
    if actual != tag {
        return Err(mistyped(name, tag, actual));
    }
    obj.get("value")
        .ok_or_else(|| PipeError::InvalidParams(missing(name)))
}

fn missing(name: &str) -> String {
    format!("missing parameter '{name}'")
}

fn mistyped(name: &str, want: &str, found: &str) -> PipeError {
    PipeError::InvalidParams(format!("parameter '{name}' expects {want}, found {found}"))
}

fn kind_of(value: &Value) -> String {
    if value.is_null() {
        return "null".to_owned();
    }
    if value.as_object().is_some() {
        return value
            .get("type")
            .and_then(Value::as_str)
            .unwrap_or("object")
            .to_owned();
    }
    match value {
        Value::Bool(_) => "bool",
        Value::Number(_) => "number",
        Value::String(_) => "string",
        Value::Array(_) => "array",
        Value::Object(_) | Value::Null => "value",
    }
    .to_owned()
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use serde_json::{Map, Value};

    use super::{get_bool, get_float, get_floats, get_int, get_text};
    use crate::PipeError;

    fn params() -> Map<String, Value> {
        serde_json::from_str(
            r#"{
                "p_float": {"type": "float", "value": 0.5},
                "p_int": {"type": "int", "value": 3},
                "p_bool": {"type": "bool", "value": true},
                "p_text": {"type": "text", "value": "hello"},
                "p_floats": {"type": "floats", "value": [0.0, 1.5, -2.0]}
            }"#,
        )
        .unwrap()
    }

    #[test]
    fn all_five_kinds_read_cleanly() {
        let params = params();
        assert_eq!(get_float(&params, "p_float").unwrap(), 0.5);
        assert_eq!(get_int(&params, "p_int").unwrap(), 3);
        assert!(get_bool(&params, "p_bool").unwrap());
        assert_eq!(get_text(&params, "p_text").unwrap(), "hello");
        assert_eq!(
            get_floats(&params, "p_floats").unwrap(),
            vec![0.0, 1.5, -2.0]
        );
    }

    #[test]
    fn missing_names_and_wrong_tags_are_invalid_params() {
        let params = params();
        let err = get_float(&params, "nope").unwrap_err();
        assert_eq!(
            err,
            PipeError::InvalidParams("missing parameter 'nope'".to_owned())
        );
        // Right name, wrong tag: float reader on an int cell.
        let err = get_float(&params, "p_int").unwrap_err();
        assert!(err.to_string().contains("expects float, found int"));
        // Right tag family, wrong payload: array where a number belongs.
        let err = get_float(&params, "p_floats").unwrap_err();
        assert!(err.to_string().contains("expects float, found floats"));
        // Non-object cell.
        let mut raw: Map<String, Value> = Map::new();
        raw.insert("p_bare".to_owned(), Value::from(1.0));
        let err = get_float(&raw, "p_bare").unwrap_err();
        assert!(err.to_string().contains("expects float, found number"));
        // Float list with a bad element.
        let mut bad: Map<String, Value> = Map::new();
        bad.insert(
            "p_mixed".to_owned(),
            serde_json::json!({"type": "floats", "value": [1.0, "x"]}),
        );
        assert!(get_floats(&bad, "p_mixed").is_err());
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from lightcraft crates/develop/src/settings.rs (`ProcessVersion`,
// commit 0da998f2) and crates/develop/src/lib.rs (`hash64`) — reworked:
// untyped per-module maps instead of one fixed struct, our own process line
// starting at V1, canonical JSON kept explicit, unknown modules kept.
//! Photo settings: lenient pure data with a process version.
//!
//! A [`PhotoSettings`] is the complete look of one photo: a [`ProcessVersion`]
//! plus an ordered map of module instances. It is plain [`serde`] data with
//! three load rules (mirroring `LightCraft`, see `docs/process-versions.md`
//! there): unknown fields are ignored, missing fields take defaults, and a
//! missing or damaged process reads as V1.
//!
//! One deliberate difference from `LightCraft`: unknown module ids and unknown
//! parameter names are **kept**, not dropped. Our modules self-register, so an
//! id this build does not know may simply not be compiled in; dropping it
//! would lose the user's edits when the module comes back.

use std::collections::BTreeMap;

use dt_iop_traits::{ParamType, ParamsDesc};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// Wire format version of [`PhotoSettings`].
///
/// Always serialized. A newer number from a future writer loads, is kept as
/// is, and is written back unchanged; unknown fields around it are ignored.
pub const FORMAT_VERSION: u32 = 1;

fn default_format_version() -> u32 {
    FORMAT_VERSION
}

/// A rendering process a photo's settings are interpreted by.
///
/// Rule (`LightCraft`'s, see its `docs/process-versions.md`): a change that
/// would alter how existing settings render ships as a new process, so a
/// photo keeps its look until someone explicitly updates it. Only V1 exists;
/// V1 is therefore also [`ProcessVersion::LATEST`].
///
/// Reading is lenient: a missing field — or anything but a whole number from
/// 0 to 2^32 - 1 (`2.0` counts as 2) — reads as V1, like settings saved before
/// process versions existed. A number this build does not know loads, is kept
/// on save, and is never downgraded; only
/// [`ProcessVersion::update_to_latest`] moves a photo, and never backwards.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize)]
#[serde(transparent)]
pub struct ProcessVersion(pub u32);

impl<'de> Deserialize<'de> for ProcessVersion {
    #[allow(
        clippy::cast_possible_truncation,
        clippy::cast_sign_loss,
        clippy::float_cmp
    )]
    // The float arm only casts after proving the value whole and inside the
    // `u32` range, so the cast is exact; the equality is the intended
    // whole-number check, not an approximation.
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum Wire {
            Whole(u64),
            Number(f64),
            Other(serde::de::IgnoredAny),
        }
        Ok(match Wire::deserialize(d)? {
            Wire::Whole(n) => {
                u32::try_from(n).map_or_else(|_| ProcessVersion::legacy(), ProcessVersion)
            }
            Wire::Number(x) if x.fract() == 0.0 && (0.0..=f64::from(u32::MAX)).contains(&x) => {
                ProcessVersion(x as u32)
            }
            Wire::Number(_) | Wire::Other(_) => ProcessVersion::legacy(),
        })
    }
}

impl ProcessVersion {
    /// The first process: our rendering from before any process change. Frozen.
    pub const V1: ProcessVersion = ProcessVersion(1);
    /// The process new photos and Reset get.
    pub const LATEST: ProcessVersion = ProcessVersion::V1;

    /// The process of settings saved without one: V1, whatever [`Self::LATEST`]
    /// becomes. This is the field-level default, not the struct's `Default`.
    #[must_use]
    pub fn legacy() -> ProcessVersion {
        ProcessVersion::V1
    }

    /// Whether this build implements this process (today: V1 only).
    #[must_use]
    pub fn is_known(self) -> bool {
        self == ProcessVersion::V1
    }

    /// Older than [`Self::LATEST`]: an explicit update applies. A number newer
    /// than this build knows is not outdated — it stays untouched.
    #[must_use]
    pub fn is_outdated(self) -> bool {
        self < ProcessVersion::LATEST
    }

    /// The explicit "update to current process": moves an older photo to
    /// [`Self::LATEST`], keeps anything newer than this build knows.
    pub fn update_to_latest(&mut self) {
        if self.is_outdated() {
            *self = ProcessVersion::LATEST;
        }
    }
}

/// One parameter value: typed on the wire so unknown parameters survive.
///
/// The kinds line up with [`ParamType`]: `Bool`/`Int`/`Float`/`Enum` match by
/// name, [`SettingValue::Floats`] carries a [`ParamType::Curve`] (curve and
/// control-point payloads are plain float lists). [`SettingValue::Text`] has
/// no [`ParamType`] counterpart today, so a declared field can never hold one
/// (see [`ModuleInstance::validate`]); free strings round-trip as undeclared
/// parameters until a later wave extends the description vocabulary.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "snake_case")]
pub enum SettingValue {
    /// On/off switch.
    Bool(bool),
    /// Integer number.
    Int(i64),
    /// Floating-point number; must be finite to validate.
    Float(f64),
    /// One variant of a fixed option list, stored by name; never empty.
    Enum(String),
    /// Free string.
    Text(String),
    /// Float list for curves and control points; every element must be finite.
    Floats(Vec<f64>),
}

impl SettingValue {
    /// Short kind name used in error reports.
    #[must_use]
    pub fn kind_name(&self) -> &'static str {
        match self {
            SettingValue::Bool(_) => "bool",
            SettingValue::Int(_) => "int",
            SettingValue::Float(_) => "float",
            SettingValue::Enum(_) => "enum",
            SettingValue::Text(_) => "text",
            SettingValue::Floats(_) => "floats",
        }
    }

    fn check_against(
        &self,
        expected: ParamType,
        module: &str,
        param: &str,
    ) -> Result<(), SettingsError> {
        let kind_ok = matches!(
            (self, expected),
            (SettingValue::Bool(_), ParamType::Bool)
                | (SettingValue::Int(_), ParamType::Int)
                | (SettingValue::Float(_), ParamType::Float)
                | (SettingValue::Enum(_), ParamType::Enum)
                | (SettingValue::Floats(_), ParamType::Curve)
        );
        if !kind_ok {
            return Err(SettingsError::TypeMismatch {
                module: module.to_owned(),
                param: param.to_owned(),
                expected,
                found: self.kind_name(),
            });
        }
        match self {
            SettingValue::Float(f) if !f.is_finite() => Err(SettingsError::OutOfRange {
                module: module.to_owned(),
                param: param.to_owned(),
                reason: "non-finite float",
            }),
            SettingValue::Floats(v) if v.iter().any(|f| !f.is_finite()) => {
                Err(SettingsError::OutOfRange {
                    module: module.to_owned(),
                    param: param.to_owned(),
                    reason: "non-finite float in list",
                })
            }
            SettingValue::Enum(s) if s.is_empty() => Err(SettingsError::OutOfRange {
                module: module.to_owned(),
                param: param.to_owned(),
                reason: "empty enum variant",
            }),
            _ => Ok(()),
        }
    }
}

/// What is wrong with a settings document: a declared parameter holding a
/// value of the wrong kind or outside its domain, or broken JSON.
#[allow(clippy::module_name_repetitions)]
// Public error names repeat the module by project convention (`SettingsError`
// reads better at use sites than `Error`); the lint's rename would obscure it.
#[derive(Debug)]
pub enum SettingsError {
    /// A declared field holds a value of another kind.
    TypeMismatch {
        /// Owning module id.
        module: String,
        /// Parameter name.
        param: String,
        /// Kind the description declares.
        expected: ParamType,
        /// Kind the value has.
        found: &'static str,
    },
    /// A declared field holds a value outside its domain (non-finite float,
    /// empty enum variant). Values are never silently repaired.
    OutOfRange {
        /// Owning module id.
        module: String,
        /// Parameter name.
        param: String,
        /// Why the value is out of range.
        reason: &'static str,
    },
    /// The document is not valid JSON of this shape.
    Json(serde_json::Error),
}

impl std::fmt::Display for SettingsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SettingsError::TypeMismatch {
                module,
                param,
                expected,
                found,
            } => {
                write!(f, "{module}.{param}: expected {expected:?}, found {found}")
            }
            SettingsError::OutOfRange {
                module,
                param,
                reason,
            } => {
                write!(f, "{module}.{param}: out of range ({reason})")
            }
            SettingsError::Json(err) => write!(f, "invalid settings JSON: {err}"),
        }
    }
}

impl std::error::Error for SettingsError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            SettingsError::Json(err) => Some(err),
            SettingsError::TypeMismatch { .. } | SettingsError::OutOfRange { .. } => None,
        }
    }
}

impl From<serde_json::Error> for SettingsError {
    fn from(err: serde_json::Error) -> Self {
        SettingsError::Json(err)
    }
}

fn enabled_by_default() -> bool {
    true
}

/// One module instance on a photo: identity, switch, and parameters.
///
/// Parameters are a name-to-value map. Names this build does not recognize
/// are kept as ordinary entries, so they survive a load/save round-trip and
/// work again once their module is compiled in.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct ModuleInstance {
    /// Module id, the same string as the A3 descriptor id.
    pub module: String,
    /// Multi-instance index; the first instance is 0.
    #[serde(default)]
    pub multi: u32,
    /// Optional user-given name.
    #[serde(default)]
    pub name: Option<String>,
    /// Whether the instance renders; missing reads as enabled.
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
    /// Parameter name to typed value, sorted by name on the wire.
    #[serde(default)]
    pub params: BTreeMap<String, SettingValue>,
}

impl ModuleInstance {
    /// Checks declared parameters against one module description.
    ///
    /// Fields the description does not declare are kept unchecked; a
    /// description with no fields yet ([`ParamsDesc`] unset, the state of all
    /// A3 stubs) accepts everything. A wrong kind or an out-of-domain value
    /// is an error — values are never silently repaired.
    ///
    /// # Errors
    ///
    /// [`SettingsError::TypeMismatch`] when a declared parameter holds a
    /// value of another kind (including [`SettingValue::Text`], which no
    /// [`ParamType`] declares today); [`SettingsError::OutOfRange`] when a
    /// declared parameter is outside its domain.
    pub fn validate(&self, params: ParamsDesc) -> Result<(), SettingsError> {
        let Some(fields) = params.fields else {
            return Ok(());
        };
        for field in fields {
            if let Some(value) = self.params.get(field.name) {
                value.check_against(field.ty, &self.module, field.name)?;
            }
        }
        Ok(())
    }
}

/// Identity of one instance: module id plus multi-instance index.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
struct InstanceKey {
    module: String,
    multi: u32,
}

impl InstanceKey {
    fn of(instance: &ModuleInstance) -> Self {
        Self {
            module: instance.module.clone(),
            multi: instance.multi,
        }
    }
}

/// The instance list of one photo, kept sorted by (`module`, `multi`).
///
/// Insertion order is unobservable: iteration and serialization always walk
/// the sorted order, so canonical bytes never depend on it. Serializes as a
/// JSON list of instances; on load, a repeated (`module`, `multi`) pair keeps
/// the last entry, like a repeated JSON object key.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct InstanceList(BTreeMap<InstanceKey, ModuleInstance>);

impl Serialize for InstanceList {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_seq(self.0.values())
    }
}

impl<'de> Deserialize<'de> for InstanceList {
    fn deserialize<D: Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        let instances = Vec::<ModuleInstance>::deserialize(d)?;
        let mut map = BTreeMap::new();
        for instance in instances {
            map.insert(InstanceKey::of(&instance), instance);
        }
        Ok(Self(map))
    }
}

impl InstanceList {
    /// Empty list.
    #[must_use]
    pub fn new() -> Self {
        Self(BTreeMap::new())
    }

    /// Inserts or replaces the instance with the same (`module`, `multi`).
    /// Returns the replaced instance, if any.
    pub fn upsert(&mut self, instance: ModuleInstance) -> Option<ModuleInstance> {
        self.0.insert(InstanceKey::of(&instance), instance)
    }

    /// Finds one instance by module id and multi-instance index.
    #[must_use]
    pub fn get(&self, module: &str, multi: u32) -> Option<&ModuleInstance> {
        let key = InstanceKey {
            module: module.to_owned(),
            multi,
        };
        self.0.get(&key)
    }

    /// Removes one instance; returns it, if it was there.
    pub fn remove(&mut self, module: &str, multi: u32) -> Option<ModuleInstance> {
        let key = InstanceKey {
            module: module.to_owned(),
            multi,
        };
        self.0.remove(&key)
    }

    /// Iterates instances in (`module`, `multi`) order.
    pub fn iter(&self) -> impl Iterator<Item = &ModuleInstance> {
        self.0.values()
    }

    /// Number of instances.
    #[must_use]
    pub fn len(&self) -> usize {
        self.0.len()
    }

    /// Whether there are no instances.
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }
}

/// The complete settings of one photo: process plus module instances.
///
/// Unknown top-level fields are ignored on load and missing fields take
/// defaults ([`FORMAT_VERSION`], V1 process, empty list). Unknown module ids
/// and parameter names are kept as data. The struct's `Default` is a fresh
/// photo: the latest process with no instances.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct PhotoSettings {
    /// Wire format version; a newer number from a future writer is kept.
    #[serde(default = "default_format_version")]
    pub format_version: u32,
    /// Rendering process; missing or damaged reads as V1, a newer number is
    /// kept and never downgraded.
    #[serde(default = "ProcessVersion::legacy")]
    pub process: ProcessVersion,
    /// Module instances in (`module`, `multi`) order.
    #[serde(default)]
    pub instances: InstanceList,
}

impl Default for PhotoSettings {
    /// Fresh photo: current format, latest process, no instances.
    fn default() -> Self {
        Self {
            format_version: FORMAT_VERSION,
            process: ProcessVersion::LATEST,
            instances: InstanceList::new(),
        }
    }
}

impl PhotoSettings {
    /// Canonical JSON: the same settings always produce the same bytes,
    /// regardless of insertion order (sorted maps, fixed field order).
    ///
    /// A finiteness gate runs first: `serde_json` would write a non-finite
    /// float as `null`, which could never read back as the same settings,
    /// so such settings are refused instead of being mangled.
    ///
    /// # Errors
    ///
    /// [`SettingsError::OutOfRange`] when any float is non-finite, even in
    /// undeclared parameters; [`SettingsError::Json`] when serialization
    /// itself fails.
    pub fn canonical_json(&self) -> Result<String, SettingsError> {
        for instance in self.instances.iter() {
            for (name, value) in &instance.params {
                let bad = match value {
                    SettingValue::Float(f) => !f.is_finite(),
                    SettingValue::Floats(v) => v.iter().any(|f| !f.is_finite()),
                    _ => false,
                };
                if bad {
                    return Err(SettingsError::OutOfRange {
                        module: instance.module.clone(),
                        param: name.clone(),
                        reason: "non-finite float",
                    });
                }
            }
        }
        Ok(serde_json::to_string(self)?)
    }

    /// Parses canonical (or hand-written) JSON back into settings.
    ///
    /// # Errors
    ///
    /// [`SettingsError::Json`] when the text is not settings-shaped JSON.
    pub fn from_json(text: &str) -> Result<Self, SettingsError> {
        Ok(serde_json::from_str(text)?)
    }

    /// Stable 64-bit cache key: FNV-1a over [`PhotoSettings::canonical_json`],
    /// so the settings and the process version both feed the key. Shares the
    /// canonical path (including its finiteness gate): settings the gate
    /// refuses hash as empty. Hash only validated settings.
    #[must_use]
    pub fn hash64(&self) -> u64 {
        let text = self.canonical_json().unwrap_or_default();
        let mut hash: u64 = 0xcbf2_9ce4_8422_2325;
        for byte in text.as_bytes() {
            hash ^= u64::from(*byte);
            hash = hash.wrapping_mul(0x0100_0000_01b3);
        }
        hash
    }

    /// [`PhotoSettings::hash64`] as a decimal string: every 64-bit hash this
    /// project stores on disk uses the decimal form.
    #[must_use]
    pub fn hash64_decimal(&self) -> String {
        self.hash64().to_string()
    }

    /// Checks every instance against its description from `lookup`.
    ///
    /// Modules the lookup does not know are kept unchecked, like undeclared
    /// parameters (see [`ModuleInstance::validate`]).
    ///
    /// # Errors
    ///
    /// The first [`SettingsError::TypeMismatch`] or
    /// [`SettingsError::OutOfRange`] found, if any.
    pub fn validate_all(
        &self,
        lookup: &dyn Fn(&str) -> Option<ParamsDesc>,
    ) -> Result<(), SettingsError> {
        for instance in self.instances.iter() {
            if let Some(params) = lookup(&instance.module) {
                instance.validate(params)?;
            }
        }
        Ok(())
    }

    /// Copy/paste: replaces the instances with the source's, keeps our own
    /// process version and format version.
    pub fn apply_copied(&mut self, source: &PhotoSettings) {
        self.instances.clone_from(&source.instances);
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

    use super::{
        FORMAT_VERSION, InstanceList, ModuleInstance, PhotoSettings, ProcessVersion, SettingValue,
        SettingsError,
    };
    use dt_iop_traits::{ParamField, ParamType, ParamsDesc};
    use serde_json::json;

    fn all_kinds() -> Vec<(String, SettingValue)> {
        vec![
            ("p_bool".to_owned(), SettingValue::Bool(true)),
            ("p_int".to_owned(), SettingValue::Int(-42)),
            ("p_float".to_owned(), SettingValue::Float(1.5)),
            (
                "p_enum".to_owned(),
                SettingValue::Enum("choice_one".to_owned()),
            ),
            (
                "p_text".to_owned(),
                SettingValue::Text("free text".to_owned()),
            ),
            (
                "p_floats".to_owned(),
                SettingValue::Floats(vec![0.0, 0.25, 1.0]),
            ),
        ]
    }

    fn sample_settings() -> PhotoSettings {
        let mut settings = PhotoSettings::default();
        settings.instances.upsert(ModuleInstance {
            module: "mod_a".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: all_kinds().into_iter().collect(),
        });
        settings.instances.upsert(ModuleInstance {
            module: "mod_b".to_owned(),
            multi: 1,
            name: Some("second".to_owned()),
            enabled: false,
            params: [("p_float".to_owned(), SettingValue::Float(2.0))]
                .into_iter()
                .collect(),
        });
        settings
    }

    #[test]
    fn settings_write_then_read_back_equal() {
        let settings = sample_settings();
        let text = settings.canonical_json().unwrap();
        assert!(
            text.contains("\"process\":1"),
            "process always written: {text}"
        );
        let back = PhotoSettings::from_json(&text).unwrap();
        assert_eq!(back, settings);
    }

    #[test]
    fn unknown_fields_ignored_and_missing_take_defaults() {
        let value = json!({
            "top_level_future": {"anything": [1, 2]},
            "instances": [{
                "module": "mod_a",
                "instance_future": 7,
            }],
        });
        let settings: PhotoSettings = serde_json::from_value(value).unwrap();
        assert_eq!(settings.format_version, FORMAT_VERSION);
        assert_eq!(settings.process, ProcessVersion::V1);
        let only = settings.instances.get("mod_a", 0).unwrap();
        assert_eq!(only.multi, 0);
        assert_eq!(only.name, None);
        assert!(only.enabled);
        assert!(only.params.is_empty());
    }

    #[test]
    fn unknown_modules_and_params_are_retained() {
        let mut settings = PhotoSettings::default();
        settings.instances.upsert(ModuleInstance {
            module: "mod_unknown".to_owned(),
            multi: 3,
            name: None,
            enabled: true,
            params: all_kinds().into_iter().collect(),
        });
        let text = settings.canonical_json().unwrap();
        let back = PhotoSettings::from_json(&text).unwrap();
        assert_eq!(back, settings);
        let kept = back.instances.get("mod_unknown", 3).unwrap();
        assert_eq!(kept.params.len(), 6);
        assert!(text.contains("mod_unknown"));
    }

    #[test]
    fn newer_format_version_is_kept() {
        let value = json!({"format_version": 9, "instances": []});
        let settings: PhotoSettings = serde_json::from_value(value).unwrap();
        assert_eq!(settings.format_version, 9);
        let text = settings.canonical_json().unwrap();
        assert!(text.contains("\"format_version\":9"), "{text}");
    }

    fn desc_of(fields: &'static [ParamField]) -> ParamsDesc {
        ParamsDesc {
            fields: Some(fields),
        }
    }

    static FLOAT_FIELD: &[ParamField] = &[ParamField {
        name: "p_float",
        ty: ParamType::Float,
    }];
    static ENUM_FIELD: &[ParamField] = &[ParamField {
        name: "p_enum",
        ty: ParamType::Enum,
    }];
    static CURVE_FIELD: &[ParamField] = &[ParamField {
        name: "p_floats",
        ty: ParamType::Curve,
    }];

    fn instance_with(value: SettingValue) -> ModuleInstance {
        let name = if matches!(value, SettingValue::Enum(_)) {
            "p_enum"
        } else {
            "p_float"
        };
        ModuleInstance {
            module: "mod_a".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: [(name.to_owned(), value)].into_iter().collect(),
        }
    }

    fn instance_with_floats(values: Vec<f64>) -> ModuleInstance {
        ModuleInstance {
            module: "mod_a".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: [("p_floats".to_owned(), SettingValue::Floats(values))]
                .into_iter()
                .collect(),
        }
    }

    #[test]
    fn validation_rejects_wrong_type() {
        let instance = instance_with(SettingValue::Int(1));
        let err = instance.validate(desc_of(FLOAT_FIELD)).unwrap_err();
        assert!(matches!(err, SettingsError::TypeMismatch { .. }), "{err:?}");
        assert_eq!(err.to_string(), "mod_a.p_float: expected Float, found int");
        let text = instance_with(SettingValue::Text("x".to_owned()));
        assert!(matches!(
            text.validate(desc_of(FLOAT_FIELD)).unwrap_err(),
            SettingsError::TypeMismatch { .. }
        ));
    }

    #[test]
    fn validation_rejects_nonfinite_float() {
        for bad in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
            let instance = instance_with(SettingValue::Float(bad));
            let err = instance.validate(desc_of(FLOAT_FIELD)).unwrap_err();
            assert!(
                matches!(err, SettingsError::OutOfRange { .. }),
                "{bad}: {err:?}"
            );
        }
        let list = instance_with_floats(vec![0.0, f64::NAN]);
        assert!(matches!(
            list.validate(desc_of(CURVE_FIELD)).unwrap_err(),
            SettingsError::OutOfRange { .. }
        ));
        let bad = sample_settings_with_float(f64::NAN);
        assert!(bad.canonical_json().is_err());
    }

    fn sample_settings_with_float(value: f64) -> PhotoSettings {
        let mut settings = PhotoSettings::default();
        settings
            .instances
            .upsert(instance_with(SettingValue::Float(value)));
        settings
    }

    #[test]
    fn validation_rejects_empty_enum() {
        let instance = instance_with(SettingValue::Enum(String::new()));
        let err = instance.validate(desc_of(ENUM_FIELD)).unwrap_err();
        assert!(matches!(err, SettingsError::OutOfRange { .. }), "{err:?}");
    }

    #[test]
    fn validation_ignores_undeclared_and_unset() {
        let settings = sample_settings();
        let lookup =
            |id: &str| -> Option<ParamsDesc> { (id == "mod_a").then_some(desc_of(FLOAT_FIELD)) };
        assert!(settings.validate_all(&lookup).is_ok());
        let unset = ModuleInstance {
            module: "mod_a".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: [("p_float".to_owned(), SettingValue::Bool(true))]
                .into_iter()
                .collect(),
        };
        assert!(unset.validate(ParamsDesc::unset()).is_ok());
    }

    #[test]
    fn missing_or_damaged_process_reads_as_v1() {
        let missing: PhotoSettings = serde_json::from_value(json!({"instances": []})).unwrap();
        assert_eq!(missing.process, ProcessVersion::V1);
        for damaged in [
            json!("x"),
            json!(-1),
            json!(1.5),
            json!(4_294_967_296_u64),
            json!(null),
            json!([1]),
            json!({"n": 1}),
        ] {
            let settings: PhotoSettings =
                serde_json::from_value(json!({"process": damaged, "instances": []})).unwrap();
            assert_eq!(settings.process, ProcessVersion::V1, "{damaged}");
        }
        let whole_float: PhotoSettings =
            serde_json::from_value(json!({"process": 2.0, "instances": []})).unwrap();
        assert_eq!(whole_float.process, ProcessVersion(2));
    }

    #[test]
    fn newer_process_version_is_kept_not_downgraded() {
        let settings: PhotoSettings =
            serde_json::from_value(json!({"process": 999, "instances": []})).unwrap();
        assert_eq!(settings.process, ProcessVersion(999));
        let text = settings.canonical_json().unwrap();
        assert!(text.contains("\"process\":999"), "{text}");
        let mut kept = settings.process;
        assert!(!kept.is_outdated());
        kept.update_to_latest();
        assert_eq!(kept, ProcessVersion(999));
        let mut old = ProcessVersion(0);
        assert!(old.is_outdated());
        old.update_to_latest();
        assert_eq!(old, ProcessVersion::LATEST);
        assert_eq!(PhotoSettings::default().process, ProcessVersion::LATEST);
        assert!(!ProcessVersion(999).is_known());
        assert!(ProcessVersion::V1.is_known());
    }

    #[test]
    fn process_u32_max_boundary_is_kept() {
        let settings: PhotoSettings =
            serde_json::from_value(json!({"process": 4_294_967_295_u64, "instances": []})).unwrap();
        assert_eq!(settings.process, ProcessVersion(u32::MAX));
        let whole: PhotoSettings =
            serde_json::from_value(json!({"process": 4_294_967_295.0, "instances": []})).unwrap();
        assert_eq!(whole.process, ProcessVersion(u32::MAX));
    }

    #[test]
    fn same_settings_same_cache_key_param_change_changes_key() {
        let settings = sample_settings();
        let twin = settings.clone();
        assert_eq!(settings.hash64(), twin.hash64());
        assert_eq!(settings.hash64_decimal(), settings.hash64().to_string());
        let mut changed = settings.clone();
        changed
            .instances
            .upsert(instance_with(SettingValue::Float(9.0)));
        assert_ne!(changed.hash64(), settings.hash64());
        let mut reprocessed = settings.clone();
        reprocessed.process = ProcessVersion(999);
        assert_ne!(reprocessed.hash64(), settings.hash64());
    }

    #[test]
    fn insertion_order_does_not_change_canonical_bytes() {
        let mut first = PhotoSettings::default();
        first.instances.upsert(ModuleInstance {
            module: "mod_b".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: [("p_int".to_owned(), SettingValue::Int(1))]
                .into_iter()
                .collect(),
        });
        first.instances.upsert(ModuleInstance {
            module: "mod_a".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: all_kinds().into_iter().collect(),
        });
        let mut second = PhotoSettings::default();
        let mut reversed = all_kinds();
        reversed.reverse();
        second.instances.upsert(ModuleInstance {
            module: "mod_a".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: reversed.into_iter().collect(),
        });
        second.instances.upsert(ModuleInstance {
            module: "mod_b".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: [("p_int".to_owned(), SettingValue::Int(1))]
                .into_iter()
                .collect(),
        });
        assert_eq!(first, second);
        assert_eq!(
            first.canonical_json().unwrap(),
            second.canonical_json().unwrap()
        );
    }

    #[test]
    fn instance_list_replaces_and_removes() {
        let mut list = InstanceList::new();
        assert!(list.is_empty());
        let first = instance_with(SettingValue::Float(1.0));
        assert!(list.upsert(first).is_none());
        assert_eq!(list.len(), 1);
        let again = instance_with(SettingValue::Float(2.0));
        let old = list.upsert(again).unwrap();
        assert_eq!(old.params.get("p_float"), Some(&SettingValue::Float(1.0)));
        assert_eq!(list.len(), 1);
        assert!(list.remove("mod_a", 0).is_some());
        assert!(list.is_empty());
        assert!(list.remove("mod_a", 0).is_none());
    }

    #[test]
    fn instance_list_load_keeps_last_of_duplicate_keys() {
        let value = json!({
            "instances": [
                {"module": "mod_a", "params": {"p_int": {"type": "int", "value": 1}}},
                {"module": "mod_a", "params": {"p_int": {"type": "int", "value": 2}}},
            ],
        });
        let settings: PhotoSettings = serde_json::from_value(value).unwrap();
        assert_eq!(settings.instances.len(), 1);
        let only = settings.instances.get("mod_a", 0).unwrap();
        assert_eq!(only.params.get("p_int"), Some(&SettingValue::Int(2)));
    }
}

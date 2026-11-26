// SPDX-License-Identifier: GPL-3.0-or-later
//! Merging one photo's adjustments into another's: module and parameter grain.
//!
//! [`merge_adjustments`] is a pure function: the target's current settings,
//! the source settings, and a [`MergeSelection`] in, the merged settings out.
//! Only instances move; the target's format and process versions are never
//! touched. Selections that name nothing in the source are no-ops, never
//! deletions: merging takes what the source has and leaves everything else
//! exactly where it was.

use super::settings::PhotoSettings;

/// One instance named inside a [`MergeSelection`]: module id plus
/// multi-instance index.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModuleRef {
    /// Module id, the same string as the descriptor id.
    pub module: String,
    /// Multi-instance index; the first instance is 0.
    pub multi: u32,
}

/// Named parameters of one instance inside a [`MergeSelection`].
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModuleParams {
    /// Module id, the same string as the descriptor id.
    pub module: String,
    /// Multi-instance index; the first instance is 0.
    pub multi: u32,
    /// Parameter names to take from the source instance.
    pub params: Vec<String>,
}

/// What [`merge_adjustments`] takes from the source settings.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MergeSelection {
    /// Whole instances: each named instance replaces the target's same
    /// instance or is added when the target lacks it. A named instance the
    /// source lacks leaves the target untouched.
    Modules(Vec<ModuleRef>),
    /// Named parameters of instances: each named parameter present in the
    /// source instance overwrites the target's same parameter. Parameters
    /// (or instances) the source lacks leave the target untouched; when the
    /// target lacks the instance but the source has it, the instance is
    /// created carrying only the selected parameters present in the source
    /// (plus the source's switch and name).
    Params(Vec<ModuleParams>),
}

/// Merges the source's selected adjustments over the target's settings.
///
/// Selected module instances replace or join the target's; unselected ones
/// are not moved, renamed, or removed. The target's format and process
/// versions stay exactly as they were.
#[must_use]
pub fn merge_adjustments(
    target: &PhotoSettings,
    source: &PhotoSettings,
    selection: &MergeSelection,
) -> PhotoSettings {
    let mut merged = target.clone();
    match selection {
        MergeSelection::Modules(refs) => {
            for named in refs {
                if let Some(instance) = source.instances.get(&named.module, named.multi) {
                    merged.instances.upsert(instance.clone());
                }
            }
        }
        MergeSelection::Params(entries) => {
            for entry in entries {
                let Some(from) = source.instances.get(&entry.module, entry.multi) else {
                    continue;
                };
                let mut instance = merged
                    .instances
                    .get(&entry.module, entry.multi)
                    .cloned()
                    .unwrap_or_else(|| super::settings::ModuleInstance {
                        module: entry.module.clone(),
                        multi: entry.multi,
                        name: from.name.clone(),
                        enabled: from.enabled,
                        params: std::collections::BTreeMap::new(),
                    });
                for name in &entry.params {
                    if let Some(value) = from.params.get(name) {
                        instance.params.insert(name.clone(), value.clone());
                    }
                }
                merged.instances.upsert(instance);
            }
        }
    }
    merged
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use std::collections::BTreeMap;

    use super::{MergeSelection, ModuleParams, ModuleRef, merge_adjustments};
    use crate::settings::{ModuleInstance, PhotoSettings, ProcessVersion, SettingValue};

    fn instance(
        module: &str,
        multi: u32,
        enabled: bool,
        params: &[(&str, SettingValue)],
    ) -> ModuleInstance {
        ModuleInstance {
            module: module.to_owned(),
            multi,
            name: None,
            enabled,
            params: params
                .iter()
                .map(|(name, value)| ((*name).to_owned(), value.clone()))
                .collect::<BTreeMap<_, _>>(),
        }
    }

    fn settings(process: u32, instances: &[ModuleInstance]) -> PhotoSettings {
        let mut settings = PhotoSettings {
            format_version: crate::settings::FORMAT_VERSION,
            process: ProcessVersion(process),
            instances: crate::settings::InstanceList::new(),
        };
        for one in instances {
            settings.instances.upsert(one.clone());
        }
        settings
    }

    #[test]
    fn modules_replace_the_selected_instance_wholesale() {
        let target = settings(
            1,
            &[
                instance("mod_a", 0, true, &[("p_x", SettingValue::Float(1.0))]),
                instance("mod_b", 0, true, &[("p_y", SettingValue::Bool(true))]),
            ],
        );
        let source = settings(
            7,
            &[instance(
                "mod_a",
                0,
                false,
                &[("p_x", SettingValue::Float(2.0))],
            )],
        );
        let merged = merge_adjustments(
            &target,
            &source,
            &MergeSelection::Modules(vec![ModuleRef {
                module: "mod_a".to_owned(),
                multi: 0,
            }]),
        );
        // The selected instance is the source's, switch included.
        let taken = merged.instances.get("mod_a", 0).expect("taken");
        assert!(!taken.enabled);
        assert_eq!(taken.params.get("p_x"), Some(&SettingValue::Float(2.0)));
        // The unselected instance is untouched, and so is the target process.
        assert_eq!(
            merged.instances.get("mod_b", 0),
            target.instances.get("mod_b", 0)
        );
        assert_eq!(merged.process, ProcessVersion(1));
        assert_eq!(merged.format_version, target.format_version);
    }

    #[test]
    fn modules_add_missing_and_skip_source_absent_selections() {
        let target = settings(
            1,
            &[instance(
                "mod_b",
                0,
                true,
                &[("p_y", SettingValue::Bool(true))],
            )],
        );
        let source = settings(
            7,
            &[instance(
                "mod_a",
                3,
                true,
                &[("p_x", SettingValue::Float(2.0))],
            )],
        );
        let merged = merge_adjustments(
            &target,
            &source,
            &MergeSelection::Modules(vec![
                ModuleRef {
                    module: "mod_a".to_owned(),
                    multi: 3,
                },
                ModuleRef {
                    module: "mod_gone".to_owned(),
                    multi: 0,
                },
            ]),
        );
        // Added from the source.
        assert_eq!(
            merged.instances.get("mod_a", 3),
            source.instances.get("mod_a", 3)
        );
        // Named but absent in the source: no deletion, no stub.
        assert!(merged.instances.get("mod_gone", 0).is_none());
        assert_eq!(
            merged.instances.get("mod_b", 0),
            target.instances.get("mod_b", 0)
        );
        assert_eq!(merged.process, ProcessVersion(1));
    }

    #[test]
    fn params_overwrite_only_the_named_parameters() {
        let target = settings(
            1,
            &[instance(
                "mod_a",
                0,
                true,
                &[
                    ("p_x", SettingValue::Float(1.0)),
                    ("p_keep", SettingValue::Bool(false)),
                ],
            )],
        );
        let source = settings(
            7,
            &[instance(
                "mod_a",
                0,
                false,
                &[
                    ("p_x", SettingValue::Float(2.0)),
                    ("p_other", SettingValue::Bool(true)),
                ],
            )],
        );
        let merged = merge_adjustments(
            &target,
            &source,
            &MergeSelection::Params(vec![ModuleParams {
                module: "mod_a".to_owned(),
                multi: 0,
                params: vec!["p_x".to_owned(), "p_missing".to_owned()],
            }]),
        );
        let kept = merged.instances.get("mod_a", 0).expect("kept");
        // Named and present: overwritten. Named but absent in the source:
        // nothing. Unnamed: kept, switch included.
        assert_eq!(kept.params.get("p_x"), Some(&SettingValue::Float(2.0)));
        assert!(!kept.params.contains_key("p_missing"));
        assert_eq!(kept.params.get("p_keep"), Some(&SettingValue::Bool(false)));
        assert!(!kept.params.contains_key("p_other"));
        assert!(kept.enabled);
        assert_eq!(merged.process, ProcessVersion(1));
    }

    #[test]
    fn params_create_a_missing_instance_with_only_selected_parameters() {
        let target = settings(1, &[]);
        let source = settings(
            7,
            &[instance(
                "mod_a",
                2,
                false,
                &[
                    ("p_x", SettingValue::Float(2.0)),
                    ("p_other", SettingValue::Bool(true)),
                ],
            )],
        );
        let merged = merge_adjustments(
            &target,
            &source,
            &MergeSelection::Params(vec![ModuleParams {
                module: "mod_a".to_owned(),
                multi: 2,
                params: vec!["p_x".to_owned()],
            }]),
        );
        let made = merged.instances.get("mod_a", 2).expect("made");
        // Only the selected parameter travelled; the switch came along.
        assert_eq!(made.params.len(), 1);
        assert_eq!(made.params.get("p_x"), Some(&SettingValue::Float(2.0)));
        assert!(!made.enabled);
        assert_eq!(merged.process, ProcessVersion(1));
    }
}

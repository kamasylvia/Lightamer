// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from lightcraft crates/catalog/src/model.rs (`HistoryStep`),
// crates/catalog/src/lib.rs (`HISTORY_LIMIT`, push/cursor handling) and
// crates/engine/src/lib.rs (`begin/end/cancel_interaction`, commit 0da998f2)
// — reworked: the cursor is an explicit index, the interaction lives on the
// stack instead of the engine, batch adjustments are a process-free carrier.
//! Snapshot history of one photo.
//!
//! Each [`HistoryStep`] holds a full [`PhotoSettings`] snapshot behind an
//! [`Arc`], plus the label of the command that committed it.
//! [`HistoryStack`] adds the cursor (undo/redo/goto), the step cap, and the
//! drag-merge interaction: `begin` … `end` folds any number of live updates
//! into one step, `cancel` returns to the pre-interaction state.

use std::sync::Arc;

use serde::{Deserialize, Serialize};

use super::settings::{InstanceList, PhotoSettings};

/// Maximum steps kept per photo; older steps drop from the front.
/// Mirrors `LightCraft`'s `catalog::HISTORY_LIMIT`.
pub const HISTORY_LIMIT: usize = 200;

/// Label of the step a fresh stack starts on.
///
/// Public so the session store and the engine name step 0 from this one
/// source instead of repeating the literal.
pub const INITIAL_LABEL: &str = "import";

/// One undo step: the command label plus a full settings snapshot.
#[allow(clippy::module_name_repetitions)]
// Public names mirror LightCraft (`HistoryStep`); renaming would obscure
// the shared vocabulary between the two models.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct HistoryStep {
    /// Which command committed this step.
    pub label: String,
    /// Full settings snapshot, shared by [`Arc`].
    pub settings: Arc<PhotoSettings>,
}

/// One open drag-merge interaction: the label for the eventual step, the
/// settings from before the interaction, and the current live value.
#[derive(Clone, Debug, PartialEq)]
struct Interaction {
    label: String,
    original: Arc<PhotoSettings>,
    live: Arc<PhotoSettings>,
}

/// Undo stack of one photo: steps, cursor, and at most one open interaction.
///
/// The stack always holds at least one step; the cursor always names the
/// current one. Interaction rule: [`HistoryStack::commit`],
/// [`HistoryStack::undo`], [`HistoryStack::redo`], and [`HistoryStack::goto`]
/// first end an open interaction (committing its step when it changed), so an
/// unended interaction can never silently lose — or strand — live edits.
#[allow(clippy::module_name_repetitions)]
// Same shared-vocabulary reason as [`HistoryStep`].
#[derive(Clone, Debug, PartialEq)]
pub struct HistoryStack {
    steps: Vec<HistoryStep>,
    cursor: usize,
    interaction: Option<Interaction>,
}

impl HistoryStack {
    /// Fresh stack: one step holding `initial`.
    #[must_use]
    pub fn new(initial: Arc<PhotoSettings>) -> Self {
        Self {
            steps: vec![HistoryStep {
                label: INITIAL_LABEL.to_owned(),
                settings: initial,
            }],
            cursor: 0,
            interaction: None,
        }
    }

    /// Current settings: the live value while an interaction is open, else
    /// the step under the cursor.
    #[must_use]
    pub fn current(&self) -> Option<&Arc<PhotoSettings>> {
        if let Some(open) = self.interaction.as_ref() {
            return Some(&open.live);
        }
        self.steps.get(self.cursor).map(|step| &step.settings)
    }

    /// One step by index, oldest first.
    #[must_use]
    pub fn step(&self, index: usize) -> Option<&HistoryStep> {
        self.steps.get(index)
    }

    /// Cursor position: index of the current step.
    #[must_use]
    pub fn cursor_index(&self) -> usize {
        self.cursor
    }

    /// Step labels, oldest first.
    #[must_use]
    pub fn labels(&self) -> Vec<&str> {
        self.steps.iter().map(|step| step.label.as_str()).collect()
    }

    /// Number of steps.
    #[must_use]
    pub fn len(&self) -> usize {
        self.steps.len()
    }

    /// Whether there are no steps (never true past construction).
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.steps.is_empty()
    }

    /// Whether an interaction is open.
    #[must_use]
    pub fn is_interaction_open(&self) -> bool {
        self.interaction.is_some()
    }

    /// What ending the open interaction would commit: the step label and the
    /// live value when the drag changed anything; `None` when no interaction
    /// is open or the live value still equals the pre-interaction settings
    /// (ending then commits nothing). Persisted commands peek through this
    /// before they touch the store, so the store learns exactly the step the
    /// memory call would commit.
    #[must_use]
    pub fn pending_interaction(&self) -> Option<(&str, &Arc<PhotoSettings>)> {
        let open = self.interaction.as_ref()?;
        if open.live == open.original {
            return None;
        }
        Some((open.label.as_str(), &open.live))
    }

    /// Commits one step: drops every step after the cursor, pushes, and moves
    /// the cursor onto the new step; past [`HISTORY_LIMIT`], the oldest steps
    /// drop from the front. Ends an open interaction first (see the struct
    /// rule).
    pub fn commit(&mut self, label: &str, settings: Arc<PhotoSettings>) {
        if self.interaction.is_some() {
            self.end_interaction();
        }
        self.steps.truncate(self.cursor.saturating_add(1));
        self.steps.push(HistoryStep {
            label: label.to_owned(),
            settings,
        });
        if self.steps.len() > HISTORY_LIMIT {
            let drop = self.steps.len() - HISTORY_LIMIT;
            self.steps.drain(..drop);
        }
        self.cursor = self.steps.len().saturating_sub(1);
    }

    /// Moves the cursor one step back. Ends an open interaction first.
    /// Returns whether the cursor moved.
    pub fn undo(&mut self) -> bool {
        if self.interaction.is_some() {
            self.end_interaction();
        }
        match self.cursor.checked_sub(1) {
            Some(prev) if prev < self.steps.len() => {
                self.cursor = prev;
                true
            }
            Some(_) | None => false,
        }
    }

    /// Moves the cursor one step forward. Ends an open interaction first.
    /// Returns whether the cursor moved.
    pub fn redo(&mut self) -> bool {
        if self.interaction.is_some() {
            self.end_interaction();
        }
        let next = self.cursor.saturating_add(1);
        if next < self.steps.len() {
            self.cursor = next;
            true
        } else {
            false
        }
    }

    /// Jumps the cursor onto one step. Ends an open interaction first.
    /// Returns false (and moves nothing) for an out-of-range index.
    pub fn goto(&mut self, index: usize) -> bool {
        if self.interaction.is_some() {
            self.end_interaction();
        }
        if index < self.steps.len() {
            self.cursor = index;
            true
        } else {
            false
        }
    }

    /// Starts a drag-merge interaction: snapshots the current settings.
    /// A previous interaction still open is ended first.
    pub fn begin_interaction(&mut self, label: &str) {
        if self.interaction.is_some() {
            self.end_interaction();
        }
        if let Some(current) = self.current() {
            self.interaction = Some(Interaction {
                label: label.to_owned(),
                original: Arc::clone(current),
                live: Arc::clone(current),
            });
        }
    }

    /// Replaces the live value mid-interaction; a no-op returning false when
    /// no interaction is open.
    pub fn update_interaction(&mut self, settings: Arc<PhotoSettings>) -> bool {
        match self.interaction.as_mut() {
            Some(open) => {
                open.live = settings;
                true
            }
            None => false,
        }
    }

    /// Ends the interaction, committing the live value as one step — unless
    /// it still equals the pre-interaction settings, which commits nothing.
    pub fn end_interaction(&mut self) {
        if let Some(open) = self.interaction.take()
            && open.live != open.original
        {
            self.commit(&open.label, open.live);
        }
    }

    /// Abandons the interaction: the live value is dropped and the current
    /// settings are the pre-interaction ones again. Commits nothing.
    pub fn cancel_interaction(&mut self) {
        self.interaction = None;
    }

    /// Rebuilds a stack from stored steps: their labels and settings plus
    /// where the cursor sat. The rebuilt stack equals one built step by step
    /// (same steps, same cursor, no open interaction); the [`HISTORY_LIMIT`]
    /// rule holds, so more stored steps than the limit is refused rather
    /// than silently trimmed.
    ///
    /// # Errors
    ///
    /// [`RebuildError::Empty`] when no step is given; [`RebuildError::TooMany`]
    /// when the steps exceed [`HISTORY_LIMIT`]; [`RebuildError::CursorOutOfRange`]
    /// when the cursor names no step.
    pub fn from_steps(steps: Vec<HistoryStep>, cursor: usize) -> Result<Self, RebuildError> {
        if steps.is_empty() {
            return Err(RebuildError::Empty);
        }
        if steps.len() > HISTORY_LIMIT {
            return Err(RebuildError::TooMany {
                steps: steps.len(),
                limit: HISTORY_LIMIT,
            });
        }
        if cursor >= steps.len() {
            return Err(RebuildError::CursorOutOfRange {
                cursor,
                steps: steps.len(),
            });
        }
        Ok(Self {
            steps,
            cursor,
            interaction: None,
        })
    }
}

/// What is wrong with stored steps handed to [`HistoryStack::from_steps`].
#[allow(clippy::module_name_repetitions)]
// Public error names repeat the module by project convention (`RebuildError`
// reads better at use sites than `Error`); the lint's rename would obscure it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RebuildError {
    /// No step was given; a stack always holds at least one step.
    Empty,
    /// More steps than [`HISTORY_LIMIT`]; stored histories never exceed it.
    TooMany {
        /// How many steps were given.
        steps: usize,
        /// The limit they exceeded.
        limit: usize,
    },
    /// The cursor names no step.
    CursorOutOfRange {
        /// The cursor that was given.
        cursor: usize,
        /// How many steps were given.
        steps: usize,
    },
}

impl std::fmt::Display for RebuildError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RebuildError::Empty => write!(f, "cannot rebuild a stack from no steps"),
            RebuildError::TooMany { steps, limit } => {
                write!(
                    f,
                    "cannot rebuild a stack from {steps} steps (limit {limit})"
                )
            }
            RebuildError::CursorOutOfRange { cursor, steps } => {
                write!(f, "cursor {cursor} names no step of {steps}")
            }
        }
    }
}

impl std::error::Error for RebuildError {}

/// Adjustments copied for batch apply: module instances only.
///
/// There is deliberately **no process field**: the type itself makes it
/// impossible to carry a process version into [`apply_batch`], so every
/// target keeps its own (`LightCraft` keeps the process out of every settings
/// group for the same reason).
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct BatchAdjustments {
    /// Instances to install on each target.
    pub instances: InstanceList,
}

impl BatchAdjustments {
    /// Takes the instances out of one photo's settings; the process stays
    /// behind by construction.
    #[must_use]
    pub fn from_settings(source: &PhotoSettings) -> Self {
        Self {
            instances: source.instances.clone(),
        }
    }
}

/// Applies one batch to many photos: each stack commits exactly one step
/// whose instances are the batch's and whose process version is its own
/// current one.
pub fn apply_batch(stacks: &mut [HistoryStack], batch: &BatchAdjustments, label: &str) {
    for stack in stacks {
        if let Some(current) = stack.current() {
            let next = PhotoSettings {
                format_version: current.format_version,
                process: current.process,
                instances: batch.instances.clone(),
            };
            stack.commit(label, Arc::new(next));
        }
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

    use std::sync::Arc;

    use super::{BatchAdjustments, HISTORY_LIMIT, HistoryStack, apply_batch};
    use crate::settings::{ModuleInstance, PhotoSettings, ProcessVersion, SettingValue};

    fn settings_with_float(value: f64) -> Arc<PhotoSettings> {
        let mut settings = PhotoSettings::default();
        settings.instances.upsert(ModuleInstance {
            module: "mod_a".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: [("p_float".to_owned(), SettingValue::Float(value))]
                .into_iter()
                .collect(),
        });
        Arc::new(settings)
    }

    fn float_of(settings: &PhotoSettings) -> f64 {
        match settings
            .instances
            .get("mod_a", 0)
            .unwrap()
            .params
            .get("p_float")
        {
            Some(SettingValue::Float(value)) => *value,
            _ => f64::NAN,
        }
    }

    #[test]
    fn commit_drops_redo_tail() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        stack.commit("step-a", settings_with_float(1.0));
        stack.commit("step-b", settings_with_float(2.0));
        assert!(stack.undo());
        stack.commit("step-c", settings_with_float(3.0));
        assert_eq!(stack.labels(), vec!["import", "step-a", "step-c"]);
        assert_eq!(stack.cursor_index(), 2);
        assert!(!stack.redo());
        assert_eq!(float_of(stack.current().unwrap()), 3.0);
    }

    #[test]
    fn undo_redo_goto_move_cursor() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        stack.commit("step-a", settings_with_float(1.0));
        stack.commit("step-b", settings_with_float(2.0));
        assert!(!stack.redo());
        assert!(stack.undo());
        assert!(stack.undo());
        assert!(!stack.undo());
        assert_eq!(float_of(stack.current().unwrap()), 0.0);
        assert!(stack.redo());
        assert_eq!(float_of(stack.current().unwrap()), 1.0);
        assert!(stack.goto(2));
        assert_eq!(float_of(stack.current().unwrap()), 2.0);
        assert!(!stack.goto(3));
        assert_eq!(stack.cursor_index(), 2);
        assert_eq!(stack.step(1).unwrap().label, "step-a");
        assert!(stack.step(9).is_none());
        assert_eq!(stack.len(), 3);
        assert!(!stack.is_empty());
    }

    #[test]
    fn history_drops_oldest_beyond_limit() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        for i in 0..205 {
            stack.commit(&format!("step-{i}"), settings_with_float(f64::from(i)));
        }
        assert_eq!(stack.len(), HISTORY_LIMIT);
        assert_eq!(stack.labels()[0], "step-5");
        assert_eq!(stack.cursor_index(), HISTORY_LIMIT - 1);
        assert_eq!(float_of(stack.current().unwrap()), 204.0);
        assert!(stack.undo());
        assert_eq!(float_of(stack.current().unwrap()), 203.0);
    }

    #[test]
    fn interaction_merges_many_updates_into_one_step() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        assert!(!stack.update_interaction(settings_with_float(9.0)));
        stack.begin_interaction("drag");
        assert!(stack.is_interaction_open());
        for value in [1.0, 2.0, 3.0] {
            assert!(stack.update_interaction(settings_with_float(value)));
            assert_eq!(float_of(stack.current().unwrap()), value);
        }
        assert_eq!(stack.len(), 1);
        stack.end_interaction();
        assert!(!stack.is_interaction_open());
        assert_eq!(stack.labels(), vec!["import", "drag"]);
        assert_eq!(float_of(stack.current().unwrap()), 3.0);
        assert!(stack.undo());
        assert_eq!(float_of(stack.current().unwrap()), 0.0);
    }

    #[test]
    fn interaction_end_without_change_commits_nothing() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        stack.begin_interaction("drag");
        stack.end_interaction();
        assert_eq!(stack.labels(), vec!["import"]);
        stack.end_interaction();
        assert_eq!(stack.len(), 1);
    }

    #[test]
    fn interaction_cancel_restores_prior_state() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        stack.commit("step-a", settings_with_float(1.0));
        stack.begin_interaction("drag");
        assert!(stack.update_interaction(settings_with_float(7.0)));
        assert_eq!(float_of(stack.current().unwrap()), 7.0);
        stack.cancel_interaction();
        assert!(!stack.is_interaction_open());
        assert_eq!(stack.labels(), vec!["import", "step-a"]);
        assert_eq!(float_of(stack.current().unwrap()), 1.0);
        stack.cancel_interaction();
        assert_eq!(float_of(stack.current().unwrap()), 1.0);
    }

    #[test]
    fn commit_during_interaction_ends_it_first() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        stack.begin_interaction("drag");
        assert!(stack.update_interaction(settings_with_float(5.0)));
        stack.commit("cmd", settings_with_float(6.0));
        assert_eq!(stack.labels(), vec!["import", "drag", "cmd"]);
        assert_eq!(float_of(stack.current().unwrap()), 6.0);
        assert!(stack.undo());
        assert_eq!(float_of(stack.current().unwrap()), 5.0);
    }

    #[test]
    fn begin_twice_ends_first_interaction() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        stack.begin_interaction("first");
        assert!(stack.update_interaction(settings_with_float(4.0)));
        stack.begin_interaction("second");
        assert_eq!(stack.labels(), vec!["import", "first"]);
        assert!(stack.update_interaction(settings_with_float(8.0)));
        stack.cancel_interaction();
        assert_eq!(float_of(stack.current().unwrap()), 4.0);
    }

    #[test]
    fn copy_keeps_target_process() {
        let mut source = PhotoSettings {
            process: ProcessVersion(999),
            ..PhotoSettings::default()
        };
        source.instances.upsert(ModuleInstance {
            module: "mod_c".to_owned(),
            multi: 0,
            name: None,
            enabled: true,
            params: [("p_int".to_owned(), SettingValue::Int(7))]
                .into_iter()
                .collect(),
        });
        let mut target = PhotoSettings::default();
        assert_eq!(target.process, ProcessVersion::V1);
        target.apply_copied(&source);
        assert_eq!(target.process, ProcessVersion::V1);
        assert_eq!(target.instances, source.instances);
    }

    #[test]
    fn batch_gives_each_photo_one_step_and_keeps_processes() {
        let source = settings_with_float(3.0);
        let batch = BatchAdjustments::from_settings(&source);
        let first = HistoryStack::new(settings_with_float(0.0));
        let older = PhotoSettings {
            process: ProcessVersion(999),
            ..PhotoSettings::default()
        };
        let second = HistoryStack::new(Arc::new(older));
        let mut stacks = vec![first, second];
        apply_batch(&mut stacks, &batch, "paste-all");
        assert_eq!(stacks.len(), 2);
        for stack in &stacks {
            assert_eq!(stack.len(), 2);
            assert_eq!(stack.labels(), vec!["import", "paste-all"]);
            assert_eq!(float_of(stack.current().unwrap()), 3.0);
        }
        assert_eq!(stacks[0].current().unwrap().process, ProcessVersion::V1);
        assert_eq!(stacks[1].current().unwrap().process, ProcessVersion(999));
    }

    #[test]
    fn batch_carrier_has_no_process_field() {
        let source = PhotoSettings {
            process: ProcessVersion(999),
            ..PhotoSettings::default()
        };
        let batch = BatchAdjustments::from_settings(&source);
        let value = serde_json::to_value(&batch).unwrap();
        assert!(value.get("process").is_none(), "{value}");
        assert!(value.get("instances").is_some(), "{value}");
    }

    #[test]
    fn undo_during_interaction_ends_it_first() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        stack.commit("step-a", settings_with_float(1.0));
        stack.begin_interaction("drag");
        assert!(stack.update_interaction(settings_with_float(5.0)));
        assert!(stack.undo());
        assert_eq!(stack.labels(), vec!["import", "step-a", "drag"]);
        assert_eq!(float_of(stack.current().unwrap()), 1.0);
        assert!(stack.redo());
        assert_eq!(float_of(stack.current().unwrap()), 5.0);
    }

    #[test]
    fn redo_and_goto_during_interaction_ends_it_first() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        stack.commit("step-a", settings_with_float(1.0));
        stack.commit("step-b", settings_with_float(2.0));
        assert!(stack.undo());
        stack.begin_interaction("drag");
        assert!(stack.update_interaction(settings_with_float(5.0)));
        assert!(!stack.redo());
        assert_eq!(stack.labels(), vec!["import", "step-a", "drag"]);
        assert_eq!(float_of(stack.current().unwrap()), 5.0);
        let mut moved = HistoryStack::new(settings_with_float(0.0));
        moved.commit("step-a", settings_with_float(1.0));
        moved.begin_interaction("drag");
        assert!(moved.update_interaction(settings_with_float(5.0)));
        assert!(moved.goto(0));
        assert_eq!(moved.labels(), vec!["import", "step-a", "drag"]);
        assert_eq!(float_of(moved.current().unwrap()), 0.0);
        assert!(!moved.goto(9));
    }

    #[test]
    fn initial_label_is_the_import_step() {
        assert_eq!(super::INITIAL_LABEL, "import");
        let stack = HistoryStack::new(settings_with_float(0.0));
        assert_eq!(stack.labels(), vec![super::INITIAL_LABEL]);
    }

    #[test]
    fn from_steps_rebuilds_exactly_the_stepwise_stack() {
        let mut stepwise = HistoryStack::new(settings_with_float(0.0));
        stepwise.commit("step-a", settings_with_float(1.0));
        stepwise.commit("step-b", settings_with_float(2.0));
        assert!(stepwise.goto(1));
        let stored: Vec<super::HistoryStep> = stepwise
            .labels()
            .into_iter()
            .enumerate()
            .map(|(index, label)| super::HistoryStep {
                label: label.to_owned(),
                settings: stepwise.step(index).unwrap().settings.clone(),
            })
            .collect();
        let rebuilt = HistoryStack::from_steps(stored, stepwise.cursor_index()).unwrap();
        assert_eq!(rebuilt, stepwise);
        assert_eq!(rebuilt.labels(), vec!["import", "step-a", "step-b"]);
        assert_eq!(rebuilt.cursor_index(), 1);
        assert!(!rebuilt.is_interaction_open());
    }

    #[test]
    fn from_steps_rejects_an_out_of_range_cursor() {
        let steps = vec![super::HistoryStep {
            label: "import".to_owned(),
            settings: settings_with_float(0.0),
        }];
        let err = HistoryStack::from_steps(steps, 1).unwrap_err();
        assert_eq!(
            err,
            super::RebuildError::CursorOutOfRange {
                cursor: 1,
                steps: 1
            }
        );
        assert_eq!(err.to_string(), "cursor 1 names no step of 1");
    }

    #[test]
    fn from_steps_rejects_empty_and_overflowing_steps() {
        assert_eq!(
            HistoryStack::from_steps(vec![], 0).unwrap_err(),
            super::RebuildError::Empty
        );
        let steps: Vec<super::HistoryStep> = (0..=HISTORY_LIMIT)
            .map(|_| super::HistoryStep {
                label: "step".to_owned(),
                settings: settings_with_float(0.0),
            })
            .collect();
        let err = HistoryStack::from_steps(steps, 0).unwrap_err();
        assert_eq!(
            err,
            super::RebuildError::TooMany {
                steps: HISTORY_LIMIT + 1,
                limit: HISTORY_LIMIT
            }
        );
    }

    #[test]
    fn pending_interaction_reports_only_a_changed_drag() {
        let mut stack = HistoryStack::new(settings_with_float(0.0));
        assert!(stack.pending_interaction().is_none());
        stack.begin_interaction("drag");
        assert!(stack.pending_interaction().is_none());
        assert!(stack.update_interaction(settings_with_float(5.0)));
        let pending = stack.pending_interaction();
        assert!(pending.is_some());
        let (label, live) = pending.unwrap();
        assert_eq!(label, "drag");
        assert_eq!(float_of(live), 5.0);
        stack.end_interaction();
        assert!(stack.pending_interaction().is_none());
    }
}

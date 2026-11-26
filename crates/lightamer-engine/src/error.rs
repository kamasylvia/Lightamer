// SPDX-License-Identifier: GPL-3.0-or-later
//! What is wrong with a command call: one typed error per failure mode.
//!
//! Every variant renders as one human-readable line (see [`Display`][std::fmt::Display]).
//! There is no catch-all: a new failure mode gets a new variant.

use std::fmt::{Display, Formatter, Result as FmtResult};

/// A failed [`Engine::execute`][crate::Engine::execute] call.
///
/// The variants pin down *why* the call failed; the engine state is unchanged
/// on every one of them (see the atomicity rule in the crate docs).
#[derive(Clone, Debug, PartialEq, Eq)]
#[allow(clippy::module_name_repetitions)]
// Public error names repeat the module by project convention (`CommandError`
// reads better at use sites than `Error`); the lint's rename would obscure it.
pub enum CommandError {
    /// No command is registered under this id.
    UnknownCommand {
        /// The id the caller asked for.
        cmd: String,
    },
    /// The params object holds a key this command does not declare.
    UnknownParam {
        /// The command that was called.
        cmd: String,
        /// The offending key.
        key: String,
    },
    /// A required parameter is absent.
    MissingParam {
        /// The command that was called.
        cmd: String,
        /// The absent parameter name.
        key: String,
    },
    /// A parameter has the wrong type or is out of range.
    BadParam {
        /// The command that was called.
        cmd: String,
        /// The parameter name (or path) at fault.
        key: String,
        /// Why the value is unacceptable.
        reason: String,
    },
    /// The command's enablement check refused to run it now.
    Disabled {
        /// The command that was called.
        cmd: String,
        /// Why it cannot run (from the command's own check).
        reason: String,
    },
    /// A session is required and none is open.
    NoSession {
        /// The command that was called.
        cmd: String,
    },
    /// The named photo is not in the open session.
    NoPhoto {
        /// The command that was called.
        cmd: String,
        /// The unknown photo id.
        photo: String,
    },
    /// The photo has no drag-merge interaction in progress.
    NoInteraction {
        /// The command that was called.
        cmd: String,
        /// The photo id.
        photo: String,
    },
    /// `develop.paste` with nothing copied yet.
    EmptyClipboard {
        /// The command that was called.
        cmd: String,
    },
    /// The named job is not in the job table.
    JobNotFound {
        /// The command that was called.
        cmd: String,
        /// The unknown job id.
        job: u64,
    },
    /// `execute` was called again from inside an event listener.
    Reentrant {
        /// The command the listener tried to run.
        cmd: String,
    },
}

impl Display for CommandError {
    fn fmt(&self, f: &mut Formatter<'_>) -> FmtResult {
        match self {
            CommandError::UnknownCommand { cmd } => write!(f, "unknown command '{cmd}'"),
            CommandError::UnknownParam { cmd, key } => {
                write!(f, "{cmd}: unknown parameter '{key}'")
            }
            CommandError::MissingParam { cmd, key } => {
                write!(f, "{cmd}: missing required parameter '{key}'")
            }
            CommandError::BadParam { cmd, key, reason } => {
                write!(f, "{cmd}: parameter '{key}': {reason}")
            }
            CommandError::Disabled { cmd, reason } => {
                write!(f, "{cmd}: cannot run now: {reason}")
            }
            CommandError::NoSession { cmd } => write!(f, "{cmd}: no session is open"),
            CommandError::NoPhoto { cmd, photo } => {
                write!(f, "{cmd}: no such photo '{photo}'")
            }
            CommandError::NoInteraction { cmd, photo } => {
                write!(f, "{cmd}: photo '{photo}' has no interaction in progress")
            }
            CommandError::EmptyClipboard { cmd } => write!(f, "{cmd}: the clipboard is empty"),
            CommandError::JobNotFound { cmd, job } => write!(f, "{cmd}: no such job {job}"),
            CommandError::Reentrant { cmd } => write!(
                f,
                "{cmd}: reentrant call from an event listener is not allowed"
            ),
        }
    }
}

impl std::error::Error for CommandError {}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use super::CommandError;

    #[test]
    fn every_variant_renders_one_readable_line() {
        let cases = [
            (
                CommandError::UnknownCommand {
                    cmd: "nope".to_owned(),
                },
                "unknown command 'nope'",
            ),
            (
                CommandError::UnknownParam {
                    cmd: "c".to_owned(),
                    key: "k".to_owned(),
                },
                "c: unknown parameter 'k'",
            ),
            (
                CommandError::MissingParam {
                    cmd: "c".to_owned(),
                    key: "k".to_owned(),
                },
                "c: missing required parameter 'k'",
            ),
            (
                CommandError::BadParam {
                    cmd: "c".to_owned(),
                    key: "k".to_owned(),
                    reason: "bad".to_owned(),
                },
                "c: parameter 'k': bad",
            ),
            (
                CommandError::Disabled {
                    cmd: "c".to_owned(),
                    reason: "why".to_owned(),
                },
                "c: cannot run now: why",
            ),
            (
                CommandError::NoSession {
                    cmd: "c".to_owned(),
                },
                "c: no session is open",
            ),
            (
                CommandError::NoPhoto {
                    cmd: "c".to_owned(),
                    photo: "p".to_owned(),
                },
                "c: no such photo 'p'",
            ),
            (
                CommandError::NoInteraction {
                    cmd: "c".to_owned(),
                    photo: "p".to_owned(),
                },
                "c: photo 'p' has no interaction in progress",
            ),
            (
                CommandError::EmptyClipboard {
                    cmd: "c".to_owned(),
                },
                "c: the clipboard is empty",
            ),
            (
                CommandError::JobNotFound {
                    cmd: "c".to_owned(),
                    job: 7,
                },
                "c: no such job 7",
            ),
            (
                CommandError::Reentrant {
                    cmd: "c".to_owned(),
                },
                "c: reentrant call from an event listener is not allowed",
            ),
        ];
        for (err, want) in cases {
            assert_eq!(err.to_string(), want, "{err:?}");
            assert!(!err.to_string().contains('\n'), "{err:?}");
        }
    }
}

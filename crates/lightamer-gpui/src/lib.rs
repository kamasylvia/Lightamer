// SPDX-License-Identifier: GPL-3.0-or-later
//! Viewport input data and its two conversions.
//!
//! [`ViewportInput`] is the UI crate's own pointer-event type: press, move,
//! release, and scroll in viewport-local logical points, with button,
//! modifiers, and timestamp. It is plain data; recognizing gestures and
//! issuing engine commands from it is a later wave's work.
//!
//! Two paths produce it, and both are real-measured: the framework's native
//! surface callback ([`convert_platform_input`]) and the native view subclass
//! in `lightamer-apple` ([`convert_native_input`]). Both conversions are pure
//! functions, tested here without opening any window.
#![deny(
    clippy::indexing_slicing,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::panic,
    clippy::todo,
    clippy::unimplemented
)]

use gpui_kit::{
    Modifiers, MouseButton, MouseDownEvent, MouseMoveEvent, MouseUpEvent, PlatformInput,
    ScrollDelta, ScrollEvent,
};
use lightamer_apple::{ModifierState as NativeModifiers, NativePointerEvent, NativePointerKind};

/// Pointer press/move/release/scroll inside the viewport.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputKind {
    /// Button pressed.
    Press,
    /// Pointer moved (drag state carried in [`ViewportInput::button`]).
    Move,
    /// Button released.
    Release,
    /// Wheel or trackpad scroll.
    Scroll,
}

impl InputKind {
    /// Short log word (`press`/`move`/`release`/`scroll`).
    #[must_use]
    pub const fn word(self) -> &'static str {
        match self {
            Self::Press => "press",
            Self::Move => "move",
            Self::Release => "release",
            Self::Scroll => "scroll",
        }
    }
}

/// Modifier key state at the time of a pointer event.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[allow(clippy::struct_excessive_bools)] // Four independent key facts; a bitflag would hide names.
pub struct InputModifiers {
    /// Shift held.
    pub shift: bool,
    /// Control held.
    pub control: bool,
    /// Option/Alt held.
    pub option: bool,
    /// Command held.
    pub command: bool,
}

/// One viewport pointer event, in viewport-local logical points.
#[derive(Debug, Clone, Copy)]
pub struct ViewportInput {
    /// What happened.
    pub kind: InputKind,
    /// Viewport-local x in logical points (origin top-left).
    pub x: f64,
    /// Viewport-local y in logical points (origin top-left).
    pub y: f64,
    /// Button number (`0` = primary; `None` for hover moves and scrolls).
    pub button: Option<u8>,
    /// Modifier state.
    pub modifiers: InputModifiers,
    /// Event timestamp in seconds (caller clock).
    pub timestamp_secs: f64,
    /// Scroll delta x in logical points (scrolls only).
    pub scroll_dx: f64,
    /// Scroll delta y in logical points (scrolls only).
    pub scroll_dy: f64,
}

/// Logical points per scroll line for line-based scroll deltas.
pub const LINE_SCROLL_POINTS: f64 = 16.0;

/// Maps a framework mouse button to our button number.
#[must_use]
pub const fn map_button(button: MouseButton) -> u8 {
    match button {
        MouseButton::Left => 0,
        MouseButton::Right => 1,
        MouseButton::Middle => 2,
        MouseButton::Navigate(_) => 3,
    }
}

/// Maps framework modifiers to ours (`platform` is Command).
#[must_use]
pub const fn map_modifiers(modifiers: &Modifiers) -> InputModifiers {
    InputModifiers {
        shift: modifiers.shift,
        control: modifiers.control,
        option: modifiers.alt,
        command: modifiers.platform,
    }
}

/// Converts one framework surface event to viewport-local input.
///
/// `origin` is the viewport's top-left in window content points; positions
/// arrive in window content points. `timestamp_secs` is stamped by the
/// caller (framework events carry no clock). Non-pointer events yield `None`.
#[must_use]
pub fn convert_platform_input(
    input: &PlatformInput,
    origin: (f64, f64),
    timestamp_secs: f64,
) -> Option<ViewportInput> {
    let local = |x: f64, y: f64| (x - origin.0, y - origin.1);
    match input {
        PlatformInput::MouseDown(MouseDownEvent {
            button,
            position,
            modifiers,
            ..
        }) => {
            let (x, y) = local(
                f64::from(position.x.as_f32()),
                f64::from(position.y.as_f32()),
            );
            Some(ViewportInput {
                kind: InputKind::Press,
                x,
                y,
                button: Some(map_button(*button)),
                modifiers: map_modifiers(modifiers),
                timestamp_secs,
                scroll_dx: 0.0,
                scroll_dy: 0.0,
            })
        }
        PlatformInput::MouseMove(MouseMoveEvent {
            position,
            pressed_button,
            modifiers,
        }) => {
            let (x, y) = local(
                f64::from(position.x.as_f32()),
                f64::from(position.y.as_f32()),
            );
            Some(ViewportInput {
                kind: InputKind::Move,
                x,
                y,
                button: (*pressed_button).map(map_button),
                modifiers: map_modifiers(modifiers),
                timestamp_secs,
                scroll_dx: 0.0,
                scroll_dy: 0.0,
            })
        }
        PlatformInput::MouseUp(MouseUpEvent {
            button,
            position,
            modifiers,
            ..
        }) => {
            let (x, y) = local(
                f64::from(position.x.as_f32()),
                f64::from(position.y.as_f32()),
            );
            Some(ViewportInput {
                kind: InputKind::Release,
                x,
                y,
                button: Some(map_button(*button)),
                modifiers: map_modifiers(modifiers),
                timestamp_secs,
                scroll_dx: 0.0,
                scroll_dy: 0.0,
            })
        }
        PlatformInput::Scroll(ScrollEvent {
            position,
            delta,
            modifiers,
            ..
        }) => {
            let (x, y) = local(
                f64::from(position.x.as_f32()),
                f64::from(position.y.as_f32()),
            );
            let (dx, dy) = match delta {
                ScrollDelta::Pixels(p) => (f64::from(p.x.as_f32()), f64::from(p.y.as_f32())),
                ScrollDelta::Lines(p) => (
                    f64::from(p.x) * LINE_SCROLL_POINTS,
                    f64::from(p.y) * LINE_SCROLL_POINTS,
                ),
            };
            Some(ViewportInput {
                kind: InputKind::Scroll,
                x,
                y,
                button: None,
                modifiers: map_modifiers(modifiers),
                timestamp_secs,
                scroll_dx: dx,
                scroll_dy: dy,
            })
        }
        _ => None,
    }
}

/// Converts one native-subclass event to our input (already viewport-local).
#[must_use]
pub fn convert_native_input(event: &NativePointerEvent) -> ViewportInput {
    let kind = match event.kind {
        NativePointerKind::Down => InputKind::Press,
        NativePointerKind::Move => InputKind::Move,
        NativePointerKind::Up => InputKind::Release,
        NativePointerKind::Scroll => InputKind::Scroll,
    };
    let NativeModifiers {
        shift,
        control,
        option,
        command,
    } = event.modifiers;
    ViewportInput {
        kind,
        x: event.x,
        y: event.y,
        button: event.button.and_then(|number| u8::try_from(number).ok()),
        modifiers: InputModifiers {
            shift,
            control,
            option,
            command,
        },
        timestamp_secs: event.timestamp_secs,
        scroll_dx: event.scroll_dx,
        scroll_dy: event.scroll_dy,
    }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]

    use super::*;
    use gpui_kit::{Pixels, Point};

    fn point(x: f32, y: f32) -> Point<Pixels> {
        Point {
            x: Pixels::from(x),
            y: Pixels::from(y),
        }
    }

    fn modifiers() -> Modifiers {
        Modifiers {
            control: false,
            alt: false,
            shift: false,
            platform: false,
            function: false,
        }
    }

    #[test]
    fn press_converts_with_origin_and_modifiers() {
        let event = PlatformInput::MouseDown(MouseDownEvent {
            button: MouseButton::Left,
            position: point(110.0, 60.0),
            modifiers: Modifiers {
                shift: true,
                platform: true,
                ..modifiers()
            },
            click_count: 1,
            first_mouse: false,
        });
        let input = convert_platform_input(&event, (100.0, 50.0), 3.5).unwrap();
        assert_eq!(input.kind, InputKind::Press);
        assert_eq!((input.x, input.y), (10.0, 10.0));
        assert_eq!(input.button, Some(0));
        assert_eq!(
            input.modifiers,
            InputModifiers {
                shift: true,
                control: false,
                option: false,
                command: true
            }
        );
        assert_eq!(input.timestamp_secs, 3.5);
        assert_eq!((input.scroll_dx, input.scroll_dy), (0.0, 0.0));
    }

    #[test]
    fn move_carries_optional_drag_button() {
        let hover = PlatformInput::MouseMove(MouseMoveEvent {
            position: point(5.0, 7.0),
            pressed_button: None,
            modifiers: modifiers(),
        });
        let input = convert_platform_input(&hover, (0.0, 0.0), 0.0).unwrap();
        assert_eq!(input.kind, InputKind::Move);
        assert_eq!(input.button, None);
        let drag = PlatformInput::MouseMove(MouseMoveEvent {
            position: point(5.0, 7.0),
            pressed_button: Some(MouseButton::Right),
            modifiers: modifiers(),
        });
        let input = convert_platform_input(&drag, (0.0, 0.0), 0.0).unwrap();
        assert_eq!(input.button, Some(1));
    }
    #[test]
    fn release_and_buttons_map() {
        let event = PlatformInput::MouseUp(MouseUpEvent {
            button: MouseButton::Middle,
            position: point(1.0, 2.0),
            modifiers: modifiers(),
            click_count: 1,
        });
        let input = convert_platform_input(&event, (0.0, 0.0), 0.0).unwrap();
        assert_eq!(input.kind, InputKind::Release);
        assert_eq!(input.button, Some(2));
        assert_eq!(map_button(MouseButton::Left), 0);
    }

    #[test]
    fn scroll_pixels_and_lines_scale() {
        let pixels = PlatformInput::Scroll(ScrollEvent {
            position: point(3.0, 4.0),
            delta: ScrollDelta::Pixels(point(10.0, -20.0)),
            modifiers: modifiers(),
            ..Default::default()
        });
        let input = convert_platform_input(&pixels, (0.0, 0.0), 0.0).unwrap();
        assert_eq!(input.kind, InputKind::Scroll);
        assert_eq!((input.scroll_dx, input.scroll_dy), (10.0, -20.0));
        assert_eq!(input.button, None);
        let lines = PlatformInput::Scroll(ScrollEvent {
            position: point(3.0, 4.0),
            delta: ScrollDelta::Lines(Point { x: 1.0, y: -2.0 }),
            modifiers: modifiers(),
            ..Default::default()
        });
        let input = convert_platform_input(&lines, (0.0, 0.0), 0.0).unwrap();
        assert_eq!((input.scroll_dx, input.scroll_dy), (16.0, -32.0));
    }

    #[test]
    fn non_pointer_events_yield_none() {
        let event = PlatformInput::MouseExited(gpui_kit::MouseExitEvent {
            position: point(0.0, 0.0),
            pressed_button: None,
            modifiers: modifiers(),
        });
        assert!(convert_platform_input(&event, (0.0, 0.0), 0.0).is_none());
    }

    #[test]
    fn native_events_convert_losslessly() {
        let event = NativePointerEvent {
            kind: NativePointerKind::Scroll,
            x: 12.5,
            y: 40.0,
            button: Some(0),
            modifiers: NativeModifiers {
                shift: false,
                control: true,
                option: true,
                command: false,
            },
            timestamp_secs: 9.25,
            scroll_dx: 3.0,
            scroll_dy: -6.0,
        };
        let input = convert_native_input(&event);
        assert_eq!(input.kind, InputKind::Scroll);
        assert_eq!((input.x, input.y), (12.5, 40.0));
        assert_eq!(input.button, Some(0));
        assert_eq!(
            input.modifiers,
            InputModifiers {
                shift: false,
                control: true,
                option: true,
                command: false
            }
        );
        assert_eq!(input.timestamp_secs, 9.25);
        assert_eq!((input.scroll_dx, input.scroll_dy), (3.0, -6.0));
        let down = NativePointerEvent {
            kind: NativePointerKind::Down,
            ..event
        };
        assert_eq!(convert_native_input(&down).kind, InputKind::Press);
        let moved = NativePointerEvent {
            kind: NativePointerKind::Move,
            ..event
        };
        assert_eq!(convert_native_input(&moved).kind, InputKind::Move);
        let hover = NativePointerEvent {
            kind: NativePointerKind::Move,
            button: None,
            ..event
        };
        assert_eq!(convert_native_input(&hover).button, None);
        let up = NativePointerEvent {
            kind: NativePointerKind::Up,
            button: Some(999),
            ..event
        };
        let input = convert_native_input(&up);
        assert_eq!(input.kind, InputKind::Release);
        assert_eq!(input.button, None);
    }

    #[test]
    fn kind_words_log_clean() {
        assert_eq!(InputKind::Press.word(), "press");
        assert_eq!(InputKind::Move.word(), "move");
        assert_eq!(InputKind::Release.word(), "release");
        assert_eq!(InputKind::Scroll.word(), "scroll");
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
//! Format negotiation: where colorspace conversions belong.
//!
//! Each node declares its input/output spaces; the plan inserts one
//! conversion between neighbors that disagree. B1-a plans only — the
//! conversions themselves land with the color trio in B5.

use lightamer_iop_traits::ColorSpace;

use super::chain::CommittedNode;

/// One planned conversion: after node `after`, convert `from` to `to`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ColorStep {
    /// Index of the node whose output is converted.
    pub after: usize,
    /// The node's output space.
    pub from: ColorSpace,
    /// The next node's input space.
    pub to: ColorSpace,
}

/// The conversion plan for a chain: zero or more [`ColorStep`]s.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ColorPlan {
    /// Steps in execution order.
    pub steps: Vec<ColorStep>,
}

/// Negotiates conversions for a committed chain.
#[must_use]
pub fn negotiate(chain: &[CommittedNode]) -> ColorPlan {
    let mut steps = Vec::new();
    let mut prev_out: Option<ColorSpace> = None;
    for (index, node) in chain.iter().enumerate() {
        let (input, output) = node.module.colorspaces();
        if let Some(from) = prev_out
            && from != input
        {
            steps.push(ColorStep {
                after: index - 1,
                from,
                to: input,
            });
        }
        prev_out = Some(output);
    }
    ColorPlan { steps }
}

#[cfg(test)]
mod tests {
    #![allow(clippy::indexing_slicing, clippy::unwrap_used, clippy::expect_used)]
    use std::sync::Arc;

    use lightamer_iop_traits::{ColorSpace, ImageInfo, PipeKind, PipeState};

    use super::{ColorStep, negotiate};
    use crate::chain::PipeNode;
    use crate::fakes::{FakeScale, no_params, table};

    fn image() -> ImageInfo {
        ImageInfo::new(64, 64, ColorSpace::Rgb)
    }

    fn node(id: &str) -> PipeNode {
        PipeNode {
            id: id.to_owned(),
            multi: 0,
            params: no_params(),
        }
    }

    #[test]
    fn uniform_chain_plans_zero_conversions() {
        let lookup = table(vec![
            Arc::new(FakeScale::new("mod_c0", 1, 1).with_colors(ColorSpace::Lab, ColorSpace::Lab)),
            Arc::new(FakeScale::new("mod_c1", 1, 1).with_colors(ColorSpace::Lab, ColorSpace::Lab)),
            Arc::new(FakeScale::new("mod_c2", 1, 1).with_colors(ColorSpace::Lab, ColorSpace::Lab)),
        ]);
        let chain = crate::chain::build_chain(
            &lookup,
            &[node("mod_c0"), node("mod_c1"), node("mod_c2")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        assert_eq!(negotiate(&chain).steps, Vec::new());
        assert_eq!(negotiate(&[]).steps, Vec::new());
        assert_eq!(negotiate(&chain[..1]).steps, Vec::new());
    }

    #[test]
    fn one_boundary_yields_exactly_one_step() {
        let lookup = table(vec![
            Arc::new(FakeScale::new("mod_c0", 1, 1).with_colors(ColorSpace::Rgb, ColorSpace::Rgb)),
            Arc::new(FakeScale::new("mod_c1", 1, 1).with_colors(ColorSpace::Lab, ColorSpace::Lab)),
        ]);
        let chain = crate::chain::build_chain(
            &lookup,
            &[node("mod_c0"), node("mod_c1")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        let plan = negotiate(&chain);
        assert_eq!(
            plan.steps,
            vec![ColorStep {
                after: 0,
                from: ColorSpace::Rgb,
                to: ColorSpace::Lab
            }]
        );
    }

    #[test]
    fn every_step_carries_from_and_to() {
        let lookup = table(vec![
            Arc::new(FakeScale::new("mod_c0", 1, 1).with_colors(ColorSpace::Rgb, ColorSpace::Lab)),
            Arc::new(FakeScale::new("mod_c1", 1, 1).with_colors(ColorSpace::Rgb, ColorSpace::Hsl)),
            Arc::new(FakeScale::new("mod_c2", 1, 1).with_colors(ColorSpace::Lab, ColorSpace::Lab)),
        ]);
        let chain = crate::chain::build_chain(
            &lookup,
            &[node("mod_c0"), node("mod_c1"), node("mod_c2")],
            &image(),
            &mut PipeState::from_image(&image()),
            PipeKind::Full,
        )
        .unwrap();
        let plan = negotiate(&chain);
        assert_eq!(
            plan.steps,
            vec![
                ColorStep {
                    after: 0,
                    from: ColorSpace::Lab,
                    to: ColorSpace::Rgb
                },
                ColorStep {
                    after: 1,
                    from: ColorSpace::Hsl,
                    to: ColorSpace::Lab
                },
            ]
        );
    }
}

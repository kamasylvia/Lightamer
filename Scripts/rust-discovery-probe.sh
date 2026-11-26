#!/bin/bash
# rust-discovery-probe.sh — 加目录即被发现的机检（T4 的 zz_probe，两方向）。
# 用法：Scripts/rust-discovery-probe.sh
#   方向 present：在 dt-iop-display 里造 zz_probe 目录，断言 registry 里有它；
#   方向 absent：删掉目录，断言没有。跑完工作区恢复原样（trap 兜底）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$ROOT/crates/dt-iop-display/src/modules/zz_probe"

cleanup() { rm -rf "$PROBE"; }
trap cleanup EXIT

echo "rust-discovery-probe: direction present (create $PROBE)"
mkdir -p "$PROBE"
cat > "$PROBE/mod.rs" <<'EOF'
// SPDX-License-Identifier: GPL-3.0-or-later
//! Temporary discovery probe (removed after the probe run).

/// Probe descriptor.
pub static DESC: ::dt_iop_traits::ModuleDesc = ::dt_iop_traits::ModuleDesc::stub(
    "zz_probe",
    ::dt_iop_traits::OrderKey { priority: 999.0, tie: 999 },
    ::dt_iop_traits::OrderKey { priority: 999.0, tie: 999 },
);
EOF
(cd "$ROOT" && DT_DISCOVERY_PROBE=present cargo test -p dt-registry --locked -j6 --test discovery_probe)
echo "rust-discovery-probe: present PASS"

echo "rust-discovery-probe: direction absent (remove $PROBE)"
rm -rf "$PROBE"
(cd "$ROOT" && DT_DISCOVERY_PROBE=absent cargo test -p dt-registry --locked -j6 --test discovery_probe)
echo "rust-discovery-probe: absent PASS"

trap - EXIT
if [ -e "$PROBE" ]; then
  echo "rust-discovery-probe: ERROR: probe dir still exists: $PROBE" >&2
  exit 1
fi
if git -C "$ROOT" status --porcelain -- crates/dt-iop-display/src/modules | grep -q zz_probe; then
  echo "rust-discovery-probe: ERROR: probe residue in git status" >&2
  exit 1
fi
echo "rust-discovery-probe: ALL GREEN (workspace restored)"

// SPDX-License-Identifier: GPL-3.0-or-later
// Glue: includes the shim plus the verbatim rawprepare fragments in
// dependency order (leaf statics before their callers).
#include "dt_shim.h"

#include "dng_gainmap_struct.inc"
#include "rawprepare_types.inc"
#include "rawprepare_crop.inc"
#include "rawprepare_cfa.inc"
#include "rawprepare_normalized.inc"
#include "rawprepare_rawcrops.inc"
#include "rawprepare_gainmaps.inc"
#include "rawprepare_process.inc"
#include "rawprepare_commit.inc"
#include "rawprepare_pipe.inc"
#include "rawprepare_defaults.inc"
#include "rawprepare_roi.inc"

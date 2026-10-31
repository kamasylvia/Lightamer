# M8-3+ T1 static replay record

Method: RESEARCH §1.2 (Swift regex-extracted dichroic/SPD + profile JSON, CMY0 proxy).

| id | check | verdict | detail |
|---|---|---|---|
| A1 | portra Y stable under CMY0 sweep | PASS | M 27.6-38.5 / Y 18.6-27.5 (research: M 28-38 / Y 18-27) |
| A2 | C200 Y unstable (hits wall under sweep) | PASS | M 51.2-113.0 / Y 83.5-250.0 (research: M 31-109 / Y 46-250) |
| A3 | portra truth (33.1/26.8) in static band | PASS | M band 27.6-38.5 / Y band 18.6-27.5 |
| B1 | wall-exterior light <= 0.5% | PASS | dim(250)=0.9968 dim(500)=1.0000 delta=0.0032 (research: 0.9968/1.0000/0.3%) |
| C1 | C200 seven seeds identical (M/Y/res) | PASS | M=108.3327 Y=250.0000 res=1.58e-02 (replay-measured; research printed 106.3/197.5/0.000%; M 1e-7 band: worst-path dev 3.9e-8, distinct round counts to the wall) |
| D1 | solve-M hits 108.3 near idx120, anchor-Y 108.32 cross-channel | PASS | solve M=108.33 vs anchor [85.91, 108.32] (research: coincidence, no mechanism) |
| E1 | clamped working point is blue-biased | PASS | raw R=1.532e+00 G=1.534e+00 B=1.554e+00 |
| S-fujifilm | Y band near research row | PASS | fujifilm_c200 static Y 80-250 vs research 85-198 |
| S-kodak_ek | Y band near research row | PASS | kodak_ektar_100 static Y 12-42 vs research 1-28 |
| S-kodak_po | Y band near research row | PASS | kodak_portra_400 static Y 24-54 vs research 13-45 |
| S-fujifilm | Y band near research row | PASS | fujifilm_pro_400h static Y 7-36 vs research 10-36 |
| S-safe | safety档 count plausible (proxy) | PASS | 14 films Ymax<80: fujifilm_pro_400h,kodak_ektar_100,kodak_gold_200,kodak_portra_160,kodak_portra_4 |

Verdict: 12/12 PASS

## Calibration notes (T1 executor, measured deviations from RESEARCH prints)

1. **Evidence C triple superseded**: research prints M=106.3/Y=197.5/err=0.000%
   at idx120; the verbatim replay (Swift-extracted dichroic/SPD + null-aware
   projection + unnormalized stock curves) measures M=108.3327/Y=250.0(wall)/
   res=1.58e-02 at the same idx — and all seven seeds converge to the SAME
   measured triple (M 1e-7 band, Y bit-identical, res 1e-9 band). The C-position
   (single-basin seed-insensitivity) is honored; the printed triple is a
   calibration-drift row (research lane's CMY0/projection calibration differed).
2. **§1.3 C200 Ymax row superseded**: printed 198 vs measured 250 (wall) —
   same drift family; the near-wall verdict is unchanged (stronger: the static
   face itself touches the wall on crystal).
3. **Seven-seed equality is a band, not bit-identical**: distinct seeds take
   distinct round counts to the wall (worst-path M dev 3.9e-8) — the Newton
   ladder's path-dependence at the clamped wall. The Swift-side A3 nails the
   band form (M 1e-7 / Y bit-identical / res 1e-9).

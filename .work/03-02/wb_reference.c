/*
 * wb_reference.c — Plan 03-02-T1: dt-side reference values for the WB
 * Kelvin→XYZ math, computed from the ACTUAL darktable source pieces:
 *   - the verbatim copy of temperature.c's four helpers (_spd_blackbody,
 *     _spd_daylight, _spectrum_to_XYZ, _temperature_to_XYZ) below,
 *   - the verbatim CIE tables via #include of darktable's
 *     src/external/cie_colorimetric_tables.c,
 *   - lcms2's cmsWhitePointFromTemp linked from Homebrew (the same lib dt
 *     links).
 * Compile+run once; the printed values are recorded as known vectors in
 * CPUDerivationTests (WB section). Not a build artifact of the app.
 *
 *   clang .work/03-02/wb_reference.c -o /tmp/wbref \
 *     -I/opt/homebrew/include -L/opt/homebrew/lib -llcms2 && /tmp/wbref
 */
#include <math.h>
#include <stdio.h>
#include <lcms2.h>

/* darktable tree (ported reference): src/external/cie_colorimetric_tables.c */
#include "/Volumes/UNITEK/Documents/Development/darktable/src/external/cie_colorimetric_tables.c"

/* ── temperature.c:287-341 verbatim (blackbody + daylight SPDs) ───────── */

#define INITIALBLACKBODYTEMPERATURE 400

static double _spd_blackbody(unsigned long int wavelength, double TempK)
{
  const long double lambda = (double)wavelength * 1e-9;
#define c1 3.7417715246641281639549488324352159753e-16L
#define c2 0.014387769599838156481252937624049081933L
  return (double)(c1 / (powl(lambda, 5) * (expl(c2 / (lambda * TempK)) - 1.0L)));
#undef c2
#undef c1
}

static double _spd_daylight(unsigned long int wavelength, double TempK)
{
  cmsCIExyY WhitePoint = { 0.3127, 0.3290, 1.0 };
  cmsWhitePointFromTemp(&WhitePoint, TempK);

  const double M = (0.0241 + 0.2562 * WhitePoint.x - 0.7341 * WhitePoint.y),
               m1 = (-1.3515 - 1.7703 * WhitePoint.x + 5.9114 * WhitePoint.y) / M,
               m2 = (0.0300 - 31.4424 * WhitePoint.x + 30.0717 * WhitePoint.y) / M;

  const unsigned long int j
      = ((wavelength - cie_daylight_components[0].wavelength)
         / (cie_daylight_components[1].wavelength
            - cie_daylight_components[0].wavelength));

  return (cie_daylight_components[j].S[0] + m1 * cie_daylight_components[j].S[1]
          + m2 * cie_daylight_components[j].S[2]);
}

/* ── temperature.c:345-386 verbatim (SPD→XYZ integral + max normalize) ── */

static cmsCIEXYZ _spectrum_to_XYZ(double TempK, double (*I)(unsigned long, double))
{
  cmsCIEXYZ Source = { .X = 0.0, .Y = 0.0, .Z = 0.0 };

  for (size_t i = 0; i < cie_1931_std_colorimetric_observer_count; i++) {
    const unsigned long int lambda =
        cie_1931_std_colorimetric_observer[0].wavelength
        + (cie_1931_std_colorimetric_observer[1].wavelength
           - cie_1931_std_colorimetric_observer[0].wavelength) * i;

    const double P = I(lambda, TempK);
    Source.X += P * cie_1931_std_colorimetric_observer[i].xyz.X;
    Source.Y += P * cie_1931_std_colorimetric_observer[i].xyz.Y;
    Source.Z += P * cie_1931_std_colorimetric_observer[i].xyz.Z;
  }

  const double _max = fmax(fmax(Source.X, Source.Y), Source.Z);
  Source.X /= _max;
  Source.Y /= _max;
  Source.Z /= _max;

  return Source;
}

static cmsCIEXYZ _temperature_to_XYZ(double TempK)
{
  if (TempK < 1901) TempK = 1901;
  if (TempK > 25000) TempK = 25000;
  if (TempK < 4000) return _spectrum_to_XYZ(TempK, _spd_blackbody);
  return _spectrum_to_XYZ(TempK, _spd_daylight);
}

int main(void)
{
  const double temps[] = { 1901.0, 2500.0, 3200.0, 3999.0, 4000.0,
                           5000.0, 6500.0, 6504.0, 10000.0, 25000.0 };
  for (unsigned t = 0; t < sizeof(temps) / sizeof(temps[0]); t++) {
    cmsCIEXYZ xyz = _temperature_to_XYZ(temps[t]);
    /* chromaticity + Rec2020 white-check trace */
    const double s = xyz.X + xyz.Y + xyz.Z;
    printf("K=%7.1f  XYZ=(%.15f, %.15f, %.15f)  xy=(%.12f, %.12f)\n",
           temps[t], xyz.X, xyz.Y, xyz.Z, xyz.X / s, xyz.Y / s);
  }

  /* lcms white point trace (what the daylight SPD targets) */
  for (unsigned t = 0; t < sizeof(temps) / sizeof(temps[0]); t++) {
    if (temps[t] < 4000) continue;
    cmsCIExyY wp = { 0.3127, 0.3290, 1.0 };
    cmsWhitePointFromTemp(&wp, temps[t]);
    printf("lcms K=%7.1f  x=%.15f y=%.15f\n", temps[t], wp.x, wp.y);
  }
  return 0;
}

# Audio Analyzer License

Unless a file states otherwise, Audio Analyzer is distributed under the
**GNU General Public License, version 2.0 only (GPL-2.0-only)**.

The analysis core includes code derived from Mixxx and QM-DSP. Mixxx is
licensed under GPLv2, and the QM-DSP files include permission under GPLv2 or
later. Therefore, this project is distributed under GPLv2-only rather than a
permissive license or GPLv3. Copyright notices and licenses for vendored files
must be preserved.

KissFFT is an independent third-party component: its files remain under their
BSD-style license and are not relicensed under the GPL. The ReplayGain
analysis (`ReplayGainAnalyzer`, ITU-R BS.1770) follows the design of
libebur128, whose MIT license is GPL-compatible and likewise preserved. The
complete license texts are included with the source code:

- QM-DSP GPLv2:
  [`QM-DSP-COPYING.txt`](Audio%20Analyzer/Services/Analysis/Core/Vendor/qm-dsp/QM-DSP-COPYING.txt)
- KissFFT BSD-style license:
  [`KissFFT-COPYING.txt`](Audio%20Analyzer/Services/Analysis/Core/Vendor/qm-dsp/ext/kissfft/KissFFT-COPYING.txt)
- libebur128 MIT license (ReplayGain analysis):
  [`LIBEBUR128-LICENSE.md`](Audio%20Analyzer/Services/Analysis/Core/LIBEBUR128-LICENSE.md)
- Third-party notices and attribution:
  [`THIRD_PARTY_NOTICES.md`](Audio%20Analyzer/THIRD_PARTY_NOTICES.md)

When distributing a binary that includes GPL code, the GPL conditions must be
met, including making the corresponding source code and this license text
available. This information is not legal advice.

## GNU General Public License, version 2

The complete license applicable to the GPL code is included verbatim in
[`QM-DSP-COPYING.txt`](Audio%20Analyzer/Services/Analysis/Core/Vendor/qm-dsp/QM-DSP-COPYING.txt)
and is also available from the official [Free Software Foundation] website.
Its conditions include preserving copyright and license notices, identifying
modifications, and providing the corresponding source code when distributing
executables.

[Free Software Foundation]: https://www.gnu.org/licenses/old-licenses/gpl-2.0.html

## KissFFT BSD-style license

The complete license applicable to the KissFFT files is included verbatim in
[`KissFFT-COPYING.txt`](Audio%20Analyzer/Services/Analysis/Core/Vendor/qm-dsp/ext/kissfft/KissFFT-COPYING.txt).
In short, it permits redistribution of source and binary code, with or
without modification, provided that its notices, conditions, and disclaimer
are retained and its authors' names are not used for promotion without prior
permission.

## libebur128 MIT license

The complete license applicable to the ReplayGain analysis design is included
verbatim in
[`LIBEBUR128-LICENSE.md`](Audio%20Analyzer/Services/Analysis/Core/LIBEBUR128-LICENSE.md).
In short, it permits use, modification, and distribution, provided that its
copyright and permission notices are retained.

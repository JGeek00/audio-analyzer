# Third-party notices

The required QM-DSP and KissFFT subset is vendored under `Services/Analysis/Core/Vendor/qm-dsp`. It follows the implementations used by the upstream [Mixxx repository](https://github.com/mixxxdj/mixxx), including the tempo-tracking and `qm-keydetector:2` key-detection paths. Preserve the copyright notices and license texts included with the vendored source.

- [Mixxx GPL v2 notice](https://github.com/mixxxdj/mixxx/blob/main/COPYING)
- [Mixxx license](https://github.com/mixxxdj/mixxx/blob/main/LICENSE)
- [QM-DSP GPL notice](https://github.com/mixxxdj/mixxx/blob/main/lib/qm-dsp/COPYING)
- [KissFFT license](https://github.com/mixxxdj/mixxx/blob/main/lib/qm-dsp/ext/kissfft/COPYING)

## ReplayGain analysis

`Services/Analysis/Core/ReplayGainAnalyzer` implements ITU-R BS.1770
integrated loudness for ReplayGain 2.0 track gain. Its filter design and
gating procedure follow [libebur128](https://github.com/jiixyj/libebur128) by
Jan Kokemüller (MIT, GPL-compatible); no libebur128 source is vendored, but
the license is preserved in
[`Services/Analysis/Core/LIBEBUR128-LICENSE.md`](Services/Analysis/Core/LIBEBUR128-LICENSE.md).

Behavioral references (no code copied):

- [rsgain](https://github.com/complexlogic/rsgain) for gain, clipping-protection, and tag conventions
- [ReplayGain 2.0 specification](https://wiki.hydrogenaudio.org/index.php?title=Revised_ReplayGain_specification) for tag names and value formats
- [ITU-R BS.1770](https://www.itu.int/rec/R-REC-BS.1770) for the loudness algorithm

Review the licensing obligations before distribution. In particular, confirm that the vendored upstream-derived source, modified files, copyright notices, and applicable license texts are distributed as required.

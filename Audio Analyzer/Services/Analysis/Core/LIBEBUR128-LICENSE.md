# libebur128 license (ReplayGain analysis)

`ReplayGainAnalyzer.h` / `ReplayGainAnalyzer.cpp` in this directory implement
an ITU-R BS.1770 (EBU R128) integrated-loudness measurement for ReplayGain 2.0
track gain. The K-weighting filter design and the gating procedure follow
[libebur128](https://github.com/jiixyj/libebur128) by Jan Kokemüller. No
libebur128 source code is vendored here; the design is reimplemented, but the
MIT license below is preserved to cover the derivation, as the license
requires for substantial portions.

Behavioral reference (no code copied): [rsgain](https://github.com/complexlogic/rsgain)
(BSD-2-Clause) for gain/clipping/tag conventions, the [ReplayGain 2.0
specification](https://wiki.hydrogenaudio.org/index.php?title=Revised_ReplayGain_specification),
and [ITU-R BS.1770](https://www.itu.int/rec/R-REC-BS.1770).

The MIT license is GPL-compatible, so the project as a whole remains
distributed under GPL-2.0-only (see the root `LICENSE.md`).

## MIT license text (libebur128)

Copyright (c) 2011 Jan Kokemüller

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

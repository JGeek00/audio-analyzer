/* -*- c-basic-offset: 4 indent-tabs-mode: nil -*-  vi:set ts=8 sts=4 sw=4: */

/*
    QM DSP Library

    Centre for Digital Music, Queen Mary, University of London.

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation; either version 2 of the
    License, or (at your option) any later version.  See the file
    COPYING included with this distribution for more information.
*/

#ifndef QM_DSP_FFT_H
#define QM_DSP_FFT_H

class FFT
{
public:
    FFT(int nsamples);
    ~FFT();
    void process(bool inverse, const double* realIn, const double* imagIn,
            double* realOut, double* imagOut);

private:
    class D;
    D* m_d;
};

class FFTReal
{
public:
    FFTReal(int nsamples);
    ~FFTReal();
    void forward(const double* realIn, double* realOut, double* imagOut);
    void forwardMagnitude(const double* realIn, double* magOut);
    void inverse(const double* realIn, const double* imagIn, double* realOut);

private:
    class D;
    D* m_d;
};

#endif

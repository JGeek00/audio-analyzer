/* -*- c-basic-offset: 4 indent-tabs-mode: nil -*-  vi:set ts=8 sts=4 sw=4: */

/*
    QM DSP Library

    Centre for Digital Music, Queen Mary, University of London.
    This file 2005-2006 Christian Landone, copyright 2013 QMUL.

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation; either version 2 of the
    License, or (at your option) any later version.  See the file
    COPYING included with this distribution for more information.
*/

#ifndef QM_DSP_PHASEVOCODER_H
#define QM_DSP_PHASEVOCODER_H

class FFTReal;

class PhaseVocoder
{
public:
    PhaseVocoder(int size, int hop);
    virtual ~PhaseVocoder();
    void processTimeDomain(const double* src, double* mag, double* phase, double* unwrapped);
    void processFrequencyDomain(const double* reals, const double* imags,
            double* mag, double* phase, double* unwrapped);
    void reset();

protected:
    void FFTShift(double* src);
    void getMagnitudes(double* mag);
    void getPhases(double* theta);
    void unwrapPhases(double* theta, double* unwrapped);

    int m_n;
    int m_hop;
    FFTReal* m_fft;
    double* m_time;
    double* m_imag;
    double* m_real;
    double* m_phase;
    double* m_unwrapped;
};

#endif

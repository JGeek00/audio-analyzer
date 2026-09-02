/*
    QM DSP Library
    Centre for Digital Music, Queen Mary, University of London.

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation; either version 2 of the
    License, or (at your option) any later version.  See the file
    COPYING included with this distribution for more information.
*/

#include "FFT.h"
#include "../../maths/MathUtilities.h"
#include "../../ext/kissfft/kiss_fft.h"
#include "../../ext/kissfft/tools/kiss_fftr.h"

#include <cmath>
#include <stdexcept>

class FFT::D {
public:
    D(int n) : m_n(n) {
        m_planf = kiss_fft_alloc(m_n, 0, NULL, NULL);
        m_plani = kiss_fft_alloc(m_n, 1, NULL, NULL);
        m_kin = new kiss_fft_cpx[m_n];
        m_kout = new kiss_fft_cpx[m_n];
    }

    ~D() {
        kiss_fft_free(m_planf);
        kiss_fft_free(m_plani);
        delete[] m_kin;
        delete[] m_kout;
    }

    void process(bool inverse, const double* ri, const double* ii,
            double* ro, double* io) {
        for (int i = 0; i < m_n; ++i) {
            m_kin[i].r = ri[i];
            m_kin[i].i = ii ? ii[i] : 0.0;
        }

        if (!inverse) {
            kiss_fft(m_planf, m_kin, m_kout);
            for (int i = 0; i < m_n; ++i) {
                ro[i] = m_kout[i].r;
                io[i] = m_kout[i].i;
            }
        } else {
            kiss_fft(m_plani, m_kin, m_kout);
            const double scale = 1.0 / m_n;
            for (int i = 0; i < m_n; ++i) {
                ro[i] = m_kout[i].r * scale;
                io[i] = m_kout[i].i * scale;
            }
        }
    }

private:
    int m_n;
    kiss_fft_cfg m_planf;
    kiss_fft_cfg m_plani;
    kiss_fft_cpx* m_kin;
    kiss_fft_cpx* m_kout;
};

FFT::FFT(int n) : m_d(new D(n)) { }
FFT::~FFT() { delete m_d; }

void FFT::process(bool inverse, const double* realIn, const double* imagIn,
        double* realOut, double* imagOut) {
    m_d->process(inverse, realIn, imagIn, realOut, imagOut);
}

class FFTReal::D {
public:
    D(int n) : m_n(n) {
        if (n % 2) {
            throw std::invalid_argument("nsamples must be even in FFTReal constructor");
        }
        m_planf = kiss_fftr_alloc(m_n, 0, NULL, NULL);
        m_plani = kiss_fftr_alloc(m_n, 1, NULL, NULL);
        m_c = new kiss_fft_cpx[m_n];
    }

    ~D() {
        kiss_fftr_free(m_planf);
        kiss_fftr_free(m_plani);
        delete[] m_c;
    }

    void forward(const double* ri, double* ro, double* io) {
        kiss_fftr(m_planf, ri, m_c);
        for (int i = 0; i <= m_n / 2; ++i) {
            ro[i] = m_c[i].r;
            io[i] = m_c[i].i;
        }
        for (int i = 0; i + 1 < m_n / 2; ++i) {
            ro[m_n - i - 1] = ro[i + 1];
            io[m_n - i - 1] = -io[i + 1];
        }
    }

    void forwardMagnitude(const double* ri, double* mo) {
        double* io = new double[m_n];
        forward(ri, mo, io);
        for (int i = 0; i < m_n; ++i) {
            mo[i] = sqrt(mo[i] * mo[i] + io[i] * io[i]);
        }
        delete[] io;
    }

    void inverse(const double* ri, const double* ii, double* ro) {
        for (int i = 0; i < m_n / 2 + 1; ++i) {
            m_c[i].r = ri[i];
            m_c[i].i = ii[i];
        }
        kiss_fftri(m_plani, m_c, ro);
        const double scale = 1.0 / m_n;
        for (int i = 0; i < m_n; ++i) ro[i] *= scale;
    }

private:
    int m_n;
    kiss_fftr_cfg m_planf;
    kiss_fftr_cfg m_plani;
    kiss_fft_cpx* m_c;
};

FFTReal::FFTReal(int n) : m_d(new D(n)) { }
FFTReal::~FFTReal() { delete m_d; }

void FFTReal::forward(const double* realIn, double* realOut, double* imagOut) {
    m_d->forward(realIn, realOut, imagOut);
}

void FFTReal::forwardMagnitude(const double* realIn, double* magOut) {
    m_d->forwardMagnitude(realIn, magOut);
}

void FFTReal::inverse(const double* realIn, const double* imagIn, double* realOut) {
    m_d->inverse(realIn, imagIn, realOut);
}

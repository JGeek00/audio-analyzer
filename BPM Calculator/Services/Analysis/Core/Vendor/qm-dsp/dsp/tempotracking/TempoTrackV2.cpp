/*
    QM DSP Library

    This file copyright 2008-2009 Matthew Davies and QMUL.

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation; either version 2 of the
    License, or (at your option) any later version.  See the file
    COPYING included with this distribution for more information.
*/

#include "TempoTrackV2.h"

#include <cmath>
#include <cstdlib>

#include "../../maths/MathUtilities.h"

using std::vector;

#define EPS 0.0000008

TempoTrackV2::TempoTrackV2(float rate, int increment)
        : m_rate(rate), m_increment(increment) {
}

TempoTrackV2::~TempoTrackV2() { }

void TempoTrackV2::filter_df(d_vec_t& df) {
    const int df_len = int(df.size());
    d_vec_t a(3);
    d_vec_t b(3);
    d_vec_t lp_df(df_len);
    a[0] = 1.0000;
    a[1] = -0.3695;
    a[2] = 0.1958;
    b[0] = 0.2066;
    b[1] = 0.4131;
    b[2] = 0.2066;

    double inp1 = 0.;
    double inp2 = 0.;
    double out1 = 0.;
    double out2 = 0.;
    for (int i = 0; i < df_len; i++) {
        lp_df[i] = b[0] * df[i] + b[1] * inp1 + b[2] * inp2 -
                a[1] * out1 - a[2] * out2;
        inp2 = inp1;
        inp1 = df[i];
        out2 = out1;
        out1 = lp_df[i];
    }
    for (int i = 0; i < df_len; i++) df[i] = lp_df[df_len - i - 1];
    for (int i = 0; i < df_len; i++) lp_df[i] = 0.;

    inp1 = 0.;
    inp2 = 0.;
    out1 = 0.;
    out2 = 0.;
    for (int i = 0; i < df_len; i++) {
        lp_df[i] = b[0] * df[i] + b[1] * inp1 + b[2] * inp2 -
                a[1] * out1 - a[2] * out2;
        inp2 = inp1;
        inp1 = df[i];
        out2 = out1;
        out1 = lp_df[i];
    }
    for (int i = 0; i < df_len; i++) df[i] = lp_df[df_len - i - 1];
}

void TempoTrackV2::calculateBeatPeriod(const vector<double>& df,
        vector<int>& beat_period, double inputtempo, bool constraintempo) {
    const int wv_len = 128;
    const double rayparam = (60 * 44100 / 512.0) / inputtempo;
    d_vec_t wv(wv_len);

    if (constraintempo) {
        for (int i = 0; i < wv_len; i++) {
            wv[i] = exp((-1. * pow(double(i) - rayparam, 2.0)) /
                    (2. * pow(rayparam / 4., 2.0)));
        }
    } else {
        for (int i = 0; i < wv_len; i++) {
            wv[i] = (double(i) / pow(rayparam, 2.0)) *
                    exp((-1. * pow(-double(i), 2.0)) /
                            (2. * pow(rayparam, 2.0)));
        }
    }

    const int winlen = 512;
    const int hopsize = 128;
    const int df_len = int(df.size());
    d_mat_t rcfmat;
    rcfmat.reserve(df_len / hopsize + 1);
    d_vec_t dfframe(winlen);
    d_vec_t rcf(wv_len);

    for (int i = -winlen / 2; i < df_len - winlen / 2; i += hopsize) {
        int k = 0;
        int l = winlen;
        if (i < 0) {
            k = -i;
            std::fill(dfframe.begin(), dfframe.begin() + k, 0.0);
        }
        if (i + l > df_len) {
            l = df_len - i;
            std::fill(dfframe.begin() + l, dfframe.end(), 0.0);
        }
        std::copy(df.begin() + i + k, df.begin() + i + l, dfframe.begin() + k);
        get_rcf(dfframe, wv, rcf);
        rcfmat.push_back(d_vec_t());
        for (int j = 0; j < wv_len; j++) rcfmat.back().push_back(rcf[j]);
    }
    viterbi_decode(rcfmat, wv, beat_period);
}

void TempoTrackV2::get_rcf(const d_vec_t& dfframe_in,
        const d_vec_t& wv, d_vec_t& rcf) {
    d_vec_t dfframe(dfframe_in);
    MathUtilities::adaptiveThreshold(dfframe);
    const int dfframe_len = int(dfframe.size());
    const int rcf_len = int(rcf.size());
    d_vec_t acf(dfframe_len);

    for (int lag = 0; lag < dfframe_len; lag++) {
        double sum = 0.;
        for (int n = 0; n < dfframe_len - lag; n++) {
            sum += dfframe[n] * dfframe[n + lag];
        }
        acf[lag] = sum / (dfframe_len - lag);
    }

    const int numelem = 4;
    for (int i = 2; i < rcf_len; i++) {
        for (int a = 1; a <= numelem; a++) {
            for (int b = 1 - a; b <= a - 1; b++) {
                rcf[i - 1] += (acf[(a * i + b) - 1] * wv[i - 1]) / (2. * a - 1.);
            }
        }
    }

    MathUtilities::adaptiveThreshold(rcf);
    double rcfSum = 0.;
    for (int i = 0; i < rcf_len; i++) {
        rcf[i] += EPS;
        rcfSum += rcf[i];
    }
    for (int i = 0; i < rcf_len; i++) rcf[i] /= rcfSum + EPS;
}

void TempoTrackV2::viterbi_decode(const d_mat_t& rcfmat,
        const d_vec_t& wv, i_vec_t& beat_period) {
    if (rcfmat.size() < 2) return;
    const std::size_t T = rcfmat.size();
    const std::size_t Q = rcfmat[0].size();
    auto tmat = d_mat_t(Q, d_vec_t(Q));
    const double sigma = 8.;
    for (std::size_t i = 20; i < Q - 20; i++) {
        for (std::size_t j = 20; j < Q - 20; j++) {
            const double mu = double(i);
            tmat[i][j] = exp(-1. * pow(double(j) - mu, 2.0) /
                    (2. * pow(sigma, 2.0)));
        }
    }

    auto delta = d_mat_t(T, d_vec_t(Q));
    auto psi = i_mat_t(T, i_vec_t(Q));
    for (std::size_t j = 0; j < Q; j++) delta[0][j] = wv[j] * rcfmat[0][j];
    double deltaSum = 0.;
    for (std::size_t i = 0; i < Q; i++) deltaSum += delta[0][i];
    for (std::size_t i = 0; i < Q; i++) delta[0][i] /= deltaSum + EPS;

    for (std::size_t t = 1; t < T; t++) {
        d_vec_t tmp_vec(Q);
        for (std::size_t j = 0; j < Q; j++) {
            for (std::size_t i = 0; i < Q; i++) {
                tmp_vec[i] = delta[t - 1][i] * tmat[j][i];
            }
            delta[t][j] = get_max_val(tmp_vec);
            psi[t][j] = get_max_ind(tmp_vec);
            delta[t][j] *= rcfmat[t][j];
        }
        double currentSum = 0.;
        for (std::size_t i = 0; i < Q; i++) currentSum += delta[t][i];
        for (std::size_t i = 0; i < Q; i++) delta[t][i] /= currentSum + EPS;
    }

    i_vec_t& bestpath = beat_period;
    bestpath[T - 1] = get_max_ind(delta[T - 1]);
    for (int t = int(T) - 2; t > 0; t--) {
        bestpath[t] = psi[t + 1][bestpath[t + 1]];
    }
    bestpath[0] = psi[1][bestpath[1]];
}

double TempoTrackV2::get_max_val(const d_vec_t& df) {
    double maxval = 0.;
    for (int i = 0; i < int(df.size()); i++) {
        if (maxval < df[i]) maxval = df[i];
    }
    return maxval;
}

int TempoTrackV2::get_max_ind(const d_vec_t& df) {
    double maxval = 0.;
    int index = 0;
    for (int i = 0; i < int(df.size()); i++) {
        if (maxval < df[i]) {
            maxval = df[i];
            index = i;
        }
    }
    return index;
}

void TempoTrackV2::normalise_vec(d_vec_t& df) {
    double sum = 0.;
    for (int i = 0; i < int(df.size()); i++) sum += df[i];
    for (int i = 0; i < int(df.size()); i++) df[i] /= sum + EPS;
}

void TempoTrackV2::calculateBeats(const vector<double>& df,
        const vector<int>& beat_period, vector<double>& beats,
        double alpha, double tightness) {
    if (df.empty() || beat_period.empty()) return;
    const int df_len = int(df.size());
    d_vec_t cumscore(df_len);
    i_vec_t backlink(df_len);
    d_vec_t localscore(df_len);
    for (int i = 0; i < df_len; i++) {
        localscore[i] = df[i];
        backlink[i] = -1;
    }

    int old_period = 0;
    int txwt_len = 0;
    d_vec_t txwt;
    for (int i = 0; i < df_len; i++) {
        const int period = beat_period[i / 128];
        const int prange_min = period * -2;
        if (period != old_period) {
            old_period = period;
            const int prange_max = period / -2;
            txwt_len = prange_max - prange_min + 1;
            txwt.clear();
            txwt.reserve(txwt_len);
            for (int j = 0; j < txwt_len; j++) {
                const double mu = double(period);
                txwt.push_back(exp(-0.5 * pow(tightness *
                        log((round(2 * mu) - j) / mu), 2.0)));
            }
        }

        double vv = 0;
        int xx = 0;
        for (int j = 0; j < txwt_len; j++) {
            const int cscore_ind = i + prange_min + j;
            if (cscore_ind >= 0) {
                const double scorecands = txwt[j] * cumscore[cscore_ind];
                if (scorecands > vv) {
                    vv = scorecands;
                    xx = cscore_ind;
                }
            }
        }
        cumscore[i] = alpha * vv + (1. - alpha) * localscore[i];
        backlink[i] = xx;
    }

    d_vec_t tmp_vec;
    for (int i = df_len - beat_period[beat_period.size() - 1]; i < df_len; i++) {
        tmp_vec.push_back(cumscore[i]);
    }
    int startpoint = get_max_ind(tmp_vec) + df_len - beat_period[beat_period.size() - 1];
    if (startpoint >= int(backlink.size())) startpoint = int(backlink.size()) - 1;
    if (startpoint < 0) return;

    i_vec_t ibeats;
    ibeats.push_back(startpoint);
    while (backlink[ibeats.back()] > 0) {
        const int b = ibeats.back();
        if (backlink[b] == b) break;
        ibeats.push_back(backlink[b]);
    }
    for (int i = 0; i < int(ibeats.size()); i++) {
        beats.push_back(double(ibeats[ibeats.size() - i - 1]));
    }
}

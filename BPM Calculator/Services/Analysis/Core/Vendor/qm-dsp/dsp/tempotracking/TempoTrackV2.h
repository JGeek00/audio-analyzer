/* -*- c-basic-offset: 4 indent-tabs-mode: nil -*-  vi:set ts=8 sts=4 sw=4: */

/*
    QM DSP Library

    This file copyright 2008-2009 Matthew Davies and QMUL.

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation; either version 2 of the
    License, or (at your option) any later version.  See the file
    COPYING included with this distribution for more information.
*/

#ifndef QM_DSP_TEMPOTRACKV2_H
#define QM_DSP_TEMPOTRACKV2_H

#include <vector>

class TempoTrackV2
{
public:
    TempoTrackV2(float sampleRate, int dfIncrement);
    ~TempoTrackV2();

    void calculateBeatPeriod(const std::vector<double>& df,
            std::vector<int>& beatPeriod) {
        calculateBeatPeriod(df, beatPeriod, 120.0, false);
    }
    void calculateBeatPeriod(const std::vector<double>& df,
            std::vector<int>& beatPeriod, double inputtempo, bool constraintempo);
    void calculateBeats(const std::vector<double>& df,
            const std::vector<int>& beatPeriod,
            std::vector<double>& beats) {
        calculateBeats(df, beatPeriod, beats, 0.9, 4.0);
    }
    void calculateBeats(const std::vector<double>& df,
            const std::vector<int>& beatPeriod,
            std::vector<double>& beats, double alpha, double tightness);

private:
    typedef std::vector<int> i_vec_t;
    typedef std::vector<std::vector<int>> i_mat_t;
    typedef std::vector<double> d_vec_t;
    typedef std::vector<std::vector<double>> d_mat_t;

    float m_rate;
    int m_increment;

    void adapt_thresh(d_vec_t& df);
    double mean_array(const d_vec_t& dfin, int start, int end);
    void filter_df(d_vec_t& df);
    void get_rcf(const d_vec_t& dfframe, const d_vec_t& wv, d_vec_t& rcf);
    void viterbi_decode(const d_mat_t& rcfmat, const d_vec_t& wv, i_vec_t& bp);
    double get_max_val(const d_vec_t& df);
    int get_max_ind(const d_vec_t& df);
    void normalise_vec(d_vec_t& df);
};

#endif

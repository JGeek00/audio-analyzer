/* -*- c-basic-offset: 4 indent-tabs-mode: nil -*-  vi:set ts=8 sts=4 sw=4: */

/*
    QM DSP Library

    Centre for Digital Music, Queen Mary, University of London.
    This file 2005-2006 Christian Landone.

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation; either version 2 of the
    License, or (at your option) any later version.  See the file
    COPYING included with this distribution for more information.
*/

#ifndef MATHUTILITIES_H
#define MATHUTILITIES_H

#include <vector>

#include "nan-inf.h"

/**
 * Static helper functions for simple mathematical calculations.
 */
class MathUtilities
{
public:
    static double round(double x);
    static void getFrameMinMax(const double* data, int len, double* min, double* max);
    static double mean(const double* src, int len);
    static double mean(const std::vector<double>& data, int start, int count);
    static double sum(const double* src, int len);
    static double median(const double* src, int len);
    static double princarg(double ang);
    static double mod(double x, double y);
    static void getAlphaNorm(const double* data, int len, int alpha, double* ANorm);
    static double getAlphaNorm(const std::vector<double>& data, int alpha);

    enum NormaliseType {
        NormaliseNone,
        NormaliseUnitSum,
        NormaliseUnitMax
    };

    static void normalise(double* data, int length, NormaliseType n = NormaliseUnitMax);
    static void normalise(std::vector<double>& data, NormaliseType n = NormaliseUnitMax);
    static double getLpNorm(const std::vector<double>& data, int p);
    static std::vector<double> normaliseLp(const std::vector<double>& data,
            int p, double threshold = 1e-6);
    static void adaptiveThreshold(std::vector<double>& data);
    static void circShift(double* data, int length, int shift);
    static int getMax(double* data, int length, double* max = 0);
    static int getMax(const std::vector<double>& data, double* max = 0);
    static int compareInt(const void* a, const void* b);
    static bool isPowerOfTwo(int x);
    static int nextPowerOfTwo(int x);
    static int previousPowerOfTwo(int x);
    static int nearestPowerOfTwo(int x);
    static double factorial(int x);
    static int gcd(int a, int b);
};

#endif

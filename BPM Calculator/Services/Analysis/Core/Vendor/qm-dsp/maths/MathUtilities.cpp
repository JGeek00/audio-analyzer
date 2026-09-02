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

#include "MathUtilities.h"

#include <iostream>
#include <algorithm>
#include <vector>
#include <cmath>

using namespace std;

double MathUtilities::mod(double x, double y)
{
    double a = floor(x / y);
    double b = x - (y * a);
    return b;
}

double MathUtilities::princarg(double ang)
{
    double ValOut;
    ValOut = mod(ang + M_PI, -2 * M_PI) + M_PI;
    return ValOut;
}

void MathUtilities::getAlphaNorm(const double* data, int len, int alpha, double* ANorm)
{
    double a = 0.0;
    for (int i = 0; i < len; i++) {
        a += ::pow(fabs(data[i]), double(alpha));
    }
    a /= double(len);
    a = ::pow(a, 1.0 / double(alpha));
    *ANorm = a;
}

double MathUtilities::getAlphaNorm(const vector<double>& data, int alpha)
{
    double a = 0.0;
    const int len = int(data.size());
    for (int i = 0; i < len; i++) {
        a += ::pow(fabs(data[i]), double(alpha));
    }
    a /= double(len);
    a = ::pow(a, 1.0 / double(alpha));
    return a;
}

double MathUtilities::round(double x)
{
    if (x < 0) {
        return -floor(-x + 0.5);
    }
    return floor(x + 0.5);
}

double MathUtilities::median(const double* src, int len)
{
    if (len == 0) return 0;
    vector<double> scratch;
    for (int i = 0; i < len; ++i) scratch.push_back(src[i]);
    sort(scratch.begin(), scratch.end());
    const int middle = len / 2;
    if (len % 2 == 0) {
        return (scratch[middle] + scratch[middle - 1]) / 2;
    }
    return scratch[middle];
}

double MathUtilities::sum(const double* src, int len)
{
    double retVal = 0.0;
    for (int i = 0; i < len; i++) retVal += src[i];
    return retVal;
}

double MathUtilities::mean(const double* src, int len)
{
    if (len == 0) return 0;
    return sum(src, len) / double(len);
}

double MathUtilities::mean(const vector<double>& src, int start, int count)
{
    double sum = 0.0;
    if (count == 0) return 0;
    for (int i = 0; i < count; ++i) sum += src[start + i];
    return sum / count;
}

void MathUtilities::getFrameMinMax(const double* data, int len, double* min, double* max)
{
    if (len == 0) {
        *min = *max = 0;
        return;
    }
    *min = data[0];
    *max = data[0];
    for (int i = 0; i < len; i++) {
        if (data[i] < *min) *min = data[i];
        if (data[i] > *max) *max = data[i];
    }
}

int MathUtilities::getMax(double* pData, int length, double* pMax)
{
    int index = 0;
    double max = pData[0];
    for (int i = 0; i < length; i++) {
        if (pData[i] > max) {
            max = pData[i];
            index = i;
        }
    }
    if (pMax) *pMax = max;
    return index;
}

int MathUtilities::getMax(const vector<double>& data, double* pMax)
{
    int index = 0;
    double max = data[0];
    for (int i = 0; i < int(data.size()); i++) {
        if (data[i] > max) {
            max = data[i];
            index = i;
        }
    }
    if (pMax) *pMax = max;
    return index;
}

void MathUtilities::circShift(double* pData, int length, int shift)
{
    shift = shift % length;
    for (int i = 0; i < shift; i++) {
        const double temp = *(pData + length - 1);
        for (int n = length - 2; n >= 0; n--) {
            *(pData + n + 1) = *(pData + n);
        }
        *pData = temp;
    }
}

int MathUtilities::compareInt(const void* a, const void* b)
{
    return (*(int*)a - *(int*)b);
}

void MathUtilities::normalise(double* data, int length, NormaliseType type)
{
    switch (type) {
    case NormaliseNone:
        return;
    case NormaliseUnitSum: {
        double sum = 0.0;
        for (int i = 0; i < length; ++i) sum += data[i];
        if (sum != 0.0) {
            for (int i = 0; i < length; ++i) data[i] /= sum;
        }
        break;
    }
    case NormaliseUnitMax: {
        double max = 0.0;
        for (int i = 0; i < length; ++i) {
            if (fabs(data[i]) > max) max = fabs(data[i]);
        }
        if (max != 0.0) {
            for (int i = 0; i < length; ++i) data[i] /= max;
        }
        break;
    }
    }
}

void MathUtilities::normalise(vector<double>& data, NormaliseType type)
{
    switch (type) {
    case NormaliseNone:
        return;
    case NormaliseUnitSum: {
        double sum = 0.0;
        for (int i = 0; i < int(data.size()); ++i) sum += data[i];
        if (sum != 0.0) {
            for (int i = 0; i < int(data.size()); ++i) data[i] /= sum;
        }
        break;
    }
    case NormaliseUnitMax: {
        double max = 0.0;
        for (int i = 0; i < int(data.size()); ++i) {
            if (fabs(data[i]) > max) max = fabs(data[i]);
        }
        if (max != 0.0) {
            for (int i = 0; i < int(data.size()); ++i) data[i] /= max;
        }
        break;
    }
    }
}

double MathUtilities::getLpNorm(const vector<double>& data, int p)
{
    double total = 0.0;
    for (int i = 0; i < int(data.size()); ++i) {
        total += abs(pow(data[i], p));
    }
    return pow(total, 1.0 / p);
}

vector<double> MathUtilities::normaliseLp(const vector<double>& data,
        int p, double threshold)
{
    const int n = int(data.size());
    if (n == 0 || p == 0) return data;
    const double norm = getLpNorm(data, p);
    if (norm < threshold) {
        return vector<double>(n, 1.0 / pow(n, 1.0 / p));
    }
    vector<double> out(n);
    for (int i = 0; i < n; ++i) out[i] = data[i] / norm;
    return out;
}

void MathUtilities::adaptiveThreshold(vector<double>& data)
{
    const int size = int(data.size());
    if (size == 0) return;
    vector<double> smoothed(size);
    const int pre = 8;
    const int post = 7;
    for (int i = 0; i < size; ++i) {
        const int first = max(0, i - pre);
        const int last = min(size - 1, i + post);
        smoothed[i] = mean(data, first, last - first + 1);
    }
    for (int i = 0; i < size; i++) {
        data[i] -= smoothed[i];
        if (data[i] < 0.0) data[i] = 0.0;
    }
}

bool MathUtilities::isPowerOfTwo(int x)
{
    if (x < 1) return false;
    return (x & (x - 1)) == 0;
}

int MathUtilities::nextPowerOfTwo(int x)
{
    if (isPowerOfTwo(x)) return x;
    if (x < 1) return 1;
    int n = 1;
    while (x) {
        x >>= 1;
        n <<= 1;
    }
    return n;
}

int MathUtilities::previousPowerOfTwo(int x)
{
    if (isPowerOfTwo(x)) return x;
    if (x < 1) return 1;
    int n = 1;
    x >>= 1;
    while (x) {
        x >>= 1;
        n <<= 1;
    }
    return n;
}

int MathUtilities::nearestPowerOfTwo(int x)
{
    if (isPowerOfTwo(x)) return x;
    const int lower = previousPowerOfTwo(x);
    const int upper = nextPowerOfTwo(x);
    return x - lower < upper - x ? lower : upper;
}

double MathUtilities::factorial(int x)
{
    if (x < 0) return 0;
    double f = 1;
    for (int i = 1; i <= x; ++i) f *= i;
    return f;
}

int MathUtilities::gcd(int a, int b)
{
    const int c = a % b;
    if (c == 0) return b;
    return gcd(b, c);
}

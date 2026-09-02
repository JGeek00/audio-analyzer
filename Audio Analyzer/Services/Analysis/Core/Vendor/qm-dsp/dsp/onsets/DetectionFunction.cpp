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

#include "DetectionFunction.h"
#include <cstring>

DetectionFunction::DetectionFunction(DFConfig config)
        : m_window(0) {
    m_magHistory = NULL;
    m_phaseHistory = NULL;
    m_phaseHistoryOld = NULL;
    m_magPeaks = NULL;
    initialise(config);
}

DetectionFunction::~DetectionFunction() {
    deInitialise();
}

void DetectionFunction::initialise(DFConfig config) {
    m_dataLength = config.frameLength;
    m_halfLength = m_dataLength / 2 + 1;
    m_DFType = config.DFType;
    m_stepSize = config.stepSize;
    m_dbRise = config.dbRise;
    m_whiten = config.adaptiveWhitening;
    m_whitenRelaxCoeff = config.whiteningRelaxCoeff;
    m_whitenFloor = config.whiteningFloor;
    if (m_whitenRelaxCoeff < 0) m_whitenRelaxCoeff = 0.9997;
    if (m_whitenFloor < 0) m_whitenFloor = 0.01;

    m_magHistory = new double[m_halfLength];
    memset(m_magHistory, 0, m_halfLength * sizeof(double));
    m_phaseHistory = new double[m_halfLength];
    memset(m_phaseHistory, 0, m_halfLength * sizeof(double));
    m_phaseHistoryOld = new double[m_halfLength];
    memset(m_phaseHistoryOld, 0, m_halfLength * sizeof(double));
    m_magPeaks = new double[m_halfLength];
    memset(m_magPeaks, 0, m_halfLength * sizeof(double));

    m_phaseVoc = new PhaseVocoder(m_dataLength, m_stepSize);
    m_magnitude = new double[m_halfLength];
    m_thetaAngle = new double[m_halfLength];
    m_unwrapped = new double[m_halfLength];
    m_window = new Window<double>(HanningWindow, m_dataLength);
    m_windowed = new double[m_dataLength];
}

void DetectionFunction::deInitialise() {
    delete [] m_magHistory;
    delete [] m_phaseHistory;
    delete [] m_phaseHistoryOld;
    delete [] m_magPeaks;
    delete m_phaseVoc;
    delete [] m_magnitude;
    delete [] m_thetaAngle;
    delete [] m_windowed;
    delete [] m_unwrapped;
    delete m_window;
}

double DetectionFunction::processTimeDomain(const double* samples) {
    m_window->cut(samples, m_windowed);
    m_phaseVoc->processTimeDomain(m_windowed, m_magnitude, m_thetaAngle, m_unwrapped);
    if (m_whiten) whiten();
    return runDF();
}

double DetectionFunction::processFrequencyDomain(const double* reals, const double* imags) {
    m_phaseVoc->processFrequencyDomain(reals, imags, m_magnitude, m_thetaAngle, m_unwrapped);
    if (m_whiten) whiten();
    return runDF();
}

void DetectionFunction::whiten() {
    for (int i = 0; i < m_halfLength; ++i) {
        double magnitude = m_magnitude[i];
        if (magnitude < m_magPeaks[i]) {
            magnitude += (m_magPeaks[i] - magnitude) * m_whitenRelaxCoeff;
        }
        if (magnitude < m_whitenFloor) magnitude = m_whitenFloor;
        m_magPeaks[i] = magnitude;
        m_magnitude[i] /= magnitude;
    }
}

double DetectionFunction::runDF() {
    double result = 0;
    switch (m_DFType) {
    case DF_HFC:
        result = HFC(m_halfLength, m_magnitude);
        break;
    case DF_SPECDIFF:
        result = specDiff(m_halfLength, m_magnitude);
        break;
    case DF_PHASEDEV:
        result = phaseDev(m_halfLength, m_thetaAngle);
        break;
    case DF_COMPLEXSD:
        result = complexSD(m_halfLength, m_magnitude, m_thetaAngle);
        break;
    case DF_BROADBAND:
        result = broadband(m_halfLength, m_magnitude);
        break;
    }
    return result;
}

double DetectionFunction::HFC(int length, double* src) {
    double value = 0;
    for (int i = 0; i < length; i++) value += src[i] * (i + 1);
    return value;
}

double DetectionFunction::specDiff(int length, double* src) {
    double value = 0.0;
    for (int i = 0; i < length; i++) {
        const double temp = fabs((src[i] * src[i]) -
                (m_magHistory[i] * m_magHistory[i]));
        value += sqrt(temp);
        m_magHistory[i] = src[i];
    }
    return value;
}

double DetectionFunction::phaseDev(int length, double* srcPhase) {
    double value = 0;
    for (int i = 0; i < length; i++) {
        const double tmpPhase = srcPhase[i] - 2 * m_phaseHistory[i] + m_phaseHistoryOld[i];
        const double deviation = MathUtilities::princarg(tmpPhase);
        value += fabs(deviation);
        m_phaseHistoryOld[i] = m_phaseHistory[i];
        m_phaseHistory[i] = srcPhase[i];
    }
    return value;
}

double DetectionFunction::complexSD(int length, double* srcMagnitude, double* srcPhase) {
    double value = 0;
    const ComplexData j = ComplexData(0, 1);
    for (int i = 0; i < length; i++) {
        const double tmpPhase = srcPhase[i] - 2 * m_phaseHistory[i] + m_phaseHistoryOld[i];
        const double deviation = MathUtilities::princarg(tmpPhase);
        const ComplexData measured = m_magHistory[i] -
                (srcMagnitude[i] * exp(j * deviation));
        const double real = std::real(measured);
        const double imag = std::imag(measured);
        value += sqrt((real * real) + (imag * imag));
        m_phaseHistoryOld[i] = m_phaseHistory[i];
        m_phaseHistory[i] = srcPhase[i];
        m_magHistory[i] = srcMagnitude[i];
    }
    return value;
}

double DetectionFunction::broadband(int length, double* src) {
    double value = 0;
    for (int i = 0; i < length; ++i) {
        const double squaredMagnitude = src[i] * src[i];
        if (m_magHistory[i] > 0.0) {
            const double difference = 10.0 * log10(squaredMagnitude / m_magHistory[i]);
            if (difference > m_dbRise) value += 1;
        }
        m_magHistory[i] = squaredMagnitude;
    }
    return value;
}

double* DetectionFunction::getSpectrumMagnitude() {
    return m_magnitude;
}

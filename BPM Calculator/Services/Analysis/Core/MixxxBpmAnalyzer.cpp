#include "MixxxBpmAnalyzer.h"

#include <algorithm>
#include <cmath>
#include <limits>

#include "Vendor/qm-dsp/dsp/onsets/DetectionFunction.h"
#include "Vendor/qm-dsp/dsp/tempotracking/TempoTrackV2.h"
#include "Vendor/qm-dsp/maths/MathUtilities.h"

#include "BeatPostProcessor.h"

namespace bpm::analysis {
namespace {

constexpr float kStepSecs = 0.01161f;
constexpr int kMaximumBinSizeHz = 50;

DFConfig makeDetectionFunctionConfig(int stepSizeFrames, int windowSize) {
    DFConfig config{};
    config.DFType = DF_COMPLEXSD;
    config.stepSize = stepSizeFrames;
    config.frameLength = windowSize;
    config.dbRise = 3.0;
    config.adaptiveWhitening = false;
    config.whiteningRelaxCoeff = -1.0;
    config.whiteningFloor = -1.0;
    return config;
}

} // namespace

MixxxBpmAnalyzer::MixxxBpmAnalyzer(double sampleRate)
        : sampleRate_(sampleRate) {
    result_.sampleRate = sampleRate_;

    if (!std::isfinite(sampleRate_) || sampleRate_ <= 0.0 ||
            sampleRate_ > static_cast<double>(std::numeric_limits<int>::max())) {
        return;
    }

    stepSizeFrames_ = static_cast<int>(sampleRate_ * kStepSecs);
    const int baseWindowSize = static_cast<int>(sampleRate_ / kMaximumBinSizeHz);
    windowSize_ = MathUtilities::nextPowerOfTwo(baseWindowSize);
    if (stepSizeFrames_ <= 0 || windowSize_ <= 0 || stepSizeFrames_ > windowSize_) {
        return;
    }

    detectionFunction_ = std::make_unique<DetectionFunction>(
            makeDetectionFunctionConfig(stepSizeFrames_, windowSize_));
    valid_ = helper_.initialize(
            static_cast<std::size_t>(windowSize_),
            static_cast<std::size_t>(stepSizeFrames_),
            [this](double* window, std::size_t) {
                detectionResults_.push_back(
                        detectionFunction_->processTimeDomain(window));
                return true;
            });
}

MixxxBpmAnalyzer::~MixxxBpmAnalyzer() = default;

bool MixxxBpmAnalyzer::isValid() const noexcept {
    return valid_;
}

bool MixxxBpmAnalyzer::process(const float* samples, std::size_t sampleCount) {
    if (finished_ || !valid_ || !detectionFunction_) {
        return false;
    }
    if (sampleCount % 2 != 0 || (sampleCount > 0 && samples == nullptr)) {
        return false;
    }
    return helper_.processStereoSamples(samples, sampleCount);
}

BpmAnalysisResult MixxxBpmAnalyzer::finish() {
    if (finished_) {
        return result_;
    }
    finished_ = true;

    if (!valid_ || !detectionFunction_) {
        return result_;
    }

    if (!helper_.finalize()) {
        detectionFunction_.reset();
        return result_;
    }

    std::size_t nonZeroCount = detectionResults_.size();
    while (nonZeroCount > 0 && detectionResults_[nonZeroCount - 1] <= 0.0) {
        --nonZeroCount;
    }

    const std::size_t requiredSize =
            std::max(static_cast<std::size_t>(2), nonZeroCount) - 2;
    std::vector<double> detectionFunctionValues;
    detectionFunctionValues.reserve(requiredSize);
    for (std::size_t i = 2; i < nonZeroCount; ++i) {
        detectionFunctionValues.push_back(detectionResults_[i]);
    }

    std::vector<int> beatPeriod(requiredSize / 128 + 1);
    TempoTrackV2 tracker(static_cast<float>(sampleRate_), stepSizeFrames_);
    tracker.calculateBeatPeriod(detectionFunctionValues, beatPeriod);

    std::vector<double> beats;
    tracker.calculateBeats(detectionFunctionValues, beatPeriod, beats);

    resultBeats_.reserve(beats.size());
    for (const double beat : beats) {
        // Mixxx uses integer division for this half-step offset.
        resultBeats_.push_back(
                beat * stepSizeFrames_ + stepSizeFrames_ / 2);
    }
    result_.rawBeatFrames = resultBeats_;

    const FixedTempoResult fixedTempo =
            BeatPostProcessor::makeFixedTempo(resultBeats_, sampleRate_);
    result_.bpm = fixedTempo.bpm;
    result_.firstBeatFrame = fixedTempo.firstBeatFrame;

    detectionFunction_.reset();
    return result_;
}

} // namespace bpm::analysis

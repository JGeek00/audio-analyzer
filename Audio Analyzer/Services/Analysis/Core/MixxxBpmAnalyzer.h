#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

#include "BufferingUtils.h"

class DetectionFunction;

namespace bpm::analysis {

struct BpmAnalysisResult {
    double bpm = 0.0;
    std::int64_t firstBeatFrame = -1;
    double sampleRate = 0.0;
    std::vector<double> rawBeatFrames;
};

class MixxxBpmAnalyzer {
public:
    explicit MixxxBpmAnalyzer(double sampleRate);
    ~MixxxBpmAnalyzer();

    MixxxBpmAnalyzer(const MixxxBpmAnalyzer&) = delete;
    MixxxBpmAnalyzer& operator=(const MixxxBpmAnalyzer&) = delete;

    bool isValid() const noexcept;
    bool process(const float* samples, std::size_t sampleCount);
    BpmAnalysisResult finish();

private:
    double sampleRate_ = 0.0;
    int stepSizeFrames_ = 0;
    int windowSize_ = 0;
    bool valid_ = false;
    bool finished_ = false;

    DownmixAndOverlapHelper helper_;
    std::unique_ptr<DetectionFunction> detectionFunction_;
    std::vector<double> detectionResults_;
    std::vector<double> resultBeats_;
    BpmAnalysisResult result_;
};

} // namespace bpm::analysis

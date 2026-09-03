#pragma once

#include <cstddef>
#include <limits>
#include <vector>

namespace bpm::analysis {

struct ReplayGainAnalysisResult {
    double loudnessLUFS = -std::numeric_limits<double>::infinity();
    double peak = 0.0;
};

class ReplayGainAnalyzer {
public:
    explicit ReplayGainAnalyzer(double sampleRate);
    ~ReplayGainAnalyzer();

    ReplayGainAnalyzer(const ReplayGainAnalyzer&) = delete;
    ReplayGainAnalyzer& operator=(const ReplayGainAnalyzer&) = delete;

    bool isValid() const noexcept;
    bool process(const float* samples, std::size_t sampleCount);
    ReplayGainAnalysisResult finish();

private:
    double filterSample(double x, double* state) noexcept;

    double sampleRate_ = 0.0;
    bool valid_ = false;
    bool finished_ = false;

    // Combined 4th-order K-weighting (ITU-R BS.1770). See .cpp for the design.
    double b_[5] = {};
    double a_[5] = {};
    double stateL_[5] = {};
    double stateR_[5] = {};

    std::size_t hopSize_ = 0;
    double hopSumL_ = 0.0;
    double hopSumR_ = 0.0;
    std::size_t hopCount_ = 0;
    std::vector<double> blocks_;
    double peak_ = 0.0;
    ReplayGainAnalysisResult result_;
};

} // namespace bpm::analysis

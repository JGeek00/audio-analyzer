#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "BufferingUtils.h"

class GetKeyMode;

namespace bpm::analysis {

struct KeyChange {
    int keyID = 0;
    std::int64_t frame = 0;
};

struct KeyAnalysisResult {
    int globalKeyID = 0;
    std::string keyText;
    double sampleRate = 0.0;
    std::vector<KeyChange> keyChanges;
};

class MixxxKeyAnalyzer {
public:
    MixxxKeyAnalyzer(double sampleRate, std::int64_t totalFrameCount);
    ~MixxxKeyAnalyzer();

    MixxxKeyAnalyzer(const MixxxKeyAnalyzer&) = delete;
    MixxxKeyAnalyzer& operator=(const MixxxKeyAnalyzer&) = delete;

    bool isValid() const noexcept;
    bool process(const float* samples, std::size_t sampleCount);
    KeyAnalysisResult finish();

private:
    static int calculateGlobalKey(const std::vector<KeyChange>& changes,
            std::int64_t totalFrameCount);
    static const char* keyTextForID(int keyID);

    double sampleRate_ = 0.0;
    std::int64_t totalFrameCount_ = 0;
    std::int64_t currentFrame_ = 0;
    bool valid_ = false;
    bool finished_ = false;

    DownmixAndOverlapHelper helper_;
    std::unique_ptr<GetKeyMode> keyMode_;
    std::vector<KeyChange> resultKeys_;
    KeyAnalysisResult result_;
};

} // namespace bpm::analysis

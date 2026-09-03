#include "MixxxKeyAnalyzer.h"

#include <array>
#include <cmath>
#include <limits>

#include "Vendor/qm-dsp/dsp/keydetection/GetKeyMode.h"

namespace bpm::analysis {
namespace {

constexpr int kFirstKeyID = 1;
constexpr int kLastKeyID = 24;
constexpr int kTuningFrequencyHertz = 440;

} // namespace

MixxxKeyAnalyzer::MixxxKeyAnalyzer(
        double sampleRate, std::int64_t totalFrameCount)
        : sampleRate_(sampleRate), totalFrameCount_(totalFrameCount) {
    result_.sampleRate = sampleRate_;

    if (!std::isfinite(sampleRate_) || sampleRate_ <= 0.0 ||
            sampleRate_ > static_cast<double>(std::numeric_limits<int>::max()) ||
            totalFrameCount_ < 0) {
        return;
    }

    try {
        GetKeyMode::Config config(sampleRate_, kTuningFrequencyHertz);
        keyMode_ = std::make_unique<GetKeyMode>(config);
    } catch (...) {
        keyMode_.reset();
        return;
    }

    const int windowSize = keyMode_->getBlockSize();
    const int stepSize = keyMode_->getHopSize();
    if (windowSize <= 0 || stepSize <= 0 || stepSize > windowSize) {
        keyMode_.reset();
        return;
    }

    valid_ = helper_.initialize(
            static_cast<std::size_t>(windowSize),
            static_cast<std::size_t>(stepSize),
            [this](double* window, std::size_t) {
                const int keyID = keyMode_->process(window);
                if (keyID < kFirstKeyID || keyID > kLastKeyID) {
                    return false;
                }
                if (resultKeys_.empty() || resultKeys_.back().keyID != keyID) {
                    resultKeys_.push_back({keyID, currentFrame_});
                }
                return true;
            });
}

MixxxKeyAnalyzer::~MixxxKeyAnalyzer() = default;

bool MixxxKeyAnalyzer::isValid() const noexcept {
    return valid_;
}

bool MixxxKeyAnalyzer::process(const float* samples, std::size_t sampleCount) {
    if (finished_ || !valid_ || !keyMode_ || sampleCount % 2 != 0 ||
            (sampleCount > 0 && samples == nullptr)) {
        return false;
    }

    const auto inputFrames = static_cast<std::int64_t>(sampleCount / 2);
    if (inputFrames > std::numeric_limits<std::int64_t>::max() - currentFrame_) {
        return false;
    }
    currentFrame_ += inputFrames;
    return helper_.processStereoSamples(samples, sampleCount);
}

KeyAnalysisResult MixxxKeyAnalyzer::finish() {
    if (finished_) {
        return result_;
    }
    finished_ = true;

    if (!valid_ || !keyMode_ || !helper_.finalize()) {
        keyMode_.reset();
        return result_;
    }

    result_.keyChanges = resultKeys_;
    result_.globalKeyID = calculateGlobalKey(resultKeys_, totalFrameCount_);
    result_.keyText = keyTextForID(result_.globalKeyID);
    keyMode_.reset();
    return result_;
}

int MixxxKeyAnalyzer::calculateGlobalKey(
        const std::vector<KeyChange>& changes, std::int64_t totalFrameCount) {
    if (changes.empty()) {
        return 0;
    }
    if (changes.size() == 1) {
        return changes.front().keyID;
    }

    std::array<std::int64_t, kLastKeyID + 1> durations{};
    for (std::size_t index = 0; index < changes.size(); ++index) {
        const auto& change = changes[index];
        const std::int64_t endFrame = index + 1 < changes.size()
                ? changes[index + 1].frame
                : totalFrameCount;
        if (change.keyID >= kFirstKeyID && change.keyID <= kLastKeyID) {
            durations[change.keyID] += endFrame - change.frame;
        }
    }

    int globalKeyID = 0;
    std::int64_t longestDuration = 0;
    for (int keyID = kFirstKeyID; keyID <= kLastKeyID; ++keyID) {
        // Strict comparison preserves Mixxx's lower-ID tie break.
        if (durations[keyID] > longestDuration) {
            longestDuration = durations[keyID];
            globalKeyID = keyID;
        }
    }
    return globalKeyID;
}

const char* MixxxKeyAnalyzer::keyTextForID(int keyID) {
    static constexpr const char* kKeyNames[] = {
        "", "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B",
        "Cm", "C#m", "Dm", "Ebm", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "Bbm", "Bm"
    };
    return keyID >= 0 && keyID <= kLastKeyID ? kKeyNames[keyID] : "";
}

} // namespace bpm::analysis

#pragma once

#include <cstddef>
#include <functional>
#include <vector>

namespace bpm::analysis {

class DownmixAndOverlapHelper {
public:
    using WindowReadyCallback = std::function<bool(double* buffer, std::size_t frames)>;

    bool initialize(std::size_t windowSize,
            std::size_t stepSize,
            WindowReadyCallback callback);
    bool processStereoSamples(const float* input, std::size_t inputStereoSamples);
    bool finalize();

private:
    bool processInner(const float* input, std::size_t inputFrames);

    std::vector<double> buffer_;
    std::size_t windowSize_ = 0;
    std::size_t stepSize_ = 0;
    std::size_t bufferWritePosition_ = 0;
    WindowReadyCallback callback_;
};

} // namespace bpm::analysis

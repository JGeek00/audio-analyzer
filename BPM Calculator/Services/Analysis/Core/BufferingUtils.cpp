#include "BufferingUtils.h"

#include <algorithm>
#include <cassert>

namespace bpm::analysis {

bool DownmixAndOverlapHelper::initialize(std::size_t windowSize,
        std::size_t stepSize,
        WindowReadyCallback callback) {
    buffer_.assign(windowSize, 0.0);
    callback_ = std::move(callback);
    windowSize_ = windowSize;
    stepSize_ = stepSize;
    bufferWritePosition_ = windowSize / 2;
    return windowSize_ > 0 && stepSize_ > 0 && stepSize_ <= windowSize_ &&
            static_cast<bool>(callback_);
}

bool DownmixAndOverlapHelper::processStereoSamples(const float* input,
        std::size_t inputStereoSamples) {
    if (inputStereoSamples % 2 != 0 || (inputStereoSamples > 0 && input == nullptr)) {
        return false;
    }
    return processInner(input, inputStereoSamples / 2);
}

bool DownmixAndOverlapHelper::finalize() {
    if (windowSize_ == 0 || stepSize_ == 0 || !callback_) {
        return false;
    }

    const std::size_t framesToFillWindow = windowSize_ - bufferWritePosition_;
    const std::size_t inputFrames = std::max(
            framesToFillWindow, windowSize_ / 2 - 1);
    return processInner(nullptr, inputFrames);
}

bool DownmixAndOverlapHelper::processInner(const float* input,
        std::size_t inputFrames) {
    std::size_t inputPosition = 0;
    double* downmix = buffer_.data();

    while (inputPosition < inputFrames) {
        assert(bufferWritePosition_ <= windowSize_);
        const std::size_t readAvailable = inputFrames - inputPosition;
        const std::size_t writeAvailable = windowSize_ - bufferWritePosition_;
        const std::size_t frames = std::min(readAvailable, writeAvailable);

        if (input != nullptr) {
            for (std::size_t i = 0; i < frames; ++i) {
                downmix[bufferWritePosition_ + i] =
                        (static_cast<double>(input[(inputPosition + i) * 2]) +
                                static_cast<double>(input[(inputPosition + i) * 2 + 1])) *
                        0.5;
            }
        } else {
            std::fill_n(downmix + bufferWritePosition_, frames, 0.0);
        }

        bufferWritePosition_ += frames;
        inputPosition += frames;

        if (bufferWritePosition_ == windowSize_) {
            if (!callback_(downmix, windowSize_)) {
                return false;
            }

            for (std::size_t i = 0; i < windowSize_ - stepSize_; ++i) {
                downmix[i] = downmix[i + stepSize_];
            }
            bufferWritePosition_ -= stepSize_;
        }
    }

    return true;
}

} // namespace bpm::analysis

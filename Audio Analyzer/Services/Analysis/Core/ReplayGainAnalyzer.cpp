#include "ReplayGainAnalyzer.h"

#include <cmath>

namespace bpm::analysis {
namespace {

// Filter design follows libebur128 (MIT, Jan Kokemüller), which implements the
// ITU-R BS.1770 K-weighting: a high shelf (f0 = 1681.97 Hz) cascaded with a
// high-pass (f0 = 38.13 Hz), combined here into a single 4th-order section so
// the coefficients track any sample rate instead of the 48 kHz table values.
// License preserved in LIBEBUR128-LICENSE.md (same directory).
constexpr double kPreFilterF0 = 1681.974450955533;
constexpr double kPreFilterG = 3.999843853973347;
constexpr double kPreFilterQ = 0.7071752369554196;
constexpr double kRlbF0 = 38.13547087602444;
constexpr double kRlbQ = 0.5003270373238773;
constexpr double kVbExponent = 0.4996667741545416;

constexpr double kAbsoluteGateLUFS = -70.0;
constexpr double kRelativeGateLU = 10.0;
constexpr double kLevelOffset = 0.691;

} // namespace

ReplayGainAnalyzer::ReplayGainAnalyzer(double sampleRate)
        : sampleRate_(sampleRate) {
    if (!std::isfinite(sampleRate_) || sampleRate_ <= 0.0) {
        return;
    }

    const double pi = std::acos(-1.0);

    double k = std::tan(pi * kPreFilterF0 / sampleRate_);
    const double vh = std::pow(10.0, kPreFilterG / 20.0);
    const double vb = std::pow(vh, kVbExponent);
    const double a0 = 1.0 + k / kPreFilterQ + k * k;
    const double pb0 = (vh + vb * k / kPreFilterQ + k * k) / a0;
    const double pb1 = 2.0 * (k * k - vh) / a0;
    const double pb2 = (vh - vb * k / kPreFilterQ + k * k) / a0;
    const double pa1 = 2.0 * (k * k - 1.0) / a0;
    const double pa2 = (1.0 - k / kPreFilterQ + k * k) / a0;

    k = std::tan(pi * kRlbF0 / sampleRate_);
    const double denom = 1.0 + k / kRlbQ + k * k;
    const double ra1 = 2.0 * (k * k - 1.0) / denom;
    const double ra2 = (1.0 - k / kRlbQ + k * k) / denom;

    b_[0] = pb0;
    b_[1] = pb0 * -2.0 + pb1;
    b_[2] = pb0 + pb1 * -2.0 + pb2;
    b_[3] = pb1 + pb2 * -2.0;
    b_[4] = pb2;
    a_[0] = 1.0;
    a_[1] = ra1 + pa1;
    a_[2] = ra2 + pa1 * ra1 + pa2;
    a_[3] = pa1 * ra2 + pa2 * ra1;
    a_[4] = pa2 * ra2;

    // ponytail: sample-peak only; 4x true-peak DSP if the player needs it.
    hopSize_ = static_cast<std::size_t>((sampleRate_ + 5.0) / 10.0);
    valid_ = hopSize_ > 0;
    for (int i = 0; i < 5; ++i) {
        valid_ = valid_ && std::isfinite(b_[i]) && std::isfinite(a_[i]);
    }
}

ReplayGainAnalyzer::~ReplayGainAnalyzer() = default;

bool ReplayGainAnalyzer::isValid() const noexcept {
    return valid_;
}

double ReplayGainAnalyzer::filterSample(double x, double* state) noexcept {
    const double v0 =
            x - a_[1] * state[1] - a_[2] * state[2] - a_[3] * state[3] - a_[4] * state[4];
    const double y = b_[0] * v0 + b_[1] * state[1] + b_[2] * state[2] +
            b_[3] * state[3] + b_[4] * state[4];
    state[4] = state[3];
    state[3] = state[2];
    state[2] = state[1];
    state[1] = v0;
    return y;
}

bool ReplayGainAnalyzer::process(const float* samples, std::size_t sampleCount) {
    if (finished_ || !valid_ || (sampleCount > 0 && samples == nullptr)) {
        return false;
    }
    if (sampleCount % 2 != 0) {
        return false;
    }

    for (std::size_t i = 0; i < sampleCount; i += 2) {
        double left = samples[i];
        double right = samples[i + 1];
        if (!std::isfinite(left)) {
            left = 0.0;
        }
        if (!std::isfinite(right)) {
            right = 0.0;
        }
        peak_ = std::max(peak_, std::max(std::fabs(left), std::fabs(right)));

        const double filteredL = filterSample(left, stateL_);
        const double filteredR = filterSample(right, stateR_);
        hopSumL_ += filteredL * filteredL;
        hopSumR_ += filteredR * filteredR;
        if (++hopCount_ == hopSize_) {
            // 400 ms gating block with 75% overlap; per-hop mean squares are
            // folded into block energies in finish().
            hopCount_ = 0;
            hopSumL_ /= static_cast<double>(hopSize_);
            hopSumR_ /= static_cast<double>(hopSize_);
            blocks_.push_back(hopSumL_ + hopSumR_);
            hopSumL_ = 0.0;
            hopSumR_ = 0.0;
        }
    }
    return true;
}

ReplayGainAnalysisResult ReplayGainAnalyzer::finish() {
    if (finished_) {
        return result_;
    }
    finished_ = true;
    if (!valid_) {
        return result_;
    }
    // Trailing partial hop is discarded: incomplete gating blocks are unused.

    // blocks_ holds per-hop (100 ms) mean squares; fold every 4 hops into the
    // overlapping 400 ms block energies, mirroring libebur128's ring buffer.
    std::vector<double> blockEnergies;
    if (blocks_.size() >= 4) {
        blockEnergies.reserve(blocks_.size() - 3);
        for (std::size_t i = 3; i < blocks_.size(); ++i) {
            blockEnergies.push_back(
                    (blocks_[i - 3] + blocks_[i - 2] + blocks_[i - 1] + blocks_[i]) /
                    4.0);
        }
    }
    blocks_ = std::move(blockEnergies);

    const double absGateEnergy = std::pow(10.0, (kAbsoluteGateLUFS + kLevelOffset) / 10.0);

    double sum = 0.0;
    std::size_t count = 0;
    for (const double energy : blocks_) {
        if (energy >= absGateEnergy) {
            sum += energy;
            ++count;
        }
    }
    if (count == 0) {
        return result_;
    }
    const double relativeGate = sum / static_cast<double>(count) *
            std::pow(10.0, -kRelativeGateLU / 10.0);

    double gatedSum = 0.0;
    std::size_t gatedCount = 0;
    for (const double energy : blocks_) {
        if (energy >= absGateEnergy && energy >= relativeGate) {
            gatedSum += energy;
            ++gatedCount;
        }
    }
    if (gatedCount == 0) {
        return result_;
    }
    result_.loudnessLUFS =
            10.0 * std::log10(gatedSum / static_cast<double>(gatedCount)) - kLevelOffset;
    result_.peak = peak_;
    return result_;
}

} // namespace bpm::analysis

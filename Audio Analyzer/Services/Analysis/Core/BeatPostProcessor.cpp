#include "BeatPostProcessor.h"

#include <algorithm>
#include <cmath>
#include <optional>

namespace bpm::analysis {
namespace {

constexpr double kMaxSecsPhaseError = 0.025;
constexpr double kMaxSecsPhaseErrorSum = 0.1;
constexpr int kMaxOutliersCount = 1;
constexpr int kMinRegionBeatCount = 16;

bool isValidBpm(double bpm) {
    return std::isfinite(bpm) && bpm > 0.0;
}

std::optional<double> trySnap(double minBpm,
        double centerBpm,
        double maxBpm,
        double fraction) {
    const double snapped = std::round(centerBpm * fraction) / fraction;
    if (minBpm < snapped && snapped < maxBpm) {
        return snapped;
    }
    return std::nullopt;
}

} // namespace

std::vector<BeatPostProcessor::ConstantRegion>
BeatPostProcessor::retrieveConstantRegions(
        const std::vector<double>& coarseBeats,
        double sampleRate) {
    if (!std::isfinite(sampleRate) || sampleRate <= 0.0 || coarseBeats.size() < 2) {
        return {};
    }

    const double maxPhaseError = kMaxSecsPhaseError * sampleRate;
    const double maxPhaseErrorSum = kMaxSecsPhaseErrorSum * sampleRate;
    int leftIndex = 0;
    int rightIndex = static_cast<int>(coarseBeats.size()) - 1;
    std::vector<ConstantRegion> regions;

    while (leftIndex < static_cast<int>(coarseBeats.size()) - 1) {
        const double meanBeatLength =
                (coarseBeats[rightIndex] - coarseBeats[leftIndex]) /
                (rightIndex - leftIndex);
        if (!std::isfinite(meanBeatLength) || meanBeatLength <= 0.0) {
            return {};
        }

        int outliersCount = 0;
        double ironedBeat = coarseBeats[leftIndex];
        double phaseErrorSum = 0.0;
        int i = leftIndex + 1;
        for (; i <= rightIndex; ++i) {
            ironedBeat += meanBeatLength;
            const double phaseError = ironedBeat - coarseBeats[i];
            phaseErrorSum += phaseError;
            if (std::fabs(phaseError) > maxPhaseError) {
                ++outliersCount;
                if (outliersCount > kMaxOutliersCount || i == leftIndex + 1) {
                    break;
                }
            }
            if (std::fabs(phaseErrorSum) > maxPhaseErrorSum) {
                break;
            }
        }

        if (i > rightIndex) {
            double regionBorderError = 0.0;
            if (rightIndex > leftIndex + 2) {
                const double firstBeatLength =
                        coarseBeats[leftIndex + 1] - coarseBeats[leftIndex];
                const double lastBeatLength =
                        coarseBeats[rightIndex] - coarseBeats[rightIndex - 1];
                regionBorderError = std::fabs(
                        firstBeatLength + lastBeatLength - (2.0 * meanBeatLength));
            }
            if (regionBorderError < maxPhaseError / 2.0) {
                regions.push_back({coarseBeats[leftIndex], meanBeatLength});
                leftIndex = rightIndex;
                rightIndex = static_cast<int>(coarseBeats.size()) - 1;
                continue;
            }
        }
        --rightIndex;
    }

    regions.push_back({coarseBeats.back(), 0.0});
    return regions;
}

double BeatPostProcessor::makeConstantBpm(
        const std::vector<ConstantRegion>& regions,
        double sampleRate,
        double* firstBeat) {
    if (regions.size() < 2 || !std::isfinite(sampleRate) || sampleRate <= 0.0) {
        return 0.0;
    }

    int middleRegionIndex = 0;
    double longestRegionLength = 0.0;
    double longestRegionBeatLength = 0.0;
    for (int i = 0; i < static_cast<int>(regions.size()) - 1; ++i) {
        const double length = regions[i + 1].firstBeat - regions[i].firstBeat;
        if (length > longestRegionLength) {
            longestRegionLength = length;
            longestRegionBeatLength = regions[i].beatLength;
            middleRegionIndex = i;
        }
    }

    if (longestRegionLength <= 0.0 || longestRegionBeatLength <= 0.0) {
        return 0.0;
    }

    int longestRegionNumberOfBeats = static_cast<int>(
            longestRegionLength / longestRegionBeatLength + 0.5);
    if (longestRegionNumberOfBeats <= 0) {
        return 0.0;
    }

    double longestRegionBeatLengthMin = longestRegionBeatLength -
            (kMaxSecsPhaseError * sampleRate) / longestRegionNumberOfBeats;
    double longestRegionBeatLengthMax = longestRegionBeatLength +
            (kMaxSecsPhaseError * sampleRate) / longestRegionNumberOfBeats;
    int startRegionIndex = middleRegionIndex;

    for (int i = 0; i < middleRegionIndex; ++i) {
        const double length = regions[i + 1].firstBeat - regions[i].firstBeat;
        const int numberOfBeats = static_cast<int>(
                length / regions[i].beatLength + 0.5);
        if (numberOfBeats < kMinRegionBeatCount) {
            continue;
        }
        const double thisRegionBeatLengthMin = regions[i].beatLength -
                (kMaxSecsPhaseError * sampleRate) / numberOfBeats;
        const double thisRegionBeatLengthMax = regions[i].beatLength +
                (kMaxSecsPhaseError * sampleRate) / numberOfBeats;
        if (longestRegionBeatLength > thisRegionBeatLengthMin &&
                longestRegionBeatLength < thisRegionBeatLengthMax) {
            const double newLongestRegionLength =
                    regions[middleRegionIndex + 1].firstBeat - regions[i].firstBeat;
            const double beatLengthMin = std::max(
                    longestRegionBeatLengthMin, thisRegionBeatLengthMin);
            const double beatLengthMax = std::min(
                    longestRegionBeatLengthMax, thisRegionBeatLengthMax);
            const int maxNumberOfBeats = static_cast<int>(
                    std::round(newLongestRegionLength / beatLengthMin));
            const int minNumberOfBeats = static_cast<int>(
                    std::round(newLongestRegionLength / beatLengthMax));
            if (minNumberOfBeats != maxNumberOfBeats || minNumberOfBeats <= 0) {
                continue;
            }
            const double newBeatLength = newLongestRegionLength / minNumberOfBeats;
            if (newBeatLength > longestRegionBeatLengthMin &&
                    newBeatLength < longestRegionBeatLengthMax) {
                longestRegionLength = newLongestRegionLength;
                longestRegionBeatLength = newBeatLength;
                longestRegionNumberOfBeats = minNumberOfBeats;
                longestRegionBeatLengthMin = longestRegionBeatLength -
                        (kMaxSecsPhaseError * sampleRate) / longestRegionNumberOfBeats;
                longestRegionBeatLengthMax = longestRegionBeatLength +
                        (kMaxSecsPhaseError * sampleRate) / longestRegionNumberOfBeats;
                startRegionIndex = i;
                break;
            }
        }
    }

    for (int i = static_cast<int>(regions.size()) - 2;
            i > middleRegionIndex;
            --i) {
        const double length = regions[i + 1].firstBeat - regions[i].firstBeat;
        const int numberOfBeats = static_cast<int>(
                length / regions[i].beatLength + 0.5);
        if (numberOfBeats < kMinRegionBeatCount) {
            continue;
        }
        const double thisRegionBeatLengthMin = regions[i].beatLength -
                (kMaxSecsPhaseError * sampleRate) / numberOfBeats;
        const double thisRegionBeatLengthMax = regions[i].beatLength +
                (kMaxSecsPhaseError * sampleRate) / numberOfBeats;
        if (longestRegionBeatLength > thisRegionBeatLengthMin &&
                longestRegionBeatLength < thisRegionBeatLengthMax) {
            const double newLongestRegionLength =
                    regions[i + 1].firstBeat - regions[startRegionIndex].firstBeat;
            const double minBeatLength = std::max(
                    longestRegionBeatLengthMin, thisRegionBeatLengthMin);
            const double maxBeatLength = std::min(
                    longestRegionBeatLengthMax, thisRegionBeatLengthMax);
            const int maxNumberOfBeats = static_cast<int>(
                    std::round(newLongestRegionLength / minBeatLength));
            const int minNumberOfBeats = static_cast<int>(
                    std::round(newLongestRegionLength / maxBeatLength));
            if (minNumberOfBeats != maxNumberOfBeats || minNumberOfBeats <= 0) {
                continue;
            }
            const double newBeatLength = newLongestRegionLength / minNumberOfBeats;
            if (newBeatLength > longestRegionBeatLengthMin &&
                    newBeatLength < longestRegionBeatLengthMax) {
                longestRegionLength = newLongestRegionLength;
                longestRegionBeatLength = newBeatLength;
                longestRegionNumberOfBeats = minNumberOfBeats;
                break;
            }
        }
    }

    longestRegionBeatLengthMin = longestRegionBeatLength -
            (kMaxSecsPhaseError * sampleRate) / longestRegionNumberOfBeats;
    longestRegionBeatLengthMax = longestRegionBeatLength +
            (kMaxSecsPhaseError * sampleRate) / longestRegionNumberOfBeats;

    const double minRoundBpm = 60.0 * sampleRate / longestRegionBeatLengthMax;
    const double maxRoundBpm = 60.0 * sampleRate / longestRegionBeatLengthMin;
    const double centerBpm = 60.0 * sampleRate / longestRegionBeatLength;
    const double roundBpm = roundBpmWithinRange(minRoundBpm, centerBpm, maxRoundBpm);
    if (!isValidBpm(roundBpm)) {
        return 0.0;
    }

    if (firstBeat != nullptr) {
        const double roundedBeatLength = 60.0 * sampleRate / roundBpm;
        *firstBeat = std::fmod(regions[startRegionIndex].firstBeat, roundedBeatLength);
    }
    return roundBpm;
}

double BeatPostProcessor::roundBpmWithinRange(
        double minBpm, double centerBpm, double maxBpm) {
    if (!isValidBpm(minBpm) || !isValidBpm(centerBpm) || !isValidBpm(maxBpm)) {
        return centerBpm;
    }

    if (auto value = trySnap(minBpm, centerBpm, maxBpm, 1.0)) {
        return *value;
    }
    if (centerBpm < 85.0) {
        if (auto value = trySnap(minBpm, centerBpm, maxBpm, 2.0)) {
            return *value;
        }
    }
    if (centerBpm > 127.0) {
        if (auto value = trySnap(minBpm, centerBpm, maxBpm, 2.0 / 3.0)) {
            return *value;
        }
    }
    if (auto value = trySnap(minBpm, centerBpm, maxBpm, 3.0)) {
        return *value;
    }
    if (auto value = trySnap(minBpm, centerBpm, maxBpm, 12.0)) {
        return *value;
    }
    return centerBpm;
}

double BeatPostProcessor::adjustPhase(
        double firstBeat,
        double bpm,
        double sampleRate,
        const std::vector<double>& beats) {
    if (!isValidBpm(bpm) || !std::isfinite(sampleRate) || sampleRate <= 0.0) {
        return firstBeat;
    }

    const double beatLength = 60.0 * sampleRate / bpm;
    const double startOffset = std::fmod(firstBeat, beatLength);
    double offsetAdjust = 0.0;
    double offsetAdjustCount = 0.0;
    for (const double beat : beats) {
        double offset = std::fmod(beat - startOffset, beatLength);
        if (offset > beatLength / 2.0) {
            offset -= beatLength;
        }
        if (std::fabs(offset) < kMaxSecsPhaseError * sampleRate) {
            offsetAdjust += offset;
            ++offsetAdjustCount;
        }
    }
    if (offsetAdjustCount == 0.0) {
        return firstBeat;
    }
    return firstBeat + offsetAdjust / offsetAdjustCount;
}

FixedTempoResult BeatPostProcessor::makeFixedTempo(
        const std::vector<double>& coarseBeats,
        double sampleRate) {
    FixedTempoResult result;
    if (!std::isfinite(sampleRate) || sampleRate <= 0.0 || coarseBeats.size() < 2) {
        return result;
    }

    const auto regions = retrieveConstantRegions(coarseBeats, sampleRate);
    if (regions.empty()) {
        return result;
    }

    double firstBeat = 0.0;
    const double bpm = makeConstantBpm(regions, sampleRate, &firstBeat);
    if (!isValidBpm(bpm) || !std::isfinite(firstBeat)) {
        return result;
    }

    firstBeat = adjustPhase(firstBeat, bpm, sampleRate, coarseBeats);
    result.bpm = bpm;
    result.firstBeatFrame = static_cast<std::int64_t>(std::llround(firstBeat));
    return result;
}

} // namespace bpm::analysis

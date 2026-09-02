#pragma once

#include <cstdint>
#include <vector>

namespace bpm::analysis {

struct FixedTempoResult {
    double bpm = 0.0;
    std::int64_t firstBeatFrame = -1;
};

class BeatPostProcessor {
public:
    static FixedTempoResult makeFixedTempo(
            const std::vector<double>& coarseBeats,
            double sampleRate);

private:
    struct ConstantRegion {
        double firstBeat = 0.0;
        double beatLength = 0.0;
    };

    static std::vector<ConstantRegion> retrieveConstantRegions(
            const std::vector<double>& coarseBeats,
            double sampleRate);
    static double makeConstantBpm(
            const std::vector<ConstantRegion>& regions,
            double sampleRate,
            double* firstBeat);
    static double roundBpmWithinRange(
            double minBpm, double centerBpm, double maxBpm);
    static double adjustPhase(
            double firstBeat,
            double bpm,
            double sampleRate,
            const std::vector<double>& beats);
};

} // namespace bpm::analysis

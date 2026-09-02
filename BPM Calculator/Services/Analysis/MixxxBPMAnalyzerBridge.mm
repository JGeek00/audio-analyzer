#import "MixxxBPMAnalyzerBridge.h"

#include <memory>

#include "Core/MixxxBpmAnalyzer.h"

@implementation BPMCoreResult

- (instancetype)initWithBpm:(double)bpm
             firstBeatFrame:(long long)firstBeatFrame
                  sampleRate:(double)sampleRate
              rawBeatFrames:(NSArray<NSNumber*>*)rawBeatFrames {
    self = [super init];
    if (self) {
        _bpm = bpm;
        _firstBeatFrame = firstBeatFrame;
        _sampleRate = sampleRate;
        _rawBeatFrames = [rawBeatFrames copy];
    }
    return self;
}

@end

@interface MixxxBPMAnalyzerBridge () {
    std::unique_ptr<bpm::analysis::MixxxBpmAnalyzer> _analyzer;
    NSString* _lastErrorMessage;
}
@end

@implementation MixxxBPMAnalyzerBridge

- (nullable instancetype)initWithSampleRate:(double)sampleRate {
    self = [super init];
    if (!self) {
        return nil;
    }

    _analyzer = std::make_unique<bpm::analysis::MixxxBpmAnalyzer>(sampleRate);
    if (!_analyzer->isValid()) {
        _lastErrorMessage = @"Invalid sample rate for the BPM analyzer.";
        return nil;
    }
    return self;
}

- (BOOL)processSamples:(NSData*)interleavedFloat32Stereo {
    if (!_analyzer) {
        _lastErrorMessage = @"The BPM analyzer is not initialized.";
        return NO;
    }
    if (interleavedFloat32Stereo.length % sizeof(float) != 0) {
        _lastErrorMessage = @"The PCM block does not contain complete float32 samples.";
        return NO;
    }

    const std::size_t sampleCount =
            interleavedFloat32Stereo.length / sizeof(float);
    const auto* samples = static_cast<const float*>(interleavedFloat32Stereo.bytes);
    if (!_analyzer->process(samples, sampleCount)) {
        _lastErrorMessage = @"The PCM block does not satisfy the interleaved stereo contract.";
        return NO;
    }
    return YES;
}

- (nullable BPMCoreResult*)finish {
    if (!_analyzer) {
        _lastErrorMessage = @"The BPM analyzer is not initialized.";
        return nil;
    }

    const bpm::analysis::BpmAnalysisResult result = _analyzer->finish();
    NSMutableArray<NSNumber*>* rawBeatFrames =
            [NSMutableArray arrayWithCapacity:result.rawBeatFrames.size()];
    for (const double beatFrame : result.rawBeatFrames) {
        [rawBeatFrames addObject:@(beatFrame)];
    }
    return [[BPMCoreResult alloc]
            initWithBpm:result.bpm
            firstBeatFrame:result.firstBeatFrame
            sampleRate:result.sampleRate
            rawBeatFrames:rawBeatFrames];
}

- (NSString*)lastErrorMessage {
    return _lastErrorMessage ?: @"";
}

@end

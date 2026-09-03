#import "MixxxBPMAnalyzerBridge.h"

#include <memory>

#include "Core/MixxxBpmAnalyzer.h"
#include "Core/MixxxKeyAnalyzer.h"

@implementation KeyChangeCoreResult

- (instancetype)initWithKeyID:(NSInteger)keyID frame:(long long)frame {
    self = [super init];
    if (self) {
        _keyID = keyID;
        _frame = frame;
    }
    return self;
}

@end

@implementation KeyCoreResult

- (instancetype)initWithGlobalKeyID:(NSInteger)globalKeyID
                            keyText:(NSString*)keyText
                         sampleRate:(double)sampleRate
                         keyChanges:(NSArray<KeyChangeCoreResult*>*)keyChanges {
    self = [super init];
    if (self) {
        _globalKeyID = globalKeyID;
        _keyText = [keyText copy];
        _sampleRate = sampleRate;
        _keyChanges = [keyChanges copy];
    }
    return self;
}

@end

@implementation BPMCoreResult

- (instancetype)initWithBpm:(double)bpm
             firstBeatFrame:(long long)firstBeatFrame
                   sampleRate:(double)sampleRate
               rawBeatFrames:(NSArray<NSNumber*>*)rawBeatFrames
                  keyResult:(KeyCoreResult*)keyResult {
    self = [super init];
    if (self) {
        _bpm = bpm;
        _firstBeatFrame = firstBeatFrame;
        _sampleRate = sampleRate;
        _rawBeatFrames = [rawBeatFrames copy];
        _keyResult = keyResult;
    }
    return self;
}

@end

@interface MixxxBPMAnalyzerBridge () {
    std::unique_ptr<bpm::analysis::MixxxBpmAnalyzer> _analyzer;
    std::unique_ptr<bpm::analysis::MixxxKeyAnalyzer> _keyAnalyzer;
    NSString* _lastErrorMessage;
}
@end

@implementation MixxxBPMAnalyzerBridge

- (nullable instancetype)initWithSampleRate:(double)sampleRate {
    return [self initWithSampleRate:sampleRate totalFrameCount:0];
}

- (nullable instancetype)initWithSampleRate:(double)sampleRate
                             totalFrameCount:(long long)totalFrameCount {
    self = [super init];
    if (!self) {
        return nil;
    }

    _analyzer = std::make_unique<bpm::analysis::MixxxBpmAnalyzer>(sampleRate);
    if (!_analyzer->isValid()) {
        _lastErrorMessage = @"Invalid sample rate for the BPM analyzer.";
        return nil;
    }
    _keyAnalyzer = std::make_unique<bpm::analysis::MixxxKeyAnalyzer>(
            sampleRate, totalFrameCount);
    if (!_keyAnalyzer->isValid()) {
        _lastErrorMessage = @"Invalid sample rate for the key analyzer.";
        return nil;
    }
    return self;
}

- (BOOL)processSamples:(NSData*)interleavedFloat32Stereo {
    if (!_analyzer || !_keyAnalyzer) {
        _lastErrorMessage = @"The audio analyzer is not initialized.";
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
    if (!_keyAnalyzer->process(samples, sampleCount)) {
        _lastErrorMessage = @"The PCM block does not satisfy the key analyzer contract.";
        return NO;
    }
    return YES;
}

- (nullable BPMCoreResult*)finish {
    if (!_analyzer || !_keyAnalyzer) {
        _lastErrorMessage = @"The audio analyzer is not initialized.";
        return nil;
    }

    const bpm::analysis::BpmAnalysisResult result = _analyzer->finish();
    const bpm::analysis::KeyAnalysisResult keyResult = _keyAnalyzer->finish();
    NSMutableArray<NSNumber*>* rawBeatFrames =
            [NSMutableArray arrayWithCapacity:result.rawBeatFrames.size()];
    for (const double beatFrame : result.rawBeatFrames) {
        [rawBeatFrames addObject:@(beatFrame)];
    }
    NSMutableArray<KeyChangeCoreResult*>* keyChanges =
            [NSMutableArray arrayWithCapacity:keyResult.keyChanges.size()];
    for (const auto& change : keyResult.keyChanges) {
        [keyChanges addObject:[[KeyChangeCoreResult alloc]
                initWithKeyID:change.keyID frame:change.frame]];
    }
    KeyCoreResult* coreKeyResult = [[KeyCoreResult alloc]
            initWithGlobalKeyID:keyResult.globalKeyID
            keyText:[NSString stringWithUTF8String:keyResult.keyText.c_str()]
            sampleRate:keyResult.sampleRate
            keyChanges:keyChanges];
    return [[BPMCoreResult alloc]
            initWithBpm:result.bpm
            firstBeatFrame:result.firstBeatFrame
            sampleRate:result.sampleRate
            rawBeatFrames:rawBeatFrames
            keyResult:coreKeyResult];
}

- (NSString*)lastErrorMessage {
    return _lastErrorMessage ?: @"";
}

@end

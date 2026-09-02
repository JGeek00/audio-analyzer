#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BPMCoreResult : NSObject
@property(nonatomic, readonly) double bpm;
@property(nonatomic, readonly) long long firstBeatFrame;
@property(nonatomic, readonly) double sampleRate;
@property(nonatomic, copy, readonly) NSArray<NSNumber*>* rawBeatFrames;

- (instancetype)initWithBpm:(double)bpm
             firstBeatFrame:(long long)firstBeatFrame
                  sampleRate:(double)sampleRate
              rawBeatFrames:(NSArray<NSNumber*>*)rawBeatFrames;
@end

@interface MixxxBPMAnalyzerBridge : NSObject
- (nullable instancetype)initWithSampleRate:(double)sampleRate;
- (BOOL)processSamples:(NSData*)interleavedFloat32Stereo;
- (nullable BPMCoreResult*)finish;
@property(nonatomic, copy, readonly) NSString* lastErrorMessage;
@end

NS_ASSUME_NONNULL_END

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KeyChangeCoreResult : NSObject
@property(nonatomic, readonly) NSInteger keyID;
@property(nonatomic, readonly) long long frame;

- (instancetype)initWithKeyID:(NSInteger)keyID frame:(long long)frame;
@end

@interface KeyCoreResult : NSObject
@property(nonatomic, readonly) NSInteger globalKeyID;
@property(nonatomic, copy, readonly) NSString* keyText;
@property(nonatomic, readonly) double sampleRate;
@property(nonatomic, copy, readonly) NSArray<KeyChangeCoreResult*>* keyChanges;

- (instancetype)initWithGlobalKeyID:(NSInteger)globalKeyID
                            keyText:(NSString*)keyText
                         sampleRate:(double)sampleRate
                         keyChanges:(NSArray<KeyChangeCoreResult*>*)keyChanges;
@end

@interface BPMCoreResult : NSObject
@property(nonatomic, readonly) double bpm;
@property(nonatomic, readonly) long long firstBeatFrame;
@property(nonatomic, readonly) double sampleRate;
@property(nonatomic, copy, readonly) NSArray<NSNumber*>* rawBeatFrames;
@property(nonatomic, readonly) KeyCoreResult* keyResult;

- (instancetype)initWithBpm:(double)bpm
              firstBeatFrame:(long long)firstBeatFrame
                   sampleRate:(double)sampleRate
               rawBeatFrames:(NSArray<NSNumber*>*)rawBeatFrames
                  keyResult:(KeyCoreResult*)keyResult;
@end

@interface MixxxBPMAnalyzerBridge : NSObject
- (nullable instancetype)initWithSampleRate:(double)sampleRate;
- (nullable instancetype)initWithSampleRate:(double)sampleRate
                             totalFrameCount:(long long)totalFrameCount;
- (BOOL)processSamples:(NSData*)interleavedFloat32Stereo;
- (nullable BPMCoreResult*)finish;
@property(nonatomic, copy, readonly) NSString* lastErrorMessage;
@end

NS_ASSUME_NONNULL_END

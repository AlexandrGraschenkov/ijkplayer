//
//  IJKMediaHelper.h
//  IJKMediaFramework
//
//  Created by Alexander Graschenkov on 04.11.2018.
//  Copyright © 2018 bilibili. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "IJKSubtitles.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct VideoInfoObjc {
    double duration;
    BOOL subtitles;
} VideoInfoObjc;

typedef void (^IJKAudioReaderDataCallback)(NSData *audioData, NSTimeInterval position);
typedef void (^IJKAudioReaderProgressCallback)(NSTimeInterval position, NSTimeInterval duration);
typedef void (^IJKAudioReaderCompletion)(NSError * _Nullable error);

@interface IJKAudioReader : NSObject
- (instancetype)initWithPath:(NSString *)path audioStreamIndex:(NSInteger)audioStreamIndex startTime:(NSTimeInterval)startTime endTime:(NSTimeInterval)endTime;
// `headers` are applied only to http(s) inputs (online videos share the playback request's headers).
- (instancetype)initWithPath:(NSString *)path audioStreamIndex:(NSInteger)audioStreamIndex startTime:(NSTimeInterval)startTime endTime:(NSTimeInterval)endTime headers:(NSDictionary<NSString *, NSString *> * _Nullable)headers;
- (void)startWithAudioCallback:(IJKAudioReaderDataCallback)audioCallback progress:(IJKAudioReaderProgressCallback _Nullable)progress completion:(IJKAudioReaderCompletion)completion;
- (void)cancel;
@end

@interface IJKMediaHelper : NSObject
+ (nullable UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTime:(NSTimeInterval)time aspectSize:(CGSize)size;
+ (nullable UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTimePercent:(double)timePercent aspectSize:(CGSize)size; // 0..1
+ (NSTimeInterval)durationOfVideoAtPath:(NSString *)path;
+ (int)getSubtitlesCount:(NSString *)path;
// Absolute ffmpeg stream indexes of the file's audio streams, in container order.
+ (NSArray<NSNumber *> *)audioStreamIndexesOfVideoAtPath:(NSString *)path NS_SWIFT_NAME(audioStreamIndexes(ofVideoAtPath:));
+ (VideoInfoObjc)getInfo:(NSString *)path;
+ (void)readSubtitles:(NSString *)videoPath saveFolder:(NSString *)saveFolder;
@end

NS_ASSUME_NONNULL_END

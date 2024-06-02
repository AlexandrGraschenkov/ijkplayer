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

typedef enum TrackCodecType : NSUInteger {
    TrackCodecTypeVideo,
    TrackCodecTypeAudio,
    TrackCodecTypeSubtitle,
} TrackCodecType;

@interface TrackInfoObjc: NSObject {
    int index;
    NSString *codecName;
    TrackCodecType type;
    CGSize resolution;
    long long bitrate;
    
    NSString *_Nullable name;
    NSString *_Nullable language;
};
@end

@interface IJKMediaHelper : NSObject
+ (nullable UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTime:(NSTimeInterval)time aspectSize:(CGSize)size;
+ (nullable UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTimePercent:(double)timePercent aspectSize:(CGSize)size; // 0..1
+ (NSTimeInterval)durationOfVideoAtPath:(NSString *)path;
+ (int)getSubtitlesCount:(NSString *)path;
+ (VideoInfoObjc)getInfo:(NSString *)path;

+ (int)downloadVideoStream:(NSURL*)url toLocation:(NSURL*)location chooseTracks:(NSArray<TrackInfoObjc *> *(^)(NSArray<TrackInfoObjc *> *))filterClosure;

+ (void)readSubtitles:(NSString *)videoPath saveFolder:(NSString *)saveFolder;
+ (NSArray<IJKSubtitles *> *)readSubtitles:(NSString *)videoPath;
//+ (void)printSubtitles:(NSString *)path;
@end

NS_ASSUME_NONNULL_END

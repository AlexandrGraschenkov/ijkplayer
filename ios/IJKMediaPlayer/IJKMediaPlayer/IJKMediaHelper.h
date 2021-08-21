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

@interface IJKMediaHelper : NSObject
+ (nullable UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTime:(NSTimeInterval)time;
+ (nullable UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTimePercent:(double)timePercent; // 0..1
+ (NSTimeInterval)durationOfVideoAtPath:(NSString *)path;
+ (BOOL)hasSubtitles:(NSString *)path;
+ (VideoInfoObjc)getInfo:(NSString *)path;

+ (void)readSubtitles:(NSString *)videoPath saveFolder:(NSString *)saveFolder;
+ (NSArray<IJKSubtitles *> *)readSubtitles:(NSString *)videoPath;
//+ (void)printSubtitles:(NSString *)path;
@end

NS_ASSUME_NONNULL_END

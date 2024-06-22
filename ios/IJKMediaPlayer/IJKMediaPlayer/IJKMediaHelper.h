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
+ (nullable UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTime:(NSTimeInterval)time aspectSize:(CGSize)size;
+ (nullable UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTimePercent:(double)timePercent aspectSize:(CGSize)size; // 0..1
+ (NSTimeInterval)durationOfVideoAtPath:(NSString *)path;
+ (int)getSubtitlesCount:(NSString *)path;
+ (VideoInfoObjc)getInfo:(NSString *)path;
+ (void)readSubtitles:(NSString *)videoPath saveFolder:(NSString *)saveFolder;
@end

NS_ASSUME_NONNULL_END

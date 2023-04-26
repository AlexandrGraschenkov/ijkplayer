//
//  IJChapter.m
//  IJKMediaPlayer
//
//  Created by Alexander Graschenkov on 22.04.2023.
//  Copyright © 2023 bilibili. All rights reserved.
//

#import "IJChapter.h"
#include "ijkmedia/ijkplayer/ios/ijkplayer_ios.h"
#include "IJTrackMetadata.h"

struct AVDictionary;
struct AVChapter;

@interface IJTrackMetadata (Hidden)
+ (NSDictionary *)AVDictionaryToNSDictionary:(AVDictionary *)avDictionary;
@end

@implementation IJChapter

+ (instancetype)chapterWithAVDictionary:(AVDictionary *)avChapterDict {
    if (avChapterDict == NULL) { return NULL; }
    NSDictionary *dict = [IJTrackMetadata AVDictionaryToNSDictionary:avChapterDict];
    
    NSString *start = dict[@(IJKM_C_KEY_START)];
    NSString *end = dict[@(IJKM_C_KEY_END)];
    if (!start || ![start isKindOfClass:[NSString class]]) {
        return NULL;
    }
    if (!end || ![end isKindOfClass:[NSString class]]) {
        return NULL;
    }
    
    IJChapter *chapter = [IJChapter new];
    chapter.startTime = start.doubleValue / 1000.0;
    chapter.endTime = end.doubleValue / 1000.0;
    chapter.metadata = dict;
    chapter.title = dict[@(IJKM_C_KEY_TITLE)] ?: @"Unknown Chapter";
    
    NSString *idStr = dict[@(IJKM_C_KEY_ID)];
    if (idStr && [idStr isKindOfClass:[NSString class]]) {
        chapter.id = [idStr intValue];
    } else {
        chapter.id = 0;
    }
    
    return chapter;
}
@end

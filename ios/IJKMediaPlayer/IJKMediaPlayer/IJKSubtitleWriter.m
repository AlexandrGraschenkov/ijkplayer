//
//  IJKSubtitleWriter.m
//  IJKMediaFramework
//
//  Created by Alexander Graschenkov on 17/01/2019.
//  Copyright © 2019 bilibili. All rights reserved.
//

#import "IJKSubtitleWriter.h"
#include <inttypes.h>


NSDictionary * IJKFoundationBrigeOfAVDictionary(AVDictionary * avDictionary)
{
    if (avDictionary == NULL) return nil;
    
    int count = av_dict_count(avDictionary);
    if (count <= 0) return nil;
    
    NSMutableDictionary * dictionary = [NSMutableDictionary dictionary];
    
    AVDictionaryEntry * entry = NULL;
    while ((entry = av_dict_get(avDictionary, "", entry, AV_DICT_IGNORE_SUFFIX))) {
        @autoreleasepool {
            NSString * key = [NSString stringWithUTF8String:entry->key];
            NSString * value = [NSString stringWithUTF8String:entry->value];
            [dictionary setObject:value forKey:key];
        }
    }
    
    return dictionary;
}

@implementation IJKMetadata

+ (instancetype)metadataWithAVDictionary:(AVDictionary *)avDictionary
{
    return [[self alloc] initWithAVDictionary:avDictionary];
}

- (instancetype)initWithAVDictionary:(AVDictionary *)avDictionary
{
    if (self = [super init])
    {
        NSDictionary * dic = IJKFoundationBrigeOfAVDictionary(avDictionary);
        
        self.metadata = dic;
        
        self.language = [dic objectForKey:@"language"];
        if (![self.language isKindOfClass:[NSString class]]) {
            self.language = @"";
        }
        self.title = [dic objectForKey:@"title"];
        if (![self.title isKindOfClass:[NSString class]]) {
            self.title = @"";
        }
        self.BPS = [[dic objectForKey:@"BPS"] longLongValue];
        self.duration = [dic objectForKey:@"DURATION"];
        self.number_of_bytes = [[dic objectForKey:@"NUMBER_OF_BYTES"] longLongValue];
        self.number_of_frames = [[dic objectForKey:@"NUMBER_OF_FRAMES"] longLongValue];
    }
    return self;
}

@end




@interface IJKSubtitleWriter () {
    int idx;
    FILE *file;
    char fromTime[13];
    char toTime[13];
}
@property (nonatomic, strong) NSString *savePath;
@end

void fillTime(char *str, int64_t time) {
    int64_t ms = time % 1000; time /= 1000;
    int64_t s = time % 60; time /= 60;
    int64_t m = time % 60; time /= 60;
    int64_t h = time;
    snprintf(str, 13, "%02"PRId64":%02"PRId64":%02"PRId64",%03"PRId64"", h, m, s, ms);
}

@implementation IJKSubtitleWriter

+ (NSString *)subtitleName:(NSString *)title track:(int)trackIdx subIdx:(int)subIdx lang:(NSString *)lang {
    return [NSString stringWithFormat:@"subtitle|#%d#|%@|{%d}|<%@>.srt",trackIdx,title?:@"",subIdx, lang ?: @""];
}

+ (instancetype)writerFile:(NSString*)savePath trackIdx:(int)track {
    IJKSubtitleWriter *writer = [IJKSubtitleWriter new];
    writer->_trackIdx = track;
    writer->idx = 0;
    writer.savePath = savePath;
    return writer;
}

- (void)addSub:(uint8_t *)text startTime:(int64_t)startTime duration:(int64_t)duration {
    if (!file) return;
    
    idx++;
    fillTime(fromTime, startTime);
    fillTime(toTime, startTime + duration);
    fprintf(file, "%d\n%s --> %s\n", idx, fromTime, toTime);
    int text_idx = 0;
    while (text[text_idx] != 0) {
        fprintf(file,"%c",text[text_idx]);
        text_idx++;
    }
    fprintf(file, "\n\n");
}

- (void)open {
    if (file) return;
    file = fopen([self.savePath cStringUsingEncoding:kCFStringEncodingUTF8], "w");
}

- (void)close {
    if (file) {
        fclose(file);
        file = nil;
    }
}

- (void)dealloc {
    if (file) {
        fclose(file);
    }
}
@end

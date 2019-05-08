//
//  IJTrackMetadata.m
//  IJKMediaFramework
//
//  Created by Alexander Graschenkov on 19.06.2018.
//  Copyright © 2018 bilibili. All rights reserved.
//

#import "IJTrackMetadata.h"
#include "ijkmedia/ijkplayer/ios/ijkplayer_ios.h"

@implementation IJTrackMetadata


+ (NSDictionary *)AVDictionaryToNSDictionary:(AVDictionary *) avDictionary
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
+ (instancetype)metadataWithAVDictionary:(AVDictionary *)avDictionary
{
    return [[self alloc] initWithAVDictionary:avDictionary];
}

- (instancetype)initWithAVDictionary:(AVDictionary *)avDictionary
{
    if (self = [super init])
    {
        NSDictionary * dic = [IJTrackMetadata AVDictionaryToNSDictionary:avDictionary];
        
//        NSLog(@"Dict: %@", dic);
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

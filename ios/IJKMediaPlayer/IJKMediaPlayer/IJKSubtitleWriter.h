//
//  IJKSubtitleWriter.h
//  IJKMediaFramework
//
//  Created by Alexander Graschenkov on 17/01/2019.
//  Copyright © 2019 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <libavformat/avformat.h>

@interface IJKMetadata : NSObject

+ (instancetype)metadataWithAVDictionary:(AVDictionary *)avDictionary;

@property (nonatomic, strong) NSDictionary * metadata;

@property (nonatomic, copy) NSString * language;
@property (nonatomic, copy) NSString * title;
@property (nonatomic, assign) long long BPS;
@property (nonatomic, copy) NSString * duration;
@property (nonatomic, assign) long long number_of_bytes;
@property (nonatomic, assign) long long number_of_frames;

@end


@interface IJKSubtitleWriter : NSObject

+ (NSString *)subtitleName:(NSString *)title
                     track:(int)trackIdx
                    subIdx:(int)subIdx
                      lang:(NSString *)lang;


+ (instancetype)writerFile:(NSString*)savePath trackIdx:(int)track;

- (void)addSub:(uint8_t *)text
     startTime:(int64_t)startTime
      duration:(int64_t)duration;

- (void)addSub:(uint8_t *)text
           len:(int)len
     startTime:(int64_t)startTime
      duration:(int64_t)duration;

// Manual sub creation line by line
- (void)addNewSubWithStartTime:(int64_t)startTime
                      duration:(int64_t)duration;
- (void)addNewSubText:(const char *)text;
- (void)finishSub;


- (void)open;
- (void)close;


@property (nonatomic, readonly) int trackIdx;
@end



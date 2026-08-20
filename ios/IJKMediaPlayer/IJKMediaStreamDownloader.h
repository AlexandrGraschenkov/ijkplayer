//
//  IJKMediaStreamDownloader.h
//  IJKMediaPlayer
//
//  Created by Alexander Graschenkov on 02.06.2024.
//  Copyright © 2024 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


typedef enum TrackCodecType : NSUInteger {
    TrackCodecTypeVideo,
    TrackCodecTypeAudio,
    TrackCodecTypeSubtitle,
} TrackCodecType;

@interface TrackInfoObjc: NSObject
@property (nonatomic, assign) int index;
@property (nonatomic, strong) NSString *codecName;
@property (nonatomic, assign) TrackCodecType type;
@property (nonatomic, assign) CGSize resolution;
@property (nonatomic, assign) long long bitrate;
@property (nonatomic, assign) long long variantBitrate;
@property (nonatomic, strong, nullable) NSString *name;
@property (nonatomic, strong, nullable) NSString *language;
@end

@interface ProgramInfoObjc : NSObject
@property (nonatomic, strong) NSArray<NSNumber *> *streamIndexes;
@property (nonatomic, strong, nullable) NSDictionary *metadata;
@end

typedef NSArray<TrackInfoObjc *> * _Nonnull (^FilterTracksClosure)(NSArray<TrackInfoObjc *> * _Nonnull, NSArray<ProgramInfoObjc *> * _Nullable);
typedef void(^DownloadProgressClosure)(BOOL finished, BOOL canceled, long long loaded, long long total, NSError * _Nullable error);


@interface IJKMediaStreamDownloader : NSObject
+ (int)downloadVideoStream:(NSURL*)url 
                toLocation:(NSURL*)location
              chooseTracks:(FilterTracksClosure)filterClosure
                  progress:(DownloadProgressClosure)progress
                  canceled:(BOOL*)canceled;

/// `headers` уходят в ffmpeg как опции ввода (`user_agent` + `headers`), в том числе
/// на дочерние запросы сегментов HLS. Без них хостинги вроде googlevideo отвечают 403.
+ (int)downloadVideoStream:(NSURL*)url
                toLocation:(NSURL*)location
                   headers:(NSDictionary<NSString *, NSString *> * _Nullable)headers
              chooseTracks:(FilterTracksClosure)filterClosure
                  progress:(DownloadProgressClosure)progress
                  canceled:(BOOL*)canceled;

+ (int)downloadVideoStream:(NSURL*)url
                toLocation:(NSURL*)location;
@end

NS_ASSUME_NONNULL_END

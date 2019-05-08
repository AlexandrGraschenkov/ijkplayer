//
//  IJKSubtitles.h
//  IJKMediaFramework
//
//  Created by Alexander Graschenkov on 23/01/2019.
//  Copyright © 2019 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IJKSubContent : NSObject
+ (instancetype)content:(uint8_t *)text startTime:(int64_t)startTime endTime:(int64_t)endTime numb:(int)number;
@property (nonatomic, strong) NSString *text;
@property (nonatomic, assign) double fromTime;
@property (nonatomic, assign) double toTime;
@property (nonatomic, assign) int number;
@end

@interface IJKSubtitles : NSObject
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *language;
@property (nonatomic, assign) int trackIdx;
@property (nonatomic, strong) NSMutableArray<IJKSubContent *> *contents;
@end

NS_ASSUME_NONNULL_END

//
//  IJKSubtitles.m
//  IJKMediaFramework
//
//  Created by Alexander Graschenkov on 23/01/2019.
//  Copyright © 2019 bilibili. All rights reserved.
//

#import "IJKSubtitles.h"

@implementation IJKSubContent

+ (instancetype)content:(uint8_t *)text startTime:(int64_t)startTime endTime:(int64_t)endTime numb:(int)number {
    IJKSubContent *content = [IJKSubContent new];
    content->_text = [NSString stringWithUTF8String:(const char *)text];
    content->_fromTime = startTime / 1000.0;
    content->_toTime = endTime / 1000.0;
    content->_number = number;
    return content;
}

@end

@implementation IJKSubtitles
- (instancetype)init
{
    self = [super init];
    if (self) {
        _title = @"";
        _language = @"";
        _trackIdx = 0;
        _contents = [NSMutableArray new];
    }
    return self;
}
@end

//
//  IJTrackMetadata.h
//  IJKMediaFramework
//
//  Created by Alexander Graschenkov on 19.06.2018.
//  Copyright © 2018 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>

struct AVDictionary;

@interface IJTrackMetadata : NSObject

@property (nonatomic, strong) NSDictionary * metadata;

@property (nonatomic, assign) NSInteger index;

@property (nonatomic, copy) NSString * language;
@property (nonatomic, copy) NSString * title;
@property (nonatomic, assign) long long BPS;
@property (nonatomic, copy) NSString * duration;
@property (nonatomic, assign) long long number_of_bytes;
@property (nonatomic, assign) long long number_of_frames;

@end

//
//  IJChapter.h
//  IJKMediaPlayer
//
//  Created by Alexander Graschenkov on 22.04.2023.
//  Copyright © 2023 bilibili. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface IJChapter : NSObject
@property (nonatomic, strong) NSDictionary * metadata;
@property (nonatomic, copy) NSString * title;
@property (nonatomic, assign) double startTime;
@property (nonatomic, assign) double endTime;
@property (nonatomic, assign) int id;
@end


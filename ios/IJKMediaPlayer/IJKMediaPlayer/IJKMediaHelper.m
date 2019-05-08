//
//  IJKMediaHelper.m
//  IJKMediaFramework
//
//  Created by Alexander Graschenkov on 04.11.2018.
//  Copyright © 2018 bilibili. All rights reserved.
//

#import "IJKMediaHelper.h"

#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libavutil/imgutils.h>
#import <libswscale/swscale.h>
#import <libavutil/timestamp.h>

#import "IJKSubtitleWriter.h"

@implementation IJKMediaHelper

+ (UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTime:(NSTimeInterval)time {
    AVFormatContext *pFormatCtx;
    AVCodecContext  *pCodecCtx;
    AVCodec         *pCodec;
    AVFrame         *pFrame;
    AVPacket        *packet;
    int             frameFinished = 0;
    int             ret = 0;
    double          timebase = 0;
    uint8_t         *buffer;
    int             videoStream;
    UIImage         *image;
    
    av_register_all();
    avformat_network_init();
    pFormatCtx = avformat_alloc_context();
    
    if (avformat_open_input(&pFormatCtx, [path UTF8String], NULL, NULL) != 0) {
//        NSLog(@"IJKMediaHelper::Couldn't open input stream");
        return nil;
    }
    
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
//        NSLog(@"IJKMediaHelper::Couldn't find stream information");
        return nil;
    }
    
    // Find the first video stream
    videoStream = -1;
    for (int i = 0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStream = i;
            break;
        }
    }
    
    if (videoStream == -1) {
//        NSLog(@"IJKMediaHelper::Couldn't find a video stream");
        return nil;
    }
    
    // Find the decoder for the video streams
    pCodec = avcodec_find_decoder(pFormatCtx->streams[videoStream]->codecpar->codec_id);
    if (pCodec == NULL) {
        return nil;
    }
    
    // Alloc Codec Context
    pCodecCtx = avcodec_alloc_context3(pCodec);
    avcodec_parameters_to_context(pCodecCtx, pFormatCtx->streams[videoStream]->codecpar);
    
    // Open Codec
    if (avcodec_open2(pCodecCtx, pCodec, NULL) < 0) {
        return nil;
    }
    
    // Determine Timebase
    AVStream *st = pFormatCtx->streams[videoStream];
    if (st->time_base.den && st->time_base.num) {
        timebase = av_q2d(st->time_base);
    } else if (pCodecCtx->time_base.den && pCodecCtx->time_base.num) {
        timebase = av_q2d(pCodecCtx->time_base);
    } else {
        timebase = 0.04; // default
    }
    
    // Seek File
    int64_t ts = (int64_t)(time / timebase);
    avformat_seek_file(pFormatCtx, videoStream, INT64_MIN, ts, INT64_MAX, AVSEEK_FLAG_FRAME);
    avcodec_flush_buffers(pCodecCtx);
    
    // Read Frame
    pFrame = av_frame_alloc();
    buffer = av_malloc(av_image_get_buffer_size(AV_PIX_FMT_YUV420P, pCodecCtx->width, pCodecCtx->height, 1));
    av_image_fill_arrays(pFrame->data, pFrame->linesize, buffer, AV_PIX_FMT_YUV420P, pCodecCtx->width, pCodecCtx->height, 1);
    packet = (AVPacket *)av_malloc(sizeof(AVPacket));
    
    while (av_read_frame(pFormatCtx, packet) >= 0) {
        if (packet->stream_index == videoStream) {
            ret = avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, packet);
        }
        av_packet_unref(packet);
        if (ret < 0) {
//            NSLog(@"Decode Error");
            break;
        }
        if (frameFinished) {
            image = [self imageFromeAVFrame:pFrame];
            break;
        }
    }
    
    free(buffer);
    av_free(pFrame);
    avcodec_close(pCodecCtx);
    avformat_close_input(&pFormatCtx);
    
    return image;
}

+ (UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTimePercent:(double)timePercent { // 0..1
    AVFormatContext *pFormatCtx;
    AVCodecContext  *pCodecCtx;
    AVCodec         *pCodec;
    AVFrame         *pFrame;
    AVPacket        *packet;
    int             frameFinished = 0;
    int             ret = 0;
    double          timebase = 0;
    uint8_t         *buffer;
    int             videoStream;
    UIImage         *image;
    
    av_register_all();
    avformat_network_init();
    pFormatCtx = avformat_alloc_context();
    
    if (avformat_open_input(&pFormatCtx, [path UTF8String], NULL, NULL) != 0) {
//        NSLog(@"IJKMediaHelper::Couldn't open input stream");
        return nil;
    }
    
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
//        NSLog(@"IJKMediaHelper::Couldn't find stream information");
        return nil;
    }
    
    if (pFormatCtx->duration == AV_NOPTS_VALUE) {
        return nil;
    }
    
    NSInteger duration = pFormatCtx->duration * 1.0 / AV_TIME_BASE;
    
    // Find the first video stream
    videoStream = -1;
    for (int i = 0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoStream = i;
            break;
        }
    }
    
    if (videoStream == -1) {
//        NSLog(@"IJKMediaHelper::Couldn't find a video stream");
        return nil;
    }
    
    // Find the decoder for the video streams
    pCodec = avcodec_find_decoder(pFormatCtx->streams[videoStream]->codecpar->codec_id);
    if (pCodec == NULL) {
        return nil;
    }
    
    // Alloc Codec Context
    pCodecCtx = avcodec_alloc_context3(pCodec);
    avcodec_parameters_to_context(pCodecCtx, pFormatCtx->streams[videoStream]->codecpar);
    
    // Open Codec
    if (avcodec_open2(pCodecCtx, pCodec, NULL) < 0) {
        return nil;
    }
    
    // Determine Timebase
    AVStream *st = pFormatCtx->streams[videoStream];
    if (st->time_base.den && st->time_base.num) {
        timebase = av_q2d(st->time_base);
    } else if (pCodecCtx->time_base.den && pCodecCtx->time_base.num) {
        timebase = av_q2d(pCodecCtx->time_base);
    } else {
        timebase = 0.04; // default
    }
    
    // Seek File
    double time = timePercent * duration;
    int64_t ts = (int64_t)(time / timebase);
    avformat_seek_file(pFormatCtx, videoStream, INT64_MIN, ts, INT64_MAX, AVSEEK_FLAG_FRAME);
    avcodec_flush_buffers(pCodecCtx);
    
    // Read Frame
    pFrame = av_frame_alloc();
    buffer = av_malloc(av_image_get_buffer_size(AV_PIX_FMT_YUV420P, pCodecCtx->width, pCodecCtx->height, 1));
    av_image_fill_arrays(pFrame->data, pFrame->linesize, buffer, AV_PIX_FMT_YUV420P, pCodecCtx->width, pCodecCtx->height, 1);
    packet = (AVPacket *)av_malloc(sizeof(AVPacket));
    
    while (av_read_frame(pFormatCtx, packet) >= 0) {
        if (packet->stream_index == videoStream) {
            ret = avcodec_decode_video2(pCodecCtx, pFrame, &frameFinished, packet);
        }
        av_packet_unref(packet);
        if (ret < 0) {
//            NSLog(@"Decode Error");
            break;
        }
        if (frameFinished) {
            image = [self imageFromeAVFrame:pFrame];
            break;
        }
    }
    
    free(buffer);
    av_free(pFrame);
    av_free(packet);
    avcodec_close(pCodecCtx);
    avformat_close_input(&pFormatCtx);
    
    return image;
}

+ (NSTimeInterval)durationOfVideoAtPath:(NSString *)path {
    AVFormatContext *pFormatCtx;
    
    av_register_all();
    avformat_network_init();
    pFormatCtx = avformat_alloc_context();
    
    if (avformat_open_input(&pFormatCtx, [path UTF8String], NULL, NULL) != 0) {
//        NSLog(@"IJKMediaHelper::Couldn't open input stream");
        return 0;
    }
    
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
//        NSLog(@"IJKMediaHelper::Couldn't find stream information");
        return 0;
    }
    
    if (pFormatCtx->duration == AV_NOPTS_VALUE) {
        return MAXFLOAT;
    }
    
    NSInteger duration = pFormatCtx->duration * 1.0 / AV_TIME_BASE;
    
    avformat_close_input(&pFormatCtx);
    
    return duration;
}

+ (UIImage *)imageFromeAVFrame:(AVFrame *)frame {
    int width = frame->width;
    int height = frame->height;
    AVPicture picture;
    
    struct SwsContext *imgConvertCtx = sws_getContext(frame->width,
                                                      frame->height,
                                                      AV_PIX_FMT_YUV420P,
                                                      frame->width,
                                                      frame->height,
                                                      AV_PIX_FMT_RGB24,
                                                      SWS_FAST_BILINEAR,
                                                      NULL,
                                                      NULL,
                                                      NULL);
    
    if (!imgConvertCtx) {
        return nil;
    }
    
    
    avpicture_alloc(&picture, AV_PIX_FMT_RGB24, width, height);
    sws_scale(imgConvertCtx,
              frame->data,
              frame->linesize,
              0,
              frame->height,
              picture.data, picture.linesize);
    sws_freeContext(imgConvertCtx);
    
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderMask;
    CFDataRef data = CFDataCreate(kCFAllocatorDefault, picture.data[0], picture.linesize[0] * height);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImage = CGImageCreate(width,
                                       height,
                                       8,
                                       24,
                                       picture.linesize[0],
                                       colorSpace,
                                       bitmapInfo,
                                       provider,
                                       NULL,
                                       NO,
                                       kCGRenderingIntentDefault);
    
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    CFRelease(data);
    
    avpicture_free(&picture);
    
    return image;
}

+ (BOOL)hasSubtitles:(NSString *)path {
    AVFormatContext *pFormatCtx;
    
    av_register_all();
    avformat_network_init();
    pFormatCtx = avformat_alloc_context();
    
    if (avformat_open_input(&pFormatCtx, [path UTF8String], NULL, NULL) != 0) {
//        NSLog(@"IJKMediaHelper::Couldn't open input stream");
        avformat_close_input(&pFormatCtx);
        return false;
    }
    
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
        avformat_close_input(&pFormatCtx);
//        NSLog(@"IJKMediaHelper::Couldn't find stream information");
        return false;
    }
    bool hasSubs = false;
    for (int i = 0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            hasSubs = true;
            break;
        }
    }
    avformat_close_input(&pFormatCtx);
    return hasSubs;
}

//+ (void)printSubtitles:(NSString *)path {
//    AVFormatContext *pFormatCtx;
//    
//    av_register_all();
//    avformat_network_init();
//    pFormatCtx = avformat_alloc_context();
//    
//    if (avformat_open_input(&pFormatCtx, [path UTF8String], NULL, NULL) != 0) {
//        //        NSLog(@"IJKMediaHelper::Couldn't open input stream");
//        return;
//    }
//    
//    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
//        //        NSLog(@"IJKMediaHelper::Couldn't find stream information");
//        return;
//    }
//    
//    for (int i = 0; i < pFormatCtx->nb_streams; i++) {
//        if (pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
//            AVPacket *pkt;
//            while(av_read_frame(pFormatCtx, &pkt) == 0) {
//                int got_frame = 0;
//                pFormatCtx->streams[i]->codecpar->
//                int ret = avcodec_decode_subtitle2(aCodecCtx, subtitle, &got_frame, &pkt);
//                if (ret >= 0 && got_frame) {
//                    AVSubtitleRect **rects = subtitle->rects;
//                    for (i = 0; i < subtitle->num_rects; i++) {
//                        AVSubtitleRect rect = *rects[i];
//                        if (rect.type == SUBTITLE_ASS) {
//                            printf("ASS %s", rect.ass);
//                        } else if (rect.x == SUBTITLE_TEXT) {;
//                            printf("TEXT %s", rect.text);
//                        }
//                    }
//                    // it just writes some big file (similar to videofile size)
//                    //out.write((char*)pkt.data, pkt.size);
//                }
//            }
//        }
//    }
//}

+ (void)readSubtitles:(NSString *)videoPath saveFolder:(NSString *)saveFolder {
    AVFormatContext *pFormatCtx;
    
    av_register_all();
    avcodec_register_all();
    avformat_network_init();
    pFormatCtx = avformat_alloc_context();
    
    if (avformat_open_input(&pFormatCtx, [videoPath UTF8String], NULL, NULL) != 0) {
        avformat_close_input(&pFormatCtx);
        return;
    }
    
    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
        avformat_close_input(&pFormatCtx);
        return;
    }
    
    NSMutableDictionary *dic = [NSMutableDictionary new];
    for (int i = 0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            IJKMetadata *metadata = [IJKMetadata metadataWithAVDictionary:pFormatCtx->streams[i]->metadata];
            NSString *name = [IJKSubtitleWriter subtitleName:metadata.title
                                                  track:i
                                                 subIdx:(int)dic.count
                                                   lang:metadata.language];
            IJKSubtitleWriter *writer = [IJKSubtitleWriter writerFile:[saveFolder stringByAppendingPathComponent:name] trackIdx:i];
            dic[@(i)] = writer;
        }
    }
    [self parseSubtitles:pFormatCtx dic:dic savePath:saveFolder];
    avformat_close_input(&pFormatCtx);
}

+ (void)parseSubtitles:(AVFormatContext *)context dic:(NSMutableDictionary<NSNumber *, IJKSubtitleWriter *> *)dic savePath:(NSString *)savePath {
    AVCodec *codec = nil;
    AVCodecContext *ctx = nil;
    for (NSNumber *idx in dic) {
        AVStream *avstream = context->streams[idx.intValue];
        
        ctx = avstream->codec;
        codec = avcodec_find_decoder( ctx->codec_id );
        int result = avcodec_open2( ctx, codec, NULL );
        if (result >= 0) {
            break;
        }
    }
    if (ctx == nil) {
        return;
    }
    for (IJKSubtitleWriter *w in dic.allValues) {
        [w open];
    }
    
    AVPacket *packet = (AVPacket *)av_malloc(sizeof(AVPacket));
    
    while( av_read_frame( context, packet ) >= 0 )
    {
        IJKSubtitleWriter *writer = dic[@(packet->stream_index)];
        if (writer != nil) {
            [writer addSub:packet->data startTime:packet->pts duration:packet->duration];
        }
        
        av_packet_unref(packet);
    }
    avcodec_close(ctx);
    av_free(packet);
    
    for (IJKSubtitleWriter *w in dic.allValues) {
        [w close];
    }
}



//+ (NSArray<IJKSubtitles *> *)readSubtitles:(NSString *)videoPath {
//    AVFormatContext *pFormatCtx;
//
//    av_register_all();
//    avcodec_register_all();
//    avformat_network_init();
//    pFormatCtx = avformat_alloc_context();
//
//    if (avformat_open_input(&pFormatCtx, [videoPath UTF8String], NULL, NULL) != 0) {
//        return nil;
//    }
//
//    if (avformat_find_stream_info(pFormatCtx, NULL) < 0) {
//        return nil;
//    }
//
//    NSMutableDictionary *dic = [NSMutableDictionary new];
//    for (int i = 0; i < pFormatCtx->nb_streams; i++) {
//        if (pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
//            IJKMetadata *metadata = [IJKMetadata metadataWithAVDictionary:pFormatCtx->streams[i]->metadata];
//            IJKSubtitles *subs = [IJKSubtitles new];
//            subs.trackIdx = i;
//            subs.title = metadata.title;
//            subs.language = metadata.language;
//            dic[@(i)] = subs;
//        }
//    }
//    [self parseSubtitles:pFormatCtx dic:dic];
//    return dic.allValues;
//}
//
//+ (void)parseSubtitles:(AVFormatContext *)context dic:(NSMutableDictionary<NSNumber *, IJKSubtitles *> *)dic {
//    AVCodec *codec = nil;
//    AVCodecContext *ctx = nil;
//    for (NSNumber *idx in dic) {
//        AVStream *avstream = context->streams[idx.intValue];
//
//        ctx = avstream->codec;
//        codec = avcodec_find_decoder( ctx->codec_id );
//        int result = avcodec_open2( ctx, codec, NULL );
//        if (result >= 0) {
//            break;
//        }
//    }
//    if (ctx == nil) {
//        return;
//    }
//
//    AVPacket pkt;
//    av_init_packet( &pkt );
//    pkt.data = NULL;
//    pkt.size = 0;
//
//    while( av_read_frame( context, &pkt ) >= 0 )
//    {
//        IJKSubtitles *subs = dic[@(pkt.stream_index)];
//        if (subs == nil) continue;
//
//        int idx = [subs.contents lastObject].number;
//        [subs.contents addObject:[IJKSubContent content:pkt.data startTime:pkt.pts endTime:pkt.duration numb:idx+1]];
//    }
//    avcodec_close(ctx);
//}

@end



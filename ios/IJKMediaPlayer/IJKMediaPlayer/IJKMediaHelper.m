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
#import "IJTrackMetadata.h"

@interface IJTrackMetadata (Hidden)
+ (NSDictionary *)AVDictionaryToNSDictionary:(AVDictionary *)avDictionary;
+ (instancetype)metadataWithAVDictionary:(AVDictionary *)avDictionary;
@end

@implementation IJKMediaHelper

+ (UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTime:(NSTimeInterval)time aspectSize:(CGSize)size {
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
    buffer = av_malloc(av_image_get_buffer_size(pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height, 1));
    av_image_fill_arrays(pFrame->data, pFrame->linesize, buffer, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height, 1);
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
            image = [self imageFromeAVFrame:pFrame codecContext:pCodecCtx aspectSize:size];
            break;
        }
    }
    
    free(buffer);
    av_free(pFrame);
    avcodec_close(pCodecCtx);
    avformat_close_input(&pFormatCtx);
    
    return image;
}

+ (UIImage *)thumbnailOfVideoAtPath:(NSString*)path atTimePercent:(double)timePercent  aspectSize:(CGSize)size { // 0..1
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
//    av_seek_frame(pFormatCtx, videoStream, ts, AVSEEK_FLAG_BACKWARD);
    avcodec_flush_buffers(pCodecCtx);
    
    // Read Frame
    pFrame = av_frame_alloc();
    buffer = av_malloc(av_image_get_buffer_size(pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height, 1));
    av_image_fill_arrays(pFrame->data, pFrame->linesize, buffer, pCodecCtx->pix_fmt, pCodecCtx->width, pCodecCtx->height, 1);
    packet = (AVPacket *)av_malloc(sizeof(AVPacket));
//    packet = av_packet_alloc();
    
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
            image = [self imageFromeAVFrame:pFrame codecContext:pCodecCtx aspectSize:size];
            break;
        }
    }
    
    av_free(buffer);
    av_frame_free(&pFrame);
//    av_packet_free(&packet);
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

+ (UIImage *)imageFromeAVFrame:(AVFrame *)frame codecContext:(AVCodecContext *)context aspectSize:(CGSize)size {
    int width = frame->width;
    int height = frame->height;

    if (size.width > 0 && width > 0) {
        float scale = fmaxf(size.width / width, size.height / height);
        width = roundf(width * scale);
        height = roundf(height * scale);
    }
    
    struct SwsContext *imgConvertCtx = sws_getContext(frame->width,
                                                      frame->height,
                                                      context->pix_fmt,
                                                      width,
                                                      height,
                                                      AV_PIX_FMT_RGB24,
                                                      SWS_AREA,
                                                      NULL,
                                                      NULL,
                                                      NULL);
    
    if (!imgConvertCtx) {
        return nil;
    }
    
//    AVFrame *picture = av_frame_alloc();
    AVPicture picture;
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
    
//    av_frame_free(&picture);
    avpicture_free(&picture);
    
    return image;
}

+ (int)getSubtitlesCount:(NSString *)path {
    AVFormatContext *pFormatCtx;
    
    av_register_all();
//    avformat_network_init();
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
    int subsCount = 0;
    for (int i = 0; i < pFormatCtx->nb_streams; i++) {
        if (pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            subsCount += 1;
        }
    }
    avformat_close_input(&pFormatCtx);
    return subsCount;
}

+ (VideoInfoObjc)getInfo:(NSString *)path {
    av_register_all();
    static AVFormatContext *pFormatCtx;
    if (!pFormatCtx) {
        pFormatCtx = avformat_alloc_context();
    }
    VideoInfoObjc info = {0, false};
    BOOL isOk = true;
    
    isOk = avformat_open_input(&pFormatCtx, [path UTF8String], NULL, NULL) == 0;
    if (isOk) {
        isOk = avformat_find_stream_info(pFormatCtx, NULL) >= 0;
    }
    if (isOk) {
        for (int i = 0; i < pFormatCtx->nb_streams; i++) {
            if (pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
                info.subtitles = true;
                break;
            }
        }
        if (pFormatCtx->duration != AV_NOPTS_VALUE) {
            info.duration = pFormatCtx->duration * 1.0 / AV_TIME_BASE;
        }
    }
    
    avformat_close_input(&pFormatCtx);
    
    return info;
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

static int kTestIdx = 3;
static NSMutableData *testData = nil;

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
//        if (pFormatCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
//            AVStream *stream = pFormatCtx->streams[i];
//            IJKMetadata *metadata = [IJKMetadata metadataWithAVDictionary:pFormatCtx->streams[i]->metadata];
//            NSLog(@"Meta %d: %@", i, metadata.metadata);
//        }
    }
    
    testData = [NSMutableData new];
    [self parseSubtitles:pFormatCtx dic:dic savePath:saveFolder];
//    testData = [NSMutableData new];
//    NSString *newPath = [videoPath stringByDeletingLastPathComponent];
//    newPath = [newPath stringByAppendingPathComponent:@"audio_2.aac"];
//    [testData writeToFile:newPath atomically:YES];
    avformat_close_input(&pFormatCtx);
}

const char* deass(const char* ass){
  // SSA/ASS formats:
  // Dialogue: Marked=0,0:02:40.65,0:02:41.79,Wolf main,Cher,0000,0000,0000,,Et les enregistrements de ses ondes delta ?
  if(strncmp(ass, "Dialogue:", strlen("Dialogue:"))){
    return NULL;
  }
  const char* delim = strchr(ass, ',');
  int commas = 0; // we want 8
  while(delim && commas < 8){
    delim = strchr(delim + 1, ',');
    ++commas;
  }
  if(!delim){
    return NULL;
  }
  return delim + 1;
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
    AVSubtitle sub;
    double t1 = CACurrentMediaTime();
    while( av_read_frame( context, packet ) >= 0 ) {
        IJKSubtitleWriter *writer = dic[@(packet->stream_index)];
        
        if (writer != nil) {
            int gotFrame = 0;
            int ret = avcodec_decode_subtitle2(ctx, &sub, &gotFrame, packet);
            
            if (ret >= 0 && gotFrame && sub.num_rects > 0) {
                AVSubtitleRect **rects = sub.rects;
                int32_t start = (int32_t)(sub.pts/1000) + (int32_t)sub.start_display_time;
                int32_t duration = sub.end_display_time - sub.start_display_time;
                [writer addNewSubWithStartTime:start duration:duration];
//                [writer addNewSubWithStartTime:packet->pts duration:packet->dts];
                
                for (int i = 0; i < sub.num_rects; i++) {
                    AVSubtitleRect *rect = rects[i];
                    if (rect->type == SUBTITLE_ASS) {
                        // no memory allocated, we just do offset from start
                        const char *text = deass(rect->ass);
                        [writer addNewSubText:text];
//                        printf("ASS %s", text);
                    } else if (rect->type == SUBTITLE_TEXT) {;
                        [writer addNewSubText:rect->text];
//                        printf("TEXT %s", rect->text);
                    }
                }
                [writer finishSub];
                // it just writes some big file (similar to videofile size)
            }
        }
//        if (packet->stream_index == kTestIdx) {
//            [testData appendBytes:packet->data length:packet->size];
//        }
        
        av_packet_unref(packet);
    }
//    avsubtitle_free(&sub);
    avcodec_close(ctx);
    av_free(packet);
    
    for (IJKSubtitleWriter *w in dic.allValues) {
        [w close];
    }
    double t2 = CACurrentMediaTime();
    NSLog(@"Subtitles read done: %lf", t2-t1);
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

+ (int)downloadVideoStream_new:(NSURL*)url toLocation:(NSURL*)location {
    
    char *inputUrl = [[url absoluteString] cStringUsingEncoding:kCFStringEncodingUTF8];
    char *outputFilename = [[location absoluteString] cStringUsingEncoding:kCFStringEncodingUTF8];
    
    avformat_network_init();
    av_register_all();
    
    AVFormatContext* input_format_context = NULL;
    AVFormatContext* output_format_context = NULL;
    int ret = avformat_open_input(&input_format_context, inputUrl, NULL, NULL);
    printf("%s", av_err2str(ret));
//    AVERROR_STREAM_NOT_FOUND
    ret = avformat_find_stream_info(input_format_context, NULL);
    avformat_alloc_output_context2(&output_format_context, NULL, NULL, outputFilename);
    for (int i = 0; i < input_format_context->nb_streams; i++) {
        AVStream* in_stream = input_format_context->streams[i];
        AVStream* out_stream = avformat_new_stream(output_format_context, NULL);
        avcodec_parameters_copy(out_stream->codecpar, in_stream->codecpar);
    }
    ret = avio_open(&output_format_context->pb, outputFilename, AVIO_FLAG_WRITE);
    ret = avformat_write_header(output_format_context, NULL);
    AVPacket pkt;
    while (av_read_frame(input_format_context, &pkt) >= 0) {
        AVStream* in_stream = input_format_context->streams[pkt.stream_index];
        AVStream* out_stream = output_format_context->streams[pkt.stream_index];
        pkt.pts = av_rescale_q_rnd(pkt.pts, in_stream->time_base, out_stream->time_base, AV_ROUND_NEAR_INF|AV_ROUND_PASS_MINMAX);
        pkt.dts = pkt.pts;
        pkt.duration = av_rescale_q(pkt.duration, in_stream->time_base, out_stream->time_base);
        pkt.pos = -1;
        av_interleaved_write_frame(output_format_context, &pkt);
        av_packet_unref(&pkt);
    }
    av_write_trailer(output_format_context);
    avformat_close_input(&input_format_context);
    avio_closep(&output_format_context->pb);
    avformat_free_context(output_format_context);
    avformat_network_deinit();
    return 0;
}

int setCodecThreadCount(AVStream **streamRef, int threadCount) {
    AVStream *stream = *streamRef;
    AVCodecContext *codecContext = avcodec_alloc_context3(NULL);
    if (!codecContext) {
        fprintf(stderr, "Failed to allocate codec context\n");
        return -4;
    }
    
    int ret = avcodec_parameters_to_context(codecContext, stream->codecpar);
    if (ret < 0) {
        fprintf(stderr, "Failed to copy codec parameters to codec context\n");
        return -5;
    }
    
    // Set the number of decode threads
    codecContext->thread_count = threadCount;  // Set this to the desired number of threads
    
    AVCodec *codec = avcodec_find_decoder(codecContext->codec_id);
    if (!codec) {
        fprintf(stderr, "Codec not found\n");
        return -6;
    }
    
    if ((ret = avcodec_open2(codecContext, codec, NULL)) < 0) {
        fprintf(stderr, "Failed to open codec\n");
        return -7;
    }
    
    (*streamRef)->codec = codecContext;
    return 0;
}

static void log_packet(const AVFormatContext *fmt_ctx, const AVPacket *pkt, const char *tag)
{
    AVRational *time_base = &fmt_ctx->streams[pkt->stream_index]->time_base;

    printf("%s: pts:%s pts_time:%s dts:%s dts_time:%s duration:%s duration_time:%s stream_index:%d\n",
           tag,
           av_ts2str(pkt->pts), av_ts2timestr(pkt->pts, time_base),
           av_ts2str(pkt->dts), av_ts2timestr(pkt->dts, time_base),
           av_ts2str(pkt->duration), av_ts2timestr(pkt->duration, time_base),
           pkt->stream_index);
}

// данный код позволяет скачивать видео из интернета
int ffmpeg_remux(char *arg1, char *arg2) {
    const AVOutputFormat *ofmt = NULL;
    AVFormatContext *ifmt_ctx = NULL, *ofmt_ctx = NULL;
    AVPacket *pkt = NULL;
    const char *in_filename, *out_filename;
    int ret, i;
    int stream_index = 0;
    int *stream_mapping = NULL;
    int stream_mapping_size = 0;

    in_filename  = arg1;
    out_filename = arg2;

    pkt = av_packet_alloc();
    if (!pkt) {
        fprintf(stderr, "Could not allocate AVPacket\n");
        return 1;
    }

    if ((ret = avformat_open_input(&ifmt_ctx, in_filename, 0, 0)) < 0) {
        fprintf(stderr, "Could not open input file '%s'", in_filename);
        goto end;
    }

    if ((ret = avformat_find_stream_info(ifmt_ctx, 0)) < 0) {
        fprintf(stderr, "Failed to retrieve input stream information");
        goto end;
    }

    av_dump_format(ifmt_ctx, 0, in_filename, 0);

    avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, out_filename);
    if (!ofmt_ctx) {
        fprintf(stderr, "Could not create output context\n");
        ret = AVERROR_UNKNOWN;
        goto end;
    }

    stream_mapping_size = ifmt_ctx->nb_streams;
    stream_mapping = av_calloc(stream_mapping_size, sizeof(*stream_mapping));
    if (!stream_mapping) {
        ret = AVERROR(ENOMEM);
        goto end;
    }

    ofmt = ofmt_ctx->oformat;

    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        AVStream *out_stream;
        AVStream *in_stream = ifmt_ctx->streams[i];
        AVCodecParameters *in_codecpar = in_stream->codecpar;

        if (in_codecpar->codec_type != AVMEDIA_TYPE_AUDIO &&
            in_codecpar->codec_type != AVMEDIA_TYPE_VIDEO &&
            in_codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE) {
            stream_mapping[i] = -1;
            continue;
        }
        if (in_stream->metadata) {
            NSDictionary * dic = [IJTrackMetadata AVDictionaryToNSDictionary:in_stream->metadata];
//            NSDictionary * dic = IJKFoundationBrigeOfAVDictionary(in_stream->metadata);
            NSLog(@"Metadata: %@", dic);
        }

        stream_mapping[i] = stream_index++;

        out_stream = avformat_new_stream(ofmt_ctx, NULL);
        if (!out_stream) {
            fprintf(stderr, "Failed allocating output stream\n");
            ret = AVERROR_UNKNOWN;
            goto end;
        }

        ret = avcodec_parameters_copy(out_stream->codecpar, in_codecpar);
        if (ret < 0) {
            fprintf(stderr, "Failed to copy codec parameters\n");
            goto end;
        }
        out_stream->codecpar->codec_tag = 0;
    }
    av_dump_format(ofmt_ctx, 0, out_filename, 1);

    if (!(ofmt->flags & AVFMT_NOFILE)) {
        ret = avio_open(&ofmt_ctx->pb, out_filename, AVIO_FLAG_WRITE);
        if (ret < 0) {
            fprintf(stderr, "Could not open output file '%s'", out_filename);
            goto end;
        }
    }

    ret = avformat_write_header(ofmt_ctx, NULL);
    if (ret < 0) {
        fprintf(stderr, "Error occurred when opening output file\n");
        goto end;
    }

    while (1) {
        AVStream *in_stream, *out_stream;

        ret = av_read_frame(ifmt_ctx, pkt);
        if (ret < 0)
            break;

        in_stream  = ifmt_ctx->streams[pkt->stream_index];
        if (pkt->stream_index >= stream_mapping_size ||
            stream_mapping[pkt->stream_index] < 0) {
            av_packet_unref(pkt);
            continue;
        }

        pkt->stream_index = stream_mapping[pkt->stream_index];
        out_stream = ofmt_ctx->streams[pkt->stream_index];
        log_packet(ifmt_ctx, pkt, "in");

        /* copy packet */
        av_packet_rescale_ts(pkt, in_stream->time_base, out_stream->time_base);
        pkt->pos = -1;
//        log_packet(ofmt_ctx, pkt, "out");

        ret = av_interleaved_write_frame(ofmt_ctx, pkt);
        /* pkt is now blank (av_interleaved_write_frame() takes ownership of
         * its contents and resets pkt), so that no unreferencing is necessary.
         * This would be different if one used av_write_frame(). */
        if (ret < 0) {
            fprintf(stderr, "Error muxing packet\n");
            break;
        }
    }

    av_write_trailer(ofmt_ctx);
end:
    av_packet_free(&pkt);

    avformat_close_input(&ifmt_ctx);

    /* close output */
    if (ofmt_ctx && !(ofmt->flags & AVFMT_NOFILE))
        avio_closep(&ofmt_ctx->pb);
    avformat_free_context(ofmt_ctx);

    av_freep(&stream_mapping);

    if (ret < 0 && ret != AVERROR_EOF) {
        fprintf(stderr, "Error occurred: %s\n", av_err2str(ret));
        return -1;
    }

    return 0;
}
+ (int)downloadVideoStream:(NSURL*)url toLocation:(NSURL*)location chooseTracks:(NSArray<TrackInfoObjc *> *(^)(NSArray<TrackInfoObjc *> *))filterClosure {
    avformat_network_init();
    av_register_all();
    
    AVFormatContext *inputFormatContext = NULL, *outputFormatContext = NULL;
    AVPacket packet;
    int ret, i;
    double tt1 = CACurrentMediaTime();
    
    char *inputUrl = [[url absoluteString] cStringUsingEncoding:kCFStringEncodingUTF8];
    char *outputFilename = [[location path] cStringUsingEncoding:kCFStringEncodingUTF8];
    ffmpeg_remux(inputUrl, outputFilename);
    
    
//    // Register all formats and codecs

//    
//    
//    // Open input
//    AVDictionary *opts = NULL;
//    av_dict_set(&opts, "stimeout", "20000000", 0);   // timeout for reading in microseconds
//    av_dict_set(&opts, "threads", "auto", 0);  // Let FFmpeg choose the optimal number of threads
//    av_dict_set(&opts, "probesize", "5000000", 0); // Increase if needed
//    av_dict_set(&opts, "analyzeduration", "5000000", 0); // in microseconds
//    av_dict_set(&opts, "buffer_size", "4096000", 0); // Increase buffer size
//    av_dict_set(&opts, "reorder_queue_size", "1000", 0); // Buffer for handling reordered packets
//
//    if ((ret = avformat_open_input(&inputFormatContext, inputUrl, NULL, &opts)) < 0) {
//        printf("%s\n", av_err2str(ret));
//        fprintf(stderr, "Could not open input file '%s'\n", inputUrl);
//        return -2;
//    }
//
//    
//    if ((ret = avformat_find_stream_info(inputFormatContext, NULL)) < 0) {
//        printf("%s\n", av_err2str(ret));
//        fprintf(stderr, "Failed to retrieve input stream information\n");
//        return -3;
//    }
////    inputFormatContext->data_codec
//    
//    // Open output
//    ret = avformat_alloc_output_context2(&outputFormatContext, NULL, NULL, outputFilename);
//    if (!outputFormatContext) {
//        printf("%s\n", av_err2str(ret));
//        fprintf(stderr, "Could not create output context\n");
//        return -4;
//    }
//    
//    // Transfer stream from input to output
//    for (i = 0; i < inputFormatContext->nb_streams; i++) {
////        setCodecThreadCount(&(inputFormatContext->streams[i]), 10);
//        AVStream *inStream = inputFormatContext->streams[i];
//        AVStream *outStream = avformat_new_stream(outputFormatContext, NULL);
//        if (!outStream) {
//            fprintf(stderr, "Failed allocating output stream: %s\n", av_err2str(ret));
//            return -5;
//        }
//        
//        // Copy context from input to output
//        ret = avcodec_parameters_copy(outStream->codecpar, inStream->codecpar);
//        outStream->codecpar->codec_tag = 0;
//        if (ret < 0) {
//            fprintf(stderr, "Copying codec context failed\n");
//            return -6;
//        }
//    }
//    
//    // Open output file
//    if (!(outputFormatContext->oformat->flags & AVFMT_NOFILE)) {
//        ret = avio_open(&outputFormatContext->pb, outputFilename, AVIO_FLAG_WRITE);
//        if (ret < 0) {
//            fprintf(stderr, "Could not open output file '%s'\n", outputFilename);
//            printf("%s\n", av_err2str(ret));
//            return -7;
//        }
//    }
//    
//    // Write output file header
//    if (avformat_write_header(outputFormatContext, NULL) < 0) {
//        fprintf(stderr, "Error occurred when opening output file\n");
//        return -8;
//    }
//    
//    // Remix/transfer packet from input to output
//    double times[4] = {0, 0, 0, 0};
//    while (1) {
//        double t1 = CACurrentMediaTime();
//        ret = av_read_frame(inputFormatContext, &packet);
//        double t2 = CACurrentMediaTime();
//        if (ret < 0)
//            break;
//
//        // Get the input stream and output stream
//        AVStream *in_stream = inputFormatContext->streams[packet.stream_index];
//        AVStream *out_stream = outputFormatContext->streams[packet.stream_index];
//
//        // Rescale the packet timestamp to home with the output stream
//        av_packet_rescale_ts(&packet, in_stream->time_base, out_stream->time_base);
//        packet.stream_index = out_stream->index;
//
//        double t3 = CACurrentMediaTime();
//        // Write the packet
//        ret = av_interleaved_write_frame(outputFormatContext, &packet);
//        if (ret < 0) {
//            fprintf(stderr, "Error muxing packet: %s\n", av_err2str(ret));
//            break;
//        }
//        double t4 = CACurrentMediaTime();
//
//        av_packet_unref(&packet);
//        double t5 = CACurrentMediaTime();
//        times[0] += t2-t1;
//        times[1] += t3-t2;
//        times[2] += t4-t3;
//        times[3] += t5-t4;
//    }
//    NSLog(@"Times: %.3lf %.3lf %.3lf %.3lf", times[0], times[1], times[2], times[3]);
//    NSLog(@"Total: %.3lf", times[0]+ times[1]+ times[2]+ times[3]);
//    
//    // Write trailer to output file
//    av_write_trailer(outputFormatContext);
//    
//    // Clean up
//    avformat_close_input(&inputFormatContext);
//    if (outputFormatContext && !(outputFormatContext->oformat->flags & AVFMT_NOFILE))
//        avio_closep(&outputFormatContext->pb);
//    avformat_free_context(outputFormatContext);
//    avformat_network_deinit();
    double tt2 = CACurrentMediaTime();
    NSLog(@"Final: %.3lf", tt2-tt1);
    
    return 0;
}

@end



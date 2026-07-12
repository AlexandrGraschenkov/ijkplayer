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
#import <libswresample/swresample.h>
#import <libavutil/timestamp.h>

#import "IJKSubtitleWriter.h"

static NSString *const IJKAudioReaderErrorDomain = @"tv.linguaplayer.ijk.audio-reader";

@implementation IJKAudioReader {
    NSString *_path;
    NSInteger _requestedAudioStreamIndex;
    NSTimeInterval _startTime;
    NSTimeInterval _endTime;
    dispatch_queue_t _queue;
    int32_t _cancelled;
    int32_t _started;
}

- (instancetype)initWithPath:(NSString *)path audioStreamIndex:(NSInteger)audioStreamIndex startTime:(NSTimeInterval)startTime endTime:(NSTimeInterval)endTime {
    self = [super init];
    if (self) {
        _path = [path copy];
        _requestedAudioStreamIndex = audioStreamIndex;
        _startTime = MAX(0, startTime);
        _endTime = endTime;
        _queue = dispatch_queue_create("tv.linguaplayer.ijk.audio-reader", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)startWithAudioCallback:(IJKAudioReaderDataCallback)audioCallback progress:(IJKAudioReaderProgressCallback)progress completion:(IJKAudioReaderCompletion)completion {
    if (__atomic_exchange_n(&_started, 1, __ATOMIC_SEQ_CST) != 0) {
        completion([self errorWithCode:1 description:@"The audio reader has already been started."]);
        return;
    }

    dispatch_async(_queue, ^{
        @autoreleasepool {
            NSError *error = [self readWithAudioCallback:audioCallback progress:progress];
            completion(error);
        }
    });
}

- (void)cancel {
    __atomic_store_n(&_cancelled, 1, __ATOMIC_SEQ_CST);
}

- (BOOL)isCancelled {
    return __atomic_load_n(&_cancelled, __ATOMIC_SEQ_CST) != 0;
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:IJKAudioReaderErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: description}];
}

static int ijk_audio_reader_interrupt(void *opaque) {
    IJKAudioReader *reader = (__bridge IJKAudioReader *)opaque;
    return reader.isCancelled ? 1 : 0;
}

typedef struct IJKAudioReadState {
    AVCodecContext *codecContext;
    AVFrame *frame;
    struct SwrContext *swrContext;
    AVStream *stream;
    uint8_t **audioBuffer;
    unsigned int *audioBufferSize;
    NSTimeInterval streamStartOffset;
    NSTimeInterval startTime;
    NSTimeInterval endTime;
    NSTimeInterval mediaDuration;
    NSTimeInterval runningPosition;
    BOOL reachedEnd;
    BOOL decoderDone;
} IJKAudioReadState;

static void ijk_audio_reader_emit(IJKAudioReadState *s,
                                  const uint8_t *samples,
                                  int sampleCount,
                                  NSTimeInterval position,
                                  IJKAudioReaderDataCallback audioCallback,
                                  IJKAudioReaderProgressCallback progress) {
    position = MAX(0, position);
    NSTimeInterval convertedDuration = (NSTimeInterval)sampleCount / 16000.0;
    NSTimeInterval frameEnd = position + convertedDuration;
    s->runningPosition = frameEnd;
    if (s->endTime > s->startTime && position >= s->endTime) {
        s->reachedEnd = YES;
        return;
    }
    if (frameEnd <= s->startTime) {
        return;
    }
    NSData *data = [NSData dataWithBytes:samples length:(NSUInteger)sampleCount * sizeof(int16_t)];
    audioCallback(data, position);
    if (progress) {
        progress(frameEnd, s->mediaDuration);
    }
}

// Pulls every frame currently available from the decoder, resamples and emits it.
// Returns 0 on success (including EAGAIN/EOF, which set state flags), or a negative error.
static int ijk_audio_reader_drain(IJKAudioReader *reader,
                                  IJKAudioReadState *s,
                                  IJKAudioReaderDataCallback audioCallback,
                                  IJKAudioReaderProgressCallback progress) {
    while (![reader isCancelled] && !s->reachedEnd) {
        int receiveResult = avcodec_receive_frame(s->codecContext, s->frame);
        if (receiveResult == AVERROR(EAGAIN)) {
            return 0;
        }
        if (receiveResult == AVERROR_EOF) {
            s->decoderDone = YES;
            return 0;
        }
        if (receiveResult < 0) {
            return receiveResult;
        }

        int64_t timestamp = s->frame->best_effort_timestamp;
        NSTimeInterval position = timestamp == AV_NOPTS_VALUE
            ? s->runningPosition
            : timestamp * av_q2d(s->stream->time_base) - s->streamStartOffset;
        // The resampler still buffers samples from previous frames, so the data
        // produced by this conversion starts that much earlier than the frame PTS.
        if (timestamp != AV_NOPTS_VALUE) {
            position -= (NSTimeInterval)swr_get_delay(s->swrContext, 16000) / 16000.0;
        }

        int outputSamples = (int)av_rescale_rnd(swr_get_delay(s->swrContext, s->frame->sample_rate) + s->frame->nb_samples,
                                                16000,
                                                s->frame->sample_rate,
                                                AV_ROUND_UP);
        int outputSize = av_samples_get_buffer_size(NULL, 1, outputSamples, AV_SAMPLE_FMT_S16, 1);
        if (outputSize <= 0) {
            av_frame_unref(s->frame);
            continue;
        }
        av_fast_malloc(s->audioBuffer, s->audioBufferSize, outputSize);
        if (!*s->audioBuffer) {
            av_frame_unref(s->frame);
            return AVERROR(ENOMEM);
        }

        uint8_t *output[] = { *s->audioBuffer };
        int convertedSamples = swr_convert(s->swrContext,
                                           output,
                                           outputSamples,
                                           (const uint8_t **)s->frame->extended_data,
                                           s->frame->nb_samples);
        av_frame_unref(s->frame);
        if (convertedSamples <= 0) {
            continue;
        }
        ijk_audio_reader_emit(s, *s->audioBuffer, convertedSamples, position, audioCallback, progress);
    }
    return 0;
}

- (NSError *)readWithAudioCallback:(IJKAudioReaderDataCallback)audioCallback progress:(IJKAudioReaderProgressCallback)progress {
    AVFormatContext *formatContext = NULL;
    AVCodecContext *codecContext = NULL;
    AVFrame *frame = NULL;
    struct SwrContext *swrContext = NULL;
    uint8_t *audioBuffer = NULL;
    unsigned int audioBufferSize = 0;
    AVPacket packet;
    int audioStreamIndex = -1;
    NSError *resultError = nil;

    av_init_packet(&packet);
    packet.data = NULL;
    packet.size = 0;

    av_register_all();
    avformat_network_init();
    formatContext = avformat_alloc_context();
    if (!formatContext) {
        return [self errorWithCode:2 description:@"Unable to allocate the media context."];
    }
    formatContext->interrupt_callback.callback = ijk_audio_reader_interrupt;
    formatContext->interrupt_callback.opaque = (__bridge void *)self;

    if (avformat_open_input(&formatContext, _path.UTF8String, NULL, NULL) < 0) {
        resultError = [self errorWithCode:3 description:@"Unable to open the media file."];
        goto cleanup;
    }
    if (avformat_find_stream_info(formatContext, NULL) < 0) {
        resultError = [self errorWithCode:4 description:@"Unable to read media stream information."];
        goto cleanup;
    }

    if (_requestedAudioStreamIndex >= 0 && _requestedAudioStreamIndex < formatContext->nb_streams &&
        formatContext->streams[_requestedAudioStreamIndex]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
        audioStreamIndex = (int)_requestedAudioStreamIndex;
    } else {
        audioStreamIndex = av_find_best_stream(formatContext, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
    }
    if (audioStreamIndex < 0) {
        resultError = [self errorWithCode:5 description:@"The media file does not contain a readable audio stream."];
        goto cleanup;
    }

    AVStream *audioStream = formatContext->streams[audioStreamIndex];
    AVCodec *codec = avcodec_find_decoder(audioStream->codecpar->codec_id);
    if (!codec) {
        resultError = [self errorWithCode:6 description:@"The selected audio codec is not supported."];
        goto cleanup;
    }
    codecContext = avcodec_alloc_context3(codec);
    if (!codecContext || avcodec_parameters_to_context(codecContext, audioStream->codecpar) < 0 || avcodec_open2(codecContext, codec, NULL) < 0) {
        resultError = [self errorWithCode:7 description:@"Unable to initialize the audio decoder."];
        goto cleanup;
    }

    int64_t inputLayout = codecContext->channel_layout;
    if (!inputLayout) {
        inputLayout = av_get_default_channel_layout(codecContext->channels);
    }
    swrContext = swr_alloc_set_opts(NULL,
                                   AV_CH_LAYOUT_MONO,
                                   AV_SAMPLE_FMT_S16,
                                   16000,
                                   inputLayout,
                                   codecContext->sample_fmt,
                                   codecContext->sample_rate,
                                   0,
                                   NULL);
    if (!swrContext || swr_init(swrContext) < 0) {
        resultError = [self errorWithCode:8 description:@"Unable to initialize audio conversion."];
        goto cleanup;
    }

    // Player time is normalized so playback starts at 0, while packet PTS keeps the
    // container's original epoch. Subtract the stream start so both clocks match.
    NSTimeInterval streamStartOffset = 0;
    if (audioStream->start_time != AV_NOPTS_VALUE) {
        streamStartOffset = audioStream->start_time * av_q2d(audioStream->time_base);
    } else if (formatContext->start_time != AV_NOPTS_VALUE) {
        streamStartOffset = (NSTimeInterval)formatContext->start_time / AV_TIME_BASE;
    }

    if (_startTime > 0) {
        int64_t timestamp = av_rescale_q((int64_t)((_startTime + streamStartOffset) * AV_TIME_BASE), AV_TIME_BASE_Q, audioStream->time_base);
        avformat_seek_file(formatContext, audioStreamIndex, INT64_MIN, timestamp, timestamp, AVSEEK_FLAG_BACKWARD);
        avcodec_flush_buffers(codecContext);
    }

    frame = av_frame_alloc();
    if (!frame) {
        resultError = [self errorWithCode:9 description:@"Unable to allocate an audio frame."];
        goto cleanup;
    }

    IJKAudioReadState state = {
        .codecContext = codecContext,
        .frame = frame,
        .swrContext = swrContext,
        .stream = audioStream,
        .audioBuffer = &audioBuffer,
        .audioBufferSize = &audioBufferSize,
        .streamStartOffset = streamStartOffset,
        .startTime = _startTime,
        .endTime = _endTime,
        .mediaDuration = formatContext->duration == AV_NOPTS_VALUE ? 0 : (NSTimeInterval)formatContext->duration / AV_TIME_BASE,
        .runningPosition = _startTime,
        .reachedEnd = NO,
        .decoderDone = NO,
    };

    while (![self isCancelled] && !state.reachedEnd && !state.decoderDone) {
        int readResult = av_read_frame(formatContext, &packet);
        if (readResult >= 0) {
            if (packet.stream_index != audioStreamIndex) {
                av_packet_unref(&packet);
                continue;
            }
            while (![self isCancelled] && !state.reachedEnd) {
                int sendResult = avcodec_send_packet(codecContext, &packet);
                BOOL decoderFull = (sendResult == AVERROR(EAGAIN));
                if (sendResult < 0 && !decoderFull && sendResult != AVERROR_EOF) {
                    resultError = [self errorWithCode:10 description:@"Unable to decode the audio packet."];
                    state.reachedEnd = YES;
                    break;
                }
                if (ijk_audio_reader_drain(self, &state, audioCallback, progress) < 0) {
                    resultError = [self errorWithCode:11 description:@"Unable to decode the audio frame."];
                    state.reachedEnd = YES;
                    break;
                }
                if (!decoderFull) {
                    break;
                }
            }
            av_packet_unref(&packet);
        } else if (readResult == AVERROR_EOF) {
            // End of file: flush the decoder, then drain samples buffered in the resampler.
            avcodec_send_packet(codecContext, NULL);
            if (ijk_audio_reader_drain(self, &state, audioCallback, progress) < 0) {
                resultError = [self errorWithCode:11 description:@"Unable to decode the audio frame."];
                break;
            }
            while (![self isCancelled] && !state.reachedEnd) {
                int pendingSamples = (int)swr_get_delay(swrContext, 16000);
                if (pendingSamples <= 0) {
                    break;
                }
                int outputSize = av_samples_get_buffer_size(NULL, 1, pendingSamples, AV_SAMPLE_FMT_S16, 1);
                if (outputSize <= 0) {
                    break;
                }
                av_fast_malloc(&audioBuffer, &audioBufferSize, outputSize);
                if (!audioBuffer) {
                    break;
                }
                uint8_t *output[] = { audioBuffer };
                int convertedSamples = swr_convert(swrContext, output, pendingSamples, NULL, 0);
                if (convertedSamples <= 0) {
                    break;
                }
                ijk_audio_reader_emit(&state, audioBuffer, convertedSamples, state.runningPosition, audioCallback, progress);
            }
            break;
        } else {
            resultError = [self errorWithCode:12 description:@"Unable to read the media stream."];
            break;
        }
    }

cleanup:
    av_packet_unref(&packet);
    av_freep(&audioBuffer);
    swr_free(&swrContext);
    av_frame_free(&frame);
    avcodec_free_context(&codecContext);
    avformat_close_input(&formatContext);
    if ([self isCancelled]) {
        return nil;
    }
    return resultError;
}

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

@end

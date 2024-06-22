//
//  IJKMediaStreamDownloader.m
//  IJKMediaPlayer
//
//  Created by Alexander Graschenkov on 02.06.2024.
//  Copyright © 2024 bilibili. All rights reserved.
//

#import "IJKMediaStreamDownloader.h"
#import "IJTrackMetadata.h"

#import <libavcodec/avcodec.h>
#import <libavformat/avformat.h>
#import <libavutil/imgutils.h>
#import <libswscale/swscale.h>
#import <libavutil/timestamp.h>

#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>


@interface IJTrackMetadata (Hidden)
+ (NSDictionary *)AVDictionaryToNSDictionary:(AVDictionary *)avDictionary;
+ (instancetype)metadataWithAVDictionary:(AVDictionary *)avDictionary;
@end

@implementation TrackInfoObjc
+ (TrackInfoObjc *)createWith:(AVStream*)stream index:(int)index {
    TrackInfoObjc *info = [TrackInfoObjc new];
    info.index = index;
    
    // Get codec parameters
    AVCodecParameters *codecpar = stream->codecpar;
    
    AVCodec *codec = avcodec_find_decoder(codecpar->codec_id);
    info.codecName = [NSString stringWithUTF8String:codec->name];
    
    switch (codecpar->codec_type) {
        case AVMEDIA_TYPE_VIDEO:
            info.type = TrackCodecTypeVideo;
            info.resolution = CGSizeMake((CGFloat)codecpar->width,
                                         (CGFloat)codecpar->height);
            break;
        case AVMEDIA_TYPE_AUDIO:
            info.type = TrackCodecTypeAudio;
            break;
        case AVMEDIA_TYPE_SUBTITLE:
            info.type = TrackCodecTypeSubtitle;
            break;
        default:
            break;
    }
    
    info.bitrate = codecpar->bit_rate;
    
    NSDictionary * metadata = [IJTrackMetadata AVDictionaryToNSDictionary:stream->metadata];
    info.name = metadata[@"title"] ?: metadata[@"comment"];
    info.language = metadata[@"language"];
    info.variantBitrate = [metadata[@"variant_bitrate"] longLongValue];
    
    return info;
}
@end

@implementation ProgramInfoObjc
+ (ProgramInfoObjc *)createWith:(AVProgram*)program {
    ProgramInfoObjc *info = [ProgramInfoObjc new];
    info.metadata = [IJTrackMetadata AVDictionaryToNSDictionary:program->metadata];
    NSMutableArray *streams = [NSMutableArray new];
    for (int i = 0; i < program->nb_stream_indexes; i++) {
        [streams addObject:@(program->stream_index[i])];
    }
    info.streamIndexes = streams;
    return info;
}
@end

@implementation IJKMediaStreamDownloader

+ (int)downloadVideoStream_new:(NSURL*)url toLocation:(NSURL*)location {
    
    const char *inputUrl = [[url absoluteString] cStringUsingEncoding:kCFStringEncodingUTF8];
    const char *outputFilename = [[location absoluteString] cStringUsingEncoding:kCFStringEncodingUTF8];
    
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


// Calculate total duration of all streams
static int64_t calculate_total_duration(AVFormatContext *ifmt_ctx) {
    int64_t total_duration = 0;
    for (unsigned int i = 0; i < ifmt_ctx->nb_streams; ++i) {
        if (ifmt_ctx->streams[i]->duration != AV_NOPTS_VALUE) {
            int64_t duration = av_rescale_q(ifmt_ctx->streams[i]->duration,
                                            ifmt_ctx->streams[i]->time_base, AV_TIME_BASE_Q);
            if (duration > total_duration) {
                total_duration = duration;
            }
        }
    }
    return total_duration;
}

static int downloadStream(AVFormatContext *ifmt_ctx, const AVOutputFormat *ofmt, AVFormatContext **ofmt_ctx, const char *out_filename, int *stream_mapping, int stream_mapping_size, DownloadProgressClosure progress, bool *canceled) {
    AVPacket *pkt = av_packet_alloc();
    if (!pkt) {
        fprintf(stderr, "Could not allocate AVPacket\n");
        return AVERROR_UNKNOWN;
    }
    
    av_dump_format(*ofmt_ctx, 0, out_filename, 1);
    
    int ret = 0;
    if (!(ofmt->flags & AVFMT_NOFILE)) {
        ret = avio_open(&(*ofmt_ctx)->pb, out_filename, AVIO_FLAG_WRITE);
        if (ret < 0) {
            fprintf(stderr, "Could not open output file '%s'", out_filename);
            goto end;
        }
    }
    
    if (*canceled) {
        goto end;
    }
    
    ret = avformat_write_header(*ofmt_ctx, NULL);
    if (ret < 0) {
        fprintf(stderr, "Error occurred when opening output file\n");
        goto end;
    }
    
    double total_duration = ifmt_ctx->duration;// calculate_total_duration(ifmt_ctx);
    double current_duration = 0;
    int progress_stream_idx = -1;
    for (int i = 0; i < ifmt_ctx->nb_streams; i++) {
        if (stream_mapping[i] < 0) continue;
        AVStream *stream = ifmt_ctx->streams[i];
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) continue;
        if (stream->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            progress_stream_idx = i;
            break;
        }
        progress_stream_idx = i;
    }
    progress(false, false, 0, 10000, nil);
    while (1) {
        if (*canceled) break;
        AVStream *in_stream, *out_stream;
        
        ret = av_read_frame(ifmt_ctx, pkt);
        if (ret < 0)
            break;
        
        in_stream  = ifmt_ctx->streams[(pkt)->stream_index];
        if (pkt->stream_index >= stream_mapping_size ||
            stream_mapping[pkt->stream_index] < 0) {
            av_packet_unref(pkt);
            continue;
        }
        
        pkt->stream_index = stream_mapping[pkt->stream_index];
        out_stream = (*ofmt_ctx)->streams[pkt->stream_index];
//        log_packet(ifmt_ctx, pkt, "in");
        
        if (progress_stream_idx == pkt->stream_index) {
            current_duration = av_rescale_q(pkt->pts, in_stream->time_base, AV_TIME_BASE_Q);
            double progressVal = (current_duration / total_duration);
            progressVal = MAX(0, MIN(1, progressVal));
            progressVal = round(10000 * progressVal);
            progress(false, false, progressVal, 10000, nil);
        }
        
        /* copy packet */
        av_packet_rescale_ts(pkt, in_stream->time_base, out_stream->time_base);
        pkt->pos = -1;
        //        log_packet(ofmt_ctx, pkt, "out");
        
        ret = av_interleaved_write_frame(*ofmt_ctx, pkt);
        /* pkt is now blank (av_interleaved_write_frame() takes ownership of
         * its contents and resets pkt), so that no unreferencing is necessary.
         * This would be different if one used av_write_frame(). */
        if (ret < 0) {
            fprintf(stderr, "Error muxing packet\n");
            break;
        }
    }
    av_write_trailer(*ofmt_ctx);
    
end:
    av_packet_free(&pkt);
    return ret;
}

bool selectTracks(AVFormatContext *ctx, FilterTracksClosure filterClosure, int *stream_mapping) {
    NSMutableArray<TrackInfoObjc *> *tracks = [NSMutableArray new];
    int videoCount = 0;
    int audioCount = 0;
    for (int i = 0; i < ctx->nb_streams; i++) {
        stream_mapping[i] = -1;
        AVStream *in_stream = ctx->streams[i];
        AVCodecParameters *in_codecpar = in_stream->codecpar;
        if (in_codecpar->codec_type != AVMEDIA_TYPE_AUDIO &&
            in_codecpar->codec_type != AVMEDIA_TYPE_VIDEO &&
            in_codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE) {
            continue;
        }
        TrackInfoObjc *info = [TrackInfoObjc createWith:in_stream index:i];
        if (in_codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            audioCount++;
        } else if (in_codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoCount++;
        }
        [tracks addObject:info];
    }
    
    NSMutableArray<ProgramInfoObjc *> *programs = NULL;
    for (int i = 0; i < ctx->nb_programs; i++) {
        if (!programs) {
            programs = [NSMutableArray new];
        }
        ProgramInfoObjc *program = [ProgramInfoObjc createWith:ctx->programs[i]];
        [programs addObject:program];
    }
    
    NSArray<TrackInfoObjc *> *outTracks = tracks;
    if (videoCount > 1 || audioCount > 1) {
        outTracks = filterClosure(tracks, programs);
    }
    if (outTracks.count == 0) {
        return false;
    }
    for (int i = 0; i < outTracks.count; i++) {
        stream_mapping[outTracks[i].index] = i;
    }
    NSLog(@"Streams to download: ");
    for (int i = 0; i < ctx->nb_streams; i++) {
        if (stream_mapping[i] < 0) {
            ctx->streams[i]->discard = AVDISCARD_ALL;
        }
        NSLog(@"%d -> %d", i, (int)stream_mapping[i]);
    }
    return true;
}

+ (int)downloadVideoStream:(NSURL*)url
                toLocation:(NSURL*)location
              chooseTracks:(FilterTracksClosure)filterClosure
                  progress:(DownloadProgressClosure)progress
                  canceled:(BOOL*)canceled {
    avformat_network_init();
    av_register_all();
    
    const AVOutputFormat *ofmt = NULL;
    AVFormatContext *ifmt_ctx = NULL, *ofmt_ctx = NULL;
    const char *in_filename, *out_filename;
    int ret, i;
    int stream_index = 0;
    int *stream_mapping = NULL;
    int stream_mapping_size = 0;

    in_filename  = [[url absoluteString] cStringUsingEncoding:kCFStringEncodingUTF8];
    out_filename = [[location path] cStringUsingEncoding:kCFStringEncodingUTF8];

    if ((ret = avformat_open_input(&ifmt_ctx, in_filename, 0, 0)) < 0) {
        fprintf(stderr, "Could not open input file '%s'", in_filename);
        goto end;
    }
    if (*canceled) {
        goto end;
    }

    if ((ret = avformat_find_stream_info(ifmt_ctx, 0)) < 0) {
        fprintf(stderr, "Failed to retrieve input stream information");
        goto end;
    }
    if (*canceled) {
        goto end;
    }

    av_dump_format(ifmt_ctx, 0, in_filename, 0);

    avformat_alloc_output_context2(&ofmt_ctx, NULL, NULL, out_filename);
    if (!ofmt_ctx) {
        fprintf(stderr, "Could not create output context\n");
        ret = AVERROR_UNKNOWN;
        goto end;
    }
    if (*canceled) {
        goto end;
    }

    stream_mapping_size = ifmt_ctx->nb_streams;
    stream_mapping = av_calloc(stream_mapping_size, sizeof(int));
    if (!stream_mapping) {
        ret = AVERROR(ENOMEM);
        goto end;
    }

    ofmt = ofmt_ctx->oformat;
    if (!selectTracks(ifmt_ctx, filterClosure, stream_mapping)) {
        // вероятно пользователь отменил выбор
        *canceled = true;
        goto end;
    }
    if (*canceled) {
        goto end;
    }

    for (i = 0; i < ifmt_ctx->nb_streams; i++) {
        if (stream_mapping[i] < 0) continue;
        
        AVStream *out_stream;
        AVStream *in_stream = ifmt_ctx->streams[i];
        AVCodecParameters *in_codecpar = in_stream->codecpar;

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
    ret = downloadStream(ifmt_ctx, ofmt, &ofmt_ctx, out_filename, stream_mapping, stream_mapping_size, progress, canceled);
end:

    avformat_close_input(&ifmt_ctx);

    /* close output */
    if (ofmt_ctx && !(ofmt->flags & AVFMT_NOFILE))
        avio_closep(&ofmt_ctx->pb);
    avformat_free_context(ofmt_ctx);

    av_freep(&stream_mapping);
    
    if (*canceled) {
        [[NSFileManager defaultManager] removeItemAtURL:location error:NULL];
    }

    if (ret < 0 && ret != AVERROR_EOF) {
        fprintf(stderr, "Error occurred: %s\n", av_err2str(ret));
        NSString *msg = [NSString stringWithCString:av_err2str(ret)];
        NSError *err = [NSError errorWithDomain:@"VideoStreamDownload" code:ret userInfo:@{NSLocalizedDescriptionKey: msg}];
        progress(false, false, 0, 0, err);
        return -1;
    } else if (*canceled) {
        progress(false, true, 0, 0, nil);
    } else {
        progress(true, false, 0, 0, nil);
    }

    return 0;
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

        if (i <= 13) {
            stream_mapping[i] = -1;
            ifmt_ctx->streams[i]->discard = AVDISCARD_ALL;
            continue;
        }
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
+ (int)downloadVideoStream:(NSURL*)url
                toLocation:(NSURL*)location {
    avformat_network_init();
    av_register_all();
    
    AVFormatContext *inputFormatContext = NULL, *outputFormatContext = NULL;
    AVPacket packet;
    int ret, i;
    double tt1 = CACurrentMediaTime();
    
    char *inputUrl = [[url absoluteString] cStringUsingEncoding:kCFStringEncodingUTF8];
    char *outputFilename = [[location path] cStringUsingEncoding:kCFStringEncodingUTF8];
    ffmpeg_remux(inputUrl, outputFilename);
    
    double tt2 = CACurrentMediaTime();
    NSLog(@"Final: %.3lf", tt2-tt1);
    
    return 0;
}

@end

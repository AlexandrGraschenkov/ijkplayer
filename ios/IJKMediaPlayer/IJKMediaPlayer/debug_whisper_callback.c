//
//  debug_whisper_callback.cpp
//  IJKMediaPlayer
//
//  Created by Alexander Graschenkov on 07.02.2025.
//  Copyright © 2025 bilibili. All rights reserved.
//

#include <stdio.h>

// C
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

typedef uint64_t u64;
typedef int64_t  s64;
typedef uint32_t u32;
typedef int32_t  s32;
typedef uint16_t u16;
typedef int16_t  s16;
typedef uint8_t   u8;
typedef int8_t    s8;

struct wave_hdr {
    /* RIFF Header: "RIFF" */
    char riff_header[4];
    /* size of audio data + sizeof(struct wave_hdr) - 8 */
    int wav_size;
    /* "WAVE" */
    char wav_header[4];

    /* Format Header */
    /* "fmt " (includes trailing space) */
    char fmt_header[4];
    /* Should be 16 for PCM */
    int fmt_chunk_size;
    /* Should be 1 for PCM. 3 for IEEE Float */
    s16 audio_format;
    s16 num_channels;
    int sample_rate;
    /*
     * Number of bytes per second
     * sample_rate * num_channels * bit_depth/8
     */
    int byte_rate;
    /* num_channels * bytes per sample */
    s16 sample_alignment;
    /* bits per sample */
    s16 bit_depth;

    /* Data Header */
    /* "data" */
    char data_header[4];
    /*
     * size of audio
     * number of samples * num_channels * bit_depth/8
     */
    int data_bytes;
} typedef wave_hdr  __attribute__((__packed__));

#define WAVE_SAMPLE_RATE    16000

static void set_wave_hdr(struct wave_hdr *wh, size_t size) {
    memcpy(wh->riff_header, "RIFF", 4);
    wh->wav_size = size + sizeof(struct wave_hdr) - 8;
    memcpy(wh->wav_header, "WAVE", 4);
    memcpy(wh->fmt_header, "fmt ", 4);
    wh->fmt_chunk_size = 16;
    wh->audio_format = 1;
    wh->num_channels = 1;
    wh->sample_rate = WAVE_SAMPLE_RATE;
    wh->sample_alignment = 2;
    wh->bit_depth = 16;
    wh->byte_rate = wh->sample_rate * wh->sample_alignment;
    memcpy(wh->data_header, "data", 4);
    wh->data_bytes = size;
}

//void media_player_whisper_callback(const uint8_t *data, int size, void *user_data) {
////    static FILE *output_file = NULL;
//    static std::vector<uint8_t> owav_data;
//    int currentSize = owav_data.size();
//    owav_data.resize(owav_data.size() + size);
//    memcpy(owav_data.data() + currentSize, data, size);
//    
//    printf("••• Write wav: %d; total: %d", size, owav_data.size());
//    FILE *output_file = fopen("/Users/alex/Downloads/test_audio_parse.wav", "wb");
//    if (!output_file) {
//        perror("Failed to open output file");
//        return;
//    }
//    
//    wave_hdr wh;
//    set_wave_hdr(wh, owav_data.size());
//    fwrite(&wh, sizeof(wave_hdr), size, output_file);
//    
//    size_t bytes_written = fwrite(data, sizeof(uint8_t), size, output_file);
//    
//    fclose(output_file);
//}
void media_player_whisper_callback(const uint8_t *data, int size, void *user_data) {
    static uint8_t *owav_data = NULL;
    static int owav_size = 0;

    // Reallocate memory to store the new data
    uint8_t *new_data = realloc(owav_data, owav_size + size);
    if (!new_data) {
        perror("Failed to allocate memory");
        return;
    }
    owav_data = new_data;

    // Copy the new data into the buffer
    memcpy(owav_data + owav_size, data, size);
    owav_size += size;

    printf("••• Write wav: %d; total: %d\n", size, owav_size);

    // Open the output file in binary write mode
    FILE *output_file = fopen("/Users/alex/Downloads/test_audio_parse.wav", "wb");
    if (!output_file) {
        perror("Failed to open output file");
        return;
    }

    // Write the WAV header
    wave_hdr wh;
    set_wave_hdr(&wh, owav_size);
    fwrite(&wh, sizeof(wave_hdr), 1, output_file);

    // Write the accumulated data to the file
    fwrite(owav_data, sizeof(uint8_t), owav_size, output_file);

    // Close the file
    fclose(output_file);
}

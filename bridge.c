#ifdef WIN32
#define EXPORT extern __declspec (dllexport)
#else
#define EXPORT extern
#endif

#include <soundio/soundio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static void write_callback(struct SoundIoOutStream *outstream, int frame_count_min, int frame_count_max) {
  struct SoundIoRingBuffer *ring_buffer = outstream->userdata;
  struct SoundIoChannelArea *areas;
  int frame_count;
  int frames_left;
  int err;

  char *read_ptr = soundio_ring_buffer_read_ptr(ring_buffer);
  int fill_bytes = soundio_ring_buffer_fill_count(ring_buffer);
  int fill_count = fill_bytes / outstream->bytes_per_frame;

  if (frame_count_min > fill_count) {
    // Ring buffer does not have enough data, fill with zeroes.
    frames_left = frame_count_min;
    for (;;) {
      frame_count = frames_left;
      if (!frame_count)
        return;
      if ((err = soundio_outstream_begin_write(outstream, &areas, &frame_count))) {
        fprintf(stderr, "0 begin_write: %s\n", soundio_strerror(err));
        // REVIEW pthread_exit?
        exit(1);
      }
      if (!frame_count)
        return;
      for (int frame = 0; frame < frame_count; frame += 1) {
        for (int ch = 0; ch < outstream->layout.channel_count; ch += 1) {
          memset(areas[ch].ptr, 0, outstream->bytes_per_sample);
          areas[ch].ptr += areas[ch].step;
        }
      }
      if ((err = soundio_outstream_end_write(outstream))) {
        fprintf(stderr, "0 end_write: %s\n", soundio_strerror(err));
        // REVIEW pthread_exit?
        exit(1);
      }
      frames_left -= frame_count;
    }
  }

  int read_count = frame_count_max < fill_count ? frame_count_max : fill_count;
  frames_left = read_count;

  while (frames_left > 0) {
    int frame_count = frames_left;

    if ((err = soundio_outstream_begin_write(outstream, &areas, &frame_count))) {
      fprintf(stderr, "1 begin_write: %s\n", soundio_strerror(err));
      // REVIEW pthread_exit?
      exit(1);
    }

    if (frame_count <= 0)
      break;

    for (int frame = 0; frame < frame_count; frame += 1) {
      for (int ch = 0; ch < outstream->layout.channel_count; ch += 1) {
        memcpy(areas[ch].ptr, read_ptr, outstream->bytes_per_sample);
        areas[ch].ptr += areas[ch].step;
        read_ptr += outstream->bytes_per_sample;
      }
    }

    if ((err = soundio_outstream_end_write(outstream))) {
      fprintf(stderr, "1 end_write: %s\n", soundio_strerror(err));
      // REVIEW pthread_exit?
      exit(1);
    }

    frames_left -= frame_count;
  }

  soundio_ring_buffer_advance_read_ptr(ring_buffer, read_count * outstream->bytes_per_frame);
}

EXPORT void bridge_outstream_attach_ring_buffer
(struct SoundIoOutStream *outstream, struct SoundIoRingBuffer *buffer) {
  outstream->format = SoundIoFormatFloat32NE;
  outstream->userdata = buffer;
  outstream->write_callback = write_callback;
}

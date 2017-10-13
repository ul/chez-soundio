#ifdef WIN32
#define EXPORT extern __declspec (dllexport)
#else
#define EXPORT extern
#endif

#include <sys/select.h>
#include <soundio/soundio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "scheme.h"

// <write_callback>
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
    // <fill-stream-with-zeros>
    frames_left = frame_count_min;
    for (;;) {
      frame_count = frames_left;
      if (!frame_count)
        return;
    
      // <begin-write>
      if ((err = soundio_outstream_begin_write(outstream, &areas, &frame_count))) {
        fprintf(stderr, "begin_write: %s\n", soundio_strerror(err));
        exit(1);
      }
      // </begin-write>
    
      if (!frame_count)
        return;
      for (int frame = 0; frame < frame_count; frame += 1) {
        for (int ch = 0; ch < outstream->layout.channel_count; ch += 1) {
          memset(areas[ch].ptr, 0, outstream->bytes_per_sample);
          areas[ch].ptr += areas[ch].step;
        }
      }
    
      // <end-write>
      if ((err = soundio_outstream_end_write(outstream))) {
        fprintf(stderr, "end_write: %s\n", soundio_strerror(err));
        // REVIEW pthread_exit?
        exit(1);
      }
      // </end-write>
    
      frames_left -= frame_count;
    }
    // </fill-stream-with-zeros>
  }

  // <copy-samples-from-buffer>
  int read_count = frame_count_max < fill_count ? frame_count_max : fill_count;
  frames_left = read_count;
  
  while (frames_left > 0) {
    int frame_count = frames_left;
  
    // <begin-write>
    if ((err = soundio_outstream_begin_write(outstream, &areas, &frame_count))) {
      fprintf(stderr, "begin_write: %s\n", soundio_strerror(err));
      exit(1);
    }
    // </begin-write>
  
    if (frame_count <= 0)
      break;
  
    for (int frame = 0; frame < frame_count; frame += 1) {
      for (int ch = 0; ch < outstream->layout.channel_count; ch += 1) {
        memcpy(areas[ch].ptr, read_ptr, outstream->bytes_per_sample);
        areas[ch].ptr += areas[ch].step;
        read_ptr += outstream->bytes_per_sample;
      }
    }
  
    // <end-write>
    if ((err = soundio_outstream_end_write(outstream))) {
      fprintf(stderr, "end_write: %s\n", soundio_strerror(err));
      // REVIEW pthread_exit?
      exit(1);
    }
    // </end-write>
  
    frames_left -= frame_count;
  }
  // </copy-samples-from-buffer>

  soundio_ring_buffer_advance_read_ptr(ring_buffer, read_count * outstream->bytes_per_frame);
}
// </write_callback>
// <bridge_outstream_attach_ring_buffer>
EXPORT void bridge_outstream_attach_ring_buffer
(struct SoundIoOutStream *outstream, struct SoundIoRingBuffer *buffer) {
  outstream->format = SoundIoFormatFloat32NE;
  outstream->userdata = buffer;
  outstream->write_callback = write_callback;
}
// </bridge_outstream_attach_ring_buffer>
// <usleep>
EXPORT void usleep (long seconds, long microseconds) {
  struct timeval timeout;
  timeout.tv_sec = seconds;
  timeout.tv_usec = microseconds;
  Sdeactivate_thread();
  select(0, NULL, NULL, NULL, &timeout);
  Sactivate_thread();
}
// </usleep>

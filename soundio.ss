(library (soundio (1))
  (export open-default-out-stream
          start-out-stream
          stop-out-stream
          teardown-out-stream
          sound-out-sample-rate
          sound-out-channel-count
          sound-out-write-callback-set!
          usleep)
  (import (chezscheme))
  (include "soundio-ffi.ss")
  ;; <build-bridge>
  (define bridge-name "bridge")
  (define bridge-lib (format "lib~a.so" bridge-name))
  
  (define init-bridge
    (begin
      (unless (file-exists? bridge-lib)
        (case (machine-type)
          [(i3nt ti3nt a6nt ta6nt)
           (begin
             ;; FIXME link to soundio
             (system (format "cl -c -DWIN32 ~a.c" bridge-name))
             (system (format "link -dll -out:~a ~a.obj" bridge-lib bridge-name)))]
          [(i3osx ti3osx a6osx ta6osx)
           (system (format "cc -O3 -dynamiclib -Wl,-undefined -Wl,dynamic_lookup -I/usr/local/lib/csv9.4.1/ta6osx -lsoundio -o ~a ~a.c" bridge-lib bridge-name))]
          [(i3le ti3le a6le ta6le)
           (system (format "cc -O3 -fPIC -shared -lsoundio -o ~a ~a.c" bridge-lib bridge-name))]
          [else (error "soundio"
                       "don't know how to build bridge shared library on this machine-type"
                       (machine-type))]))
  
      (load-shared-object bridge-lib)))
  ;; </build-bridge>
  (define-foreign-procedure
    [bridge_outstream_attach_ring_buffer ((* SoundIoOutStream) (* SoundIoRingBuffer)) void]
    [usleep (long long) void])
  (define-record-type sound-out
    (fields stream
            ring-buffer
            channel-count
            sample-rate
            (mutable write-callback)
            (mutable write-thread)))
  (define open-default-out-stream
    (lambda (write-callback)
      (let ([sio (soundio_create)])
        (when (ftype-pointer-null? sio)
          (error "soundio_create" "out of memory"))
        (let ([err (soundio_connect sio)])
          (when (not (zero? err))
            (error "soundio_connect" (soundio_strerror err)))
          (soundio_flush_events sio)
          (let ([idx (soundio_default_output_device_index sio)])
            (when (< idx 0)
              (error "soundio_default_output_device_index" "no output device found"))
            (let ([device (soundio_get_output_device sio idx)])
              (when (ftype-pointer-null? device)
                (error "soundio_get_output_device" "out of memory"))
              (let ([out-stream (soundio_outstream_create device)])
                (when (ftype-pointer-null? out-stream)
                  (error "soundio_outstream_create" "out of memory"))
                (let ([err (soundio_outstream_open out-stream)])
                  (when (not (zero? err))
                    (error "soundio_outstream_open" (soundio_strerror err)))
                  (let ([err (ftype-ref SoundIoOutStream (layout_error) out-stream)])
                    (when (not (zero? err))
                      (error "soundio_outstream_open" (soundio_strerror err))))
                  (let* ([frame-size (ftype-sizeof float)]
                         [channel-count (ftype-ref SoundIoOutStream (layout channel_count) out-stream)]
                         [sample-rate (ftype-ref SoundIoOutStream (sample_rate) out-stream)]
                         [latency (ftype-ref SoundIoOutStream (software_latency) out-stream)]
                         [buffer-size (exact (ceiling (* latency sample-rate)))] ; in samples
                         [buffer-capacity (* buffer-size frame-size channel-count)] ; in bytes
                         ;; REVIEW
                         [ring-buffer (soundio_ring_buffer_create sio buffer-capacity)])
                    (when (ftype-pointer-null? ring-buffer)
                      (error "soundio_ring_buffer_create" "out of memory"))
                    (bridge_outstream_attach_ring_buffer out-stream ring-buffer)
                    (printf "Channels:\t~s\r\n" channel-count)
                    (printf "Sample rate:\t~s\r\n" sample-rate)
                    (printf "Latency:\t~s\r\n" latency)
                    (printf "Buffer:\t\t~s\r\n" buffer-size)
                    (make-sound-out
                     out-stream
                     ring-buffer
                     channel-count
                     sample-rate
                     write-callback
                     #f)
                    )
                  )
                )
              ))
          ))
      ))
  (define start-out-stream
    (lambda (sound-out)
      (let* ([frame-size (ftype-sizeof float)]
             [out-stream (sound-out-stream sound-out)]
             [channel-count (ftype-ref SoundIoOutStream (layout channel_count) out-stream)]
             [sample-rate (ftype-ref SoundIoOutStream (sample_rate) out-stream)]
             [seconds-per-sample (inexact (/ sample-rate))]
             [ring-buffer (sound-out-ring-buffer sound-out)]
             [polling-usec 1000]
             [sample-number 0])
        (sound-out-write-thread-set! sound-out #t)
        (fork-thread
         (lambda ()
           (let loop ()
             (when (sound-out-write-thread sound-out)
               (let ([write-callback (sound-out-write-callback sound-out)]
                     [free-count (soundio_ring_buffer_free_count ring-buffer)])
                 (if (zero? free-count)
                     (begin
                       (usleep 0 polling-usec)
                       (loop))
                     (let ([free-frames (/ free-count frame-size channel-count)]
                           [write-ptr (ftype-pointer-address (soundio_ring_buffer_write_ptr ring-buffer))])
                       (do ([frame 0 (+ frame 1)])
                           ((= frame free-frames) 0)
                         (let* ([sample-number (+ sample-number frame)]
                                [time (fl* (fixnum->flonum sample-number) seconds-per-sample)])
                           (do ([channel 0 (+ channel 1)])
                               ((= channel channel-count) 0)
                             (foreign-set!
                              'float
                              write-ptr
                              (* (+ (* frame channel-count) channel) frame-size)
                              (guard (x [else 0.0]) (write-callback time channel)))
                             )))
                       (soundio_ring_buffer_advance_write_ptr ring-buffer free-count)
                       (set! sample-number (+ sample-number free-frames))
                       (loop))
                     ))))))
        (soundio_outstream_start out-stream))))
  
  (define stop-out-stream
    (lambda (sound-out)
      (sound-out-write-thread-set! sound-out #f)
      ;; (soundio_outstream_pause (sound-out-stream sound-out) #t)
      ))
  (define teardown-out-stream
    (lambda (sound-out)
      (let* ([stream (sound-out-stream sound-out)]
             [ring-buffer (sound-out-ring-buffer sound-out)]
             [device (ftype-ref SoundIoOutStream (device) stream)]
             [soundio (ftype-ref SoundIoDevice (soundio) device)])
        (soundio_outstream_destroy stream)
        (soundio_ring_buffer_destroy ring-buffer)
        (soundio_device_unref device)
        (soundio_destroy soundio))))
)

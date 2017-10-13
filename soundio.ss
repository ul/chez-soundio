(library (soundio (1))
  (export open-default-out-stream
          start-out-stream
          stop-out-stream
          teardown-out-stream
          sample-rate
          channel-count
          usleep)
  (import (chezscheme))
  (include "soundio-ffi.ss")
  ;; <high-level-wrapper>
  ;; <build-bridge>
  ;; <bridge-paths>
  (define bridge-source-filename "bridge.c")
  (define bridge-library-filename "libbridge.so")
  (define scheme-headers-path (format "/usr/local/lib/csv9.4.1/~a" (machine-type)))
  ;; </bridge-paths>
  (define init-bridge
    (begin
      (unless (file-exists? bridge-library-filename)
        ;; <build-bridge>
        (case (machine-type)
          [(i3nt ti3nt a6nt ta6nt)
           (begin
             (error "init-bridge"
                    "don't know how to build for Windows, look at the source for template to adjust")
             (system (format "cl -c -DWIN32 ~a"
                             bridge-source-filename))
             (system (format "link -dll -out:~a ~a.obj"
                             bridge-library-filename
                             bridge-source-filename)))]
          [(i3osx ti3osx a6osx ta6osx)
           (system (format "cc -O3 -dynamiclib -Wl,-undefined -Wl,dynamic_lookup -I~a -lsoundio -o ~a ~a"
                           scheme-headers-path
                           bridge-library-filename
                           bridge-source-filename))]
          [(i3le ti3le a6le ta6le)
           (system (format "cc -O3 -fPIC -shared -Wl,-undefined -Wl,dynamic_lookup -I/usr/local/lib/csv9.4.1/~a -lsoundio -o ~a ~a.c"
                           scheme-headers-path
                           bridge-library-filename
                           bridge-source-filename))]
          [else (error "init-bridge"
                       "don't know how to build bridge shared library on this machine-type"
                       (machine-type))])
        ;; </build-bridge>
        )
      (load-shared-object bridge-library-filename)))
  ;; </build-bridge>
  ;; <bridge-ffi>
  (define-foreign-procedure
    [bridge_outstream_attach_ring_buffer ((* SoundIoOutStream) (* SoundIoRingBuffer)) void]
    [usleep (long #|seconds|# long #|microseconds|#) void])
  ;; </bridge-ffi>
  ;; <sound-out-record>
  (define-record-type sound-out
    (fields stream
            ring-buffer
            (mutable write-callback)
            (mutable write-thread)))
  ;; </sound-out-record>
  ;; <open-default-out-stream>
  (define (open-default-out-stream write-callback)
    ;; <try-create-connect-sio>
    (let ([sio (soundio_create)])
      (when (ftype-pointer-null? sio)
        (error "soundio_create" "out of memory"))
      (let ([err (soundio_connect sio)])
        (when (not (zero? err))
          (error "soundio_connect" (soundio_strerror err)))
        (soundio_flush_events sio)
        ;; <try-create-device>
        (let ([idx (soundio_default_output_device_index sio)])
          (when (< idx 0)
            (error "soundio_default_output_device_index" "no output device found"))
          (let ([device (soundio_get_output_device sio idx)])
            (when (ftype-pointer-null? device)
              (error "soundio_get_output_device" "out of memory"))
            ;; <try-create-stream>
            (let ([out-stream (soundio_outstream_create device)])
              (when (ftype-pointer-null? out-stream)
                (error "soundio_outstream_create" "out of memory"))
              ;; <try-open-stream>
              (let ([err (soundio_outstream_open out-stream)])
                (when (not (zero? err))
                  (error "soundio_outstream_open" (soundio_strerror err)))
                (let ([err (ftype-ref SoundIoOutStream (layout_error) out-stream)])
                  (when (not (zero? err))
                    (error "soundio_outstream_open" (soundio_strerror err))))
                ;; <attach-buffer-to-stream>
                (let* ([frame-size (ftype-sizeof float)]
                       [channel-count (ftype-ref SoundIoOutStream (layout channel_count) out-stream)]
                       [sample-rate (ftype-ref SoundIoOutStream (sample_rate) out-stream)]
                       [latency (ftype-ref SoundIoOutStream (software_latency) out-stream)]
                       [buffer-size (exact (ceiling (* latency sample-rate)))] ; in samples
                       [buffer-capacity (* buffer-size frame-size channel-count)] ; in bytes
                       [ring-buffer (soundio_ring_buffer_create sio buffer-capacity)])
                  (when (ftype-pointer-null? ring-buffer)
                    (error "soundio_ring_buffer_create" "out of memory"))
                  (bridge_outstream_attach_ring_buffer out-stream ring-buffer)
                  ;; <make-sound-out>
                  (printf "Channels:\t~s\r\n" channel-count)
                  (printf "Sample rate:\t~s\r\n" sample-rate)
                  (printf "Latency:\t~s\r\n" latency)
                  (printf "Buffer:\t\t~s\r\n" buffer-size)
                  (make-sound-out out-stream ring-buffer write-callback #f)
                  ;; </make-sound-out>
                  )
                ;; </attach-buffer-to-stream>
                )
              ;; </try-open-stream>
              )
            ;; </try-create-stream>
            ))
        ;; </try-create-device>
        ))
    ;; </try-create-connect-sio>
    )
  ;; </open-default-out-stream>
  ;; <start-out-stream>
  (define (start-out-stream sound-out)
    (let* ([frame-size (ftype-sizeof float)]
           [out-stream (sound-out-stream sound-out)]
           [channel-count (ftype-ref SoundIoOutStream (layout channel_count) out-stream)]
           [sample-rate (ftype-ref SoundIoOutStream (sample_rate) out-stream)]
           [seconds-per-sample (inexact (/ sample-rate))]
           [ring-buffer (sound-out-ring-buffer sound-out)]
           [write-callback (sound-out-write-callback sound-out)]
           [polling-microseconds 1000]
           [sample-number 0])
      (sound-out-write-thread-set! sound-out (get-thread-id))
      (fork-thread
       (lambda ()
         (let loop ()
           (when (sound-out-write-thread sound-out)
             (let ([free-count (soundio_ring_buffer_free_count ring-buffer)])
               (if (zero? free-count)
                   (begin
                     (usleep 0 polling-microseconds)
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
                            (write-callback time channel))
                           )))
                     (soundio_ring_buffer_advance_write_ptr ring-buffer free-count)
                     (set! sample-number (+ sample-number free-frames))
                     (loop))
                   ))))))
      (soundio_outstream_start out-stream)))
  ;; </start-out-stream>
  ;; <stop-out-stream>
  (define (stop-out-stream sound-out)
    (sound-out-write-thread-set! sound-out #f)
    (soundio_outstream_pause (sound-out-stream sound-out) #t))
  ;; </stop-out-stream>
  ;; <teardown-out-stream>
  (define (teardown-out-stream sound-out)
    (let* ([stream (sound-out-stream sound-out)]
           [ring-buffer (sound-out-ring-buffer sound-out)]
           [device (ftype-ref SoundIoOutStream (device) stream)]
           [soundio (ftype-ref SoundIoDevice (soundio) device)])
      (soundio_outstream_destroy stream)
      (soundio_ring_buffer_destroy ring-buffer)
      (soundio_device_unref device)
      (soundio_destroy soundio)))
  ;; </teardown-out-stream>
  ;; <channel-count>
  (define (channel-count sound-out)
    (ftype-ref SoundIoOutStream
               (layout channel_count)
               (sound-out-stream sound-out)))
  ;; </channel-count>
  ;; <sample-rate>
  (define (sample-rate sound-out)
    (ftype-ref SoundIoOutStream
               (sample_rate)
               (sound-out-stream sound-out)))
  ;; </sample-rate>
  ;; </high-level-wrapper>
)

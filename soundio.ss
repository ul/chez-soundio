;; (import (rnrs))

(load-shared-object "libsoundio.dylib")

(define-ftype SoundIoBackend
  int ; TODO enum
  )

(define-ftype SoundIo
  (struct
    (userdata void*) ; Optional. Put whatever you want here. Defaults to NULL.
    (on_devices_change void*) ; Optional callback. TODO function (struct SoundIo *)
    (on_backend_disconnect void*) ; Optional callback. TODO function (struct SoundIo *, int err)
    (on_events_signal void*) ; Optional callback. TODO function (struct SoundIo *)
    (current_backend SoundIoBackend) ; Read-only.
    (app_name (* char)) ; Optional: Application name.
    (emit_rtprio_warning void*) ; Optional: Real time priority warning. TODO function (void)
    (jack_info_callback void*) ; Optional: JACK info callback. TODO function (const char *msg)
    (jack_error_callback void*) ; Optional: JACK error callback. TODO function (const char *msg)
    ))

(define-ftype SoundIoChannelLayout
  (struct
    (name (* char))
    (channel_count int)
    (channels (array 24 int))))

(define-ftype SoundIoOutStream
  (struct
    (device void*)
    (format int)
    (sample_rate int)
    (layout SoundIoChannelLayout)
    (software_latency double)
    (userdata void*)
    (write_callback void*)
    (underflow_callback void*)
    (error_callback void*)
    (name (* char))
    (non_terminal_hint boolean)
    (bytes_per_frame int)
    (bytes_per_sample int)
    (layout_error int)))

(define-ftype SoundIoChannelArea
  (struct
    (ptr (* char))
    (step int)))

(define soundio_version_string
  (foreign-procedure "soundio_version_string" () string))

(define soundio_create
  (foreign-procedure "soundio_create" () void*))

(define soundio_connect
  (foreign-procedure "soundio_connect" (void*) int))

(define soundio_flush_events
  (foreign-procedure "soundio_flush_events" (void*) void))

(define soundio_default_output_device_index
  (foreign-procedure "soundio_default_output_device_index" (void*) int))

(define soundio_get_output_device
  (foreign-procedure "soundio_get_output_device" (void* int) void*))

(define soundio_outstream_create
  (foreign-procedure "soundio_outstream_create" (void*) (* SoundIoOutStream)))

(define soundio_outstream_begin_write
  (foreign-procedure "soundio_outstream_begin_write" (void* void* (* int)) int))

(define soundio_outstream_end_write
  (foreign-procedure "soundio_outstream_end_write" (void*) int))

(define soundio_outstream_open
  (foreign-procedure "soundio_outstream_open" (void*) int))

(define soundio_outstream_start
  (foreign-procedure "soundio_outstream_start" (void*) int))

;;;

(soundio_version_string)
(define soundio (soundio_create))
(soundio_connect soundio)
(soundio_flush_events soundio)
(define out-idx (soundio_default_output_device_index soundio))
(define device (soundio_get_output_device soundio out-idx))
(define stream (soundio_outstream_create device))

(define write-callback
  (let ((code (foreign-callable
               (lambda (stream frame-count-min frame-count-max)
                 (let ([layout (ftype-&ref SoundIoOutStream (layout) stream)]
                       [channel-count (ftype-ref SoundIoChannelLayout (channel_count) layout)]
                       [sample-rate (ftype-ref SoundIoOutStream (sample_rate) stream)]
                       [areas (make-ftype-pointer
                               void*
                               (foreign-alloc (ftype-sizeof void*)))])
                   (let batch ([frames-left frame-count-max])
                     (let ([frame-count frames-left]
                           [err (soundio_outstream_begin_write
                                 stream
                                 (ftype-pointer-address areas)
                                 (ftype-pointer-address (make-ftype-pointer int frame-count)))])
                       (if (and (= err 0) (not (= frame-count 0)))
                           (do ([frame 0 (+ frame 1)])
                               ((= frame frame-count) 0)
                             (do ([channel 0 (+ channel 1)])
                                 ((= channel channel-count) 0)
                               (let ([ptr (+ (ftype-&ref SoundIoChannelArea (ptr) areas channel)
                                             (* (ftype-&ref SoundIoChannelArea (step) areas channel)
                                                frame))])
                                 (foreign-set! float ptr 0 (random 1.0))
                                 )))))
                     (if (< 0 (- frames-left frame-count))
                         (batch (- frames-left frame-count)))))
                 )
               ((* SoundIoOutStream) int int)
               void)))
    (lock-object code)
    (foreign-callable-entry-point code)))

(ftype-set! SoundIoOutStream (write_callback)
            stream
            write-callback)

(soundio_outstream_open (ftype-pointer-address stream))
(soundio_outstream_start (ftype-pointer-address stream))

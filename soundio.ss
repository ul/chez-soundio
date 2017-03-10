(import (chezscheme))

(load-shared-object "libsoundio.dylib")

(define-ftype

  ;; enums
  [SoundIoBackend int]
  [SoundIoChannelId int]
  [SoundIoFormat int]
  [SoundIoDeviceAim int]

  ;; aliases
  [ErrorCode int]
  [Message (* char)]
  [Name (* char)]

  ;; callbacks
  [OnDeviceChangeCallback (function ((* SoundIo)) void)]
  ;; FIXME Exception: invalid function-ftype argument type specifier ErrorCode
  ;; [OnBackendDisconnectCallback (function ((* SoundIo) ErrorCode) void)]
  [OnBackendDisconnectCallback (function ((* SoundIo) int) void)]
  [OnEventsSignalCallback (function ((* SoundIo)) void)]
  [EmitRtprioWarningCallback (function () void)]
  ;; [JackInfoCallback (function (Message) void)]
  ;; [JackErrorCallback (function (Message) void)]
  [JackInfoCallback (function ((* char)) void)]
  [JackErrorCallback (function ((* char)) void)]
  [WriteCallback (function ((* SoundIoOutStream) int int) void)]
  [UnderflowCallback (function ((* SoundIoOutStream)) void)]
  ;; [ErrorCallback (function ((* SoundIoOutStream) ErrorCode) void)]
  [ErrorCallback (function ((* SoundIoOutStream) int) void)]

  ;; structs
  [SoundIo
   (struct
     [userdata void*] ; Optional. Put whatever you want here. Defaults to NULL.
     [on_devices_change (* OnDeviceChangeCallback)] ; Optional callback.
     [on_backend_disconnect (* OnBackendDisconnectCallback)] ; Optional callback.
     [on_events_signal (* OnEventsSignalCallback)] ; Optional callback.
     [current_backend SoundIoBackend] ; Read-only.
     [app_name Name] ; Optional: Application name.
     [emit_rtprio_warning (* EmitRtprioWarningCallback)] ; Optional: Real time priority warning.
     [jack_info_callback (* JackInfoCallback)] ; Optional: JACK info callback.
     [jack_error_callback (* JackErrorCallback)] ; Optional: JACK error callback.
     )]

  [SoundIoChannelLayout
   (struct
     [name Name]
     [channel_count int]
     [channels (array 24 SoundIoChannelId)])]

  [SoundIoDevice
   (struct
     [soundio (* SoundIo)]
     [id Name]
     [name Name]
     [aim SoundIoDeviceAim]
     [layouts (* SoundIoChannelLayout)]
     [layout_count int]
     [current_layout SoundIoChannelLayout]
     [formats (* SoundIoFormat)]
     [format_count int]
     [current_format SoundIoFormat]
     [sample_rates (* SoundIoSampleRateRange)]
     [sample_rate_count int]
     [sample_rate_current int]
     [software_latency_min double]
     [software_latency_max double]
     [software_latency_current double]
     [is_raw boolean]
     [ref_count int]
     [probe_error int])]

  [SoundIoOutStream
   (struct
     [device (* SoundIoDevice)]
     [format SoundIoFormat]
     [sample_rate int]
     [layout SoundIoChannelLayout]
     [software_latency double]
     [userdata void*]
     [write_callback (* WriteCallback)]
     [underflow_callback (* UnderflowCallback)]
     [error_callback (* ErrorCallback)]
     [name Name]
     [non_terminal_hint boolean]
     [bytes_per_frame int]
     [bytes_per_sample int]
     [layout_error ErrorCode])]

  [SoundIoChannelArea
   (struct
     [ptr (* float)] ; REVIEW char
     [step int])]

  [SoundIoSampleRateRange
   (struct
     [min int]
     [max int])]
  [*SoundIoChannelArea (* SoundIoChannelArea)]
  [**SoundIoChannelArea (* (* SoundIoChannelArea))]
  )

(define soundio_version_string
  (foreign-procedure "soundio_version_string" () string))

(define soundio_create
  (foreign-procedure "soundio_create" () (* SoundIo)))

(define soundio_connect
  (foreign-procedure "soundio_connect" ((* SoundIo)) ErrorCode))

(define soundio_flush_events
  (foreign-procedure "soundio_flush_events" ((* SoundIo)) void))

(define soundio_default_output_device_index
  (foreign-procedure "soundio_default_output_device_index" ((* SoundIo)) int))

(define soundio_get_output_device
  (foreign-procedure "soundio_get_output_device" ((* SoundIo) int) (* SoundIoDevice)))

(define soundio_outstream_create
  (foreign-procedure "soundio_outstream_create" ((* SoundIoDevice)) (* SoundIoOutStream)))

;; FIXME Exception: invalid (non-base) foreign-procedure argument ftype **SoundIoChannelArea
(define soundio_outstream_begin_write
  (foreign-procedure "soundio_outstream_begin_write" ((* SoundIoOutStream) ; outstream
                                                      ;; **SoundIoChannelArea ; areas
                                                      (* *SoundIoChannelArea)
                                                      (* int)) ; frame_count
                     ErrorCode))

(define soundio_outstream_end_write
  (foreign-procedure "soundio_outstream_end_write" ((* SoundIoOutStream)) ErrorCode))

(define soundio_outstream_open
  (foreign-procedure "soundio_outstream_open" ((* SoundIoOutStream)) ErrorCode))

(define soundio_outstream_start
  (foreign-procedure "soundio_outstream_start" ((* SoundIoOutStream)) ErrorCode))

(define soundio_wait_events
  (foreign-procedure "soundio_wait_events" ((* SoundIo)) void))

(define soundio_outstream_destroy
  (foreign-procedure "soundio_outstream_destroy" ((* SoundIoOutStream)) void))

(define soundio_device_unref
  (foreign-procedure "soundio_device_unref" ((* SoundIoDevice)) void))

(define soundio_destroy
  (foreign-procedure "soundio_destroy" ((* SoundIo)) void))

;;;

(soundio_version_string)
(define soundio (soundio_create))
(soundio_connect soundio)
(soundio_flush_events soundio)
(define out-idx (soundio_default_output_device_index soundio))
(define device (soundio_get_output_device soundio out-idx))
(define stream (soundio_outstream_create device))

(define pi 3.1415926535)
(define two-pi (* 2 pi))
(define pitch 440.0)
(define radians-per-second (* pitch two-pi))
(define seconds-offset 0.0)

(define write-callback
  (let ((code (foreign-callable
               (lambda (stream frame-count-min frame-count-max)
                 (let* ([layout (ftype-&ref SoundIoOutStream (layout) stream)]
                        [channel-count (ftype-ref SoundIoChannelLayout (channel_count) layout)]
                        [sample-rate (ftype-ref SoundIoOutStream (sample_rate) stream)]
                        [seconds-per-frame (/ 1.0 sample-rate)]
                        [areas (make-ftype-pointer
                                *SoundIoChannelArea
                                (foreign-alloc (ftype-sizeof *SoundIoChannelArea)))]
                        [frame-count (make-ftype-pointer int (foreign-alloc (ftype-sizeof int)))])
                   (let batch ([frames-left frame-count-max])
                     (ftype-set! int () frame-count frames-left)
                     (let ([err (soundio_outstream_begin_write
                                 stream
                                 areas
                                 frame-count)])
                       (if (not (= 0 err))
                           (exit))
                       (let* ([fc (ftype-ref int () frame-count)]
                              [areas (ftype-ref *SoundIoChannelArea () areas)])
                         (if (not (= fc 0))
                             (begin
                               (do ([frame 0 (+ frame 1)])
                                   ((= frame fc) 0)
                                 (do ([channel 0 (+ channel 1)])
                                     ((= channel channel-count) 0)
                                   (let* ([ptr (ftype-ref SoundIoChannelArea (ptr) areas channel)]
                                          [step (ftype-ref SoundIoChannelArea (step) areas channel)]
                                          [sample (* 0.2
                                                     (sin (* (+ seconds-offset
                                                                (* frame seconds-per-frame))
                                                             radians-per-second)))])
                                     (ftype-set! float () ptr (* (/ step (ftype-sizeof float))
                                                                 frame)
                                                 ;; (- (random 2.0) 1.0)
                                                 sample
                                                 ))))
                               (set! seconds-offset (+ seconds-offset (* fc seconds-per-frame)))
                               (if (not (= 0 (soundio_outstream_end_write stream)))
                                   (exit))))
                         (if (< 0 (- frames-left fc))
                             (batch (- frames-left fc))))))
                   (foreign-free (ftype-pointer-address frame-count)))
                 )
               ((* SoundIoOutStream) int int)
               void)))
    (lock-object code)
    (make-ftype-pointer WriteCallback (foreign-callable-entry-point code))
    ))

(ftype-set! SoundIoOutStream (write_callback)
            stream
            write-callback)

;; TODO ensure sample type

(soundio_outstream_open stream)
(soundio_outstream_start stream)

(let loop ()
  (soundio_wait_events soundio)
  (loop))

(soundio_outstream_destroy stream)
(soundio_device_unref device)
(soundio_destroy soundio)

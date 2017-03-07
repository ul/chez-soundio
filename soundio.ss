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
     [ptr (* char)]
     [step int])]

  [SoundIoSampleRateRange
   (struct
     [min int]
     [max int])]
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
                                                      void*
                                                      (* int)) ; frame_count
                     ErrorCode))

(define soundio_outstream_end_write
  (foreign-procedure "soundio_outstream_end_write" ((* SoundIoOutStream)) ErrorCode))

(define soundio_outstream_open
  (foreign-procedure "soundio_outstream_open" ((* SoundIoOutStream)) ErrorCode))

(define soundio_outstream_start
  (foreign-procedure "soundio_outstream_start" ((* SoundIoOutStream)) ErrorCode))

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
                 (void)
                 #|
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
                 |#
                 )
               ((* SoundIoOutStream) int int)
               void)))
    (lock-object code)
    (make-ftype-pointer WriteCallback (foreign-callable-entry-point code))
    ))

(ftype-set! SoundIoOutStream (write_callback)
            stream
            write-callback)

(soundio_outstream_open stream)
(soundio_outstream_start stream)

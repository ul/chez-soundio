(define unlock-ftype-pointer
  (lambda (fptr)
    (unlock-object
     (foreign-callable-code-object
      (ftype-pointer-address fptr)))))
;; <ffi>
;; <load-library>
(define init-ffi
  (case (machine-type)
    [(i3nt ti3nt a6nt ta6nt) (load-shared-object "libsoundio.dll")]
    [(i3osx ti3osx a6osx ta6osx) (load-shared-object "libsoundio.dylib")]
    [(i3le ti3le a6le ta6le) (load-shared-object "libsoundio.so")]
    [else (error "soundio"
                 "don't know how libsoundio shared library file is called on this machine-type"
                 (machine-type))]))
;; </load-library>
;; <ftypes>
(define-ftype
  ;; <ftype-enums>
  [SoundIoBackend int]
  [SoundIoChannelId int]
  [SoundIoFormat int]
  [SoundIoDeviceAim int]
  ;; </ftype-enums>
  ;; <ftype-callbacks>
  [OnDeviceChangeCallback (function ((* SoundIo)) void)]
  [OnBackendDisconnectCallback (function ((* SoundIo) int) void)]
  [OnEventsSignalCallback (function ((* SoundIo)) void)]
  [EmitRtprioWarningCallback (function () void)]
  [JackInfoCallback (function ((* char)) void)]
  [JackErrorCallback (function ((* char)) void)]
  [WriteCallback (function ((* SoundIoOutStream) int int) void)]
  [UnderflowCallback (function ((* SoundIoOutStream)) void)]
  [ReadCallback (function ((* SoundIoInStream) int int) void)]
  [OverflowCallback (function ((* SoundIoInStream)) void)]
  [ErrorCallback (function ((* SoundIoOutStream) int) void)]
  ;; </ftype-callbacks>
  ;; <ftype-structs>
  [SoundIo
   (struct
    [userdata void*] ; Optional. Put whatever you want here. Defaults to NULL.
    [on_devices_change (* OnDeviceChangeCallback)] ; Optional callback.
    [on_backend_disconnect (* OnBackendDisconnectCallback)] ; Optional callback.
    [on_events_signal (* OnEventsSignalCallback)] ; Optional callback.
    [current_backend SoundIoBackend] ; Read-only.
    [app_name (* char)] ; Optional: Application name.
    [emit_rtprio_warning (* EmitRtprioWarningCallback)] ; Optional: Real time priority warning.
    [jack_info_callback (* JackInfoCallback)] ; Optional: JACK info callback.
    [jack_error_callback (* JackErrorCallback)] ; Optional: JACK error callback.
    )]
  [SoundIoChannelArea
   (struct
    [ptr (* char)]
    [step int])]
  ;; Useful for defining **SoundIoChannelArea in function ftype as (* *SoundIoChannelArea)
  ;; nested * or its alias doesn't work:
  ;; Exception: invalid (non-base) foreign-procedure argument ftype **SoundIoChannelArea
  [*SoundIoChannelArea (* SoundIoChannelArea)]
  [SoundIoChannelLayout
   (struct
     [name (* char)]
     [channel_count int]
     ;; #define SOUNDIO_MAX_CHANNELS 24
     ;; http://libsound.io/doc-1.1.0/soundio_8h.html#a1bf1282c5d903085916f8ed6af174bdd
     [channels (array 24 SoundIoChannelId)])]
  [SoundIoDevice
   (struct
    [soundio (* SoundIo)]
    [id (* char)]
    [name (* char)]
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
  [SoundIoInStream
   (struct
     [device (* SoundIoDevice)]
     [format SoundIoFormat]
     [sample_rate int]
     [layout SoundIoChannelLayout]
     [software_latency double]
     [userdata void*]
     [read_callback (* ReadCallback)]
     [overflow_callback (* OverflowCallback)]
     [error_callback (* ErrorCallback)]
     [name (* char)]
     [non_terminal_hint boolean]
     [bytes_per_frame int]
     [bytes_per_sample int]
     [layout_error int])]
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
     [name (* char)]
     [non_terminal_hint boolean]
     [bytes_per_frame int]
     [bytes_per_sample int]
     [layout_error int])]
  [SoundIoSampleRateRange
   (struct
    [min int]
    [max int])]
  [SoundIoOsMirroredMemory
   (struct
    [capacity size_t]
    [address (* char)]
    [priv void*])]
  [SoundIoAtomicLong long]
  [SoundIoRingBuffer
   (struct
    [mem SoundIoOsMirroredMemory]
    [write_offset SoundIoAtomicLong]
    [read_offset SoundIoAtomicLong]
    [capacity int])]
  ;; </ftype-structs>
)
;; </ftypes>
(define-syntax (define-foreign-procedure stx)
  (syntax-case stx ()
    [(_ [name args result])
     #`(define name
         (foreign-procedure
          #,(symbol->string (syntax->datum #'name))
          args
          result))]
    [(_ e ...)
     #'(begin
         (define-foreign-procedure e)
         ...)]))
(define-foreign-procedure
  [soundio_backend_count ((* SoundIo)) int]
  [soundio_backend_name (SoundIoBackend) int]
  [soundio_best_matching_channel_layout
   ((* SoundIoChannelLayout) ; preferred_layouts
    int                      ; preferred_layout_count
    (* SoundIoChannelLayout) ; available_layouts
    int                      ; available_layout_count
    )
   (* SoundIoChannelLayout)]
  [soundio_channel_layout_builtin_count () int]
  [soundio_channel_layout_detect_builtin ((* SoundIoChannelLayout)) boolean]
  [soundio_channel_layout_equal ((* SoundIoChannelLayout) (* SoundIoChannelLayout)) boolean]
  [soundio_channel_layout_find_channel ((* SoundIoChannelLayout) SoundIoChannelId) int]
  [soundio_channel_layout_get_builtin (int) (* SoundIoChannelLayout)]
  [soundio_channel_layout_get_default (#|channel_count|# int) (* SoundIoChannelLayout)]
  [soundio_connect ((* SoundIo)) int]
  [soundio_connect_backend ((* SoundIo) (* SoundIoBackend)) int]
  [soundio_create () (* SoundIo)]
  [soundio_default_input_device_index ((* SoundIo)) int]
  [soundio_default_output_device_index ((* SoundIo)) int]
  [soundio_destroy ((* SoundIo)) void]
  [soundio_device_equal ((* SoundIoDevice) (* SoundIoDevice)) boolean]
  [soundio_device_nearest_sample_rate ((* SoundIoDevice) int) int]
  [soundio_device_ref ((* SoundIoDevice)) void]
  [soundio_device_sort_channel_layouts ((* SoundIoDevice)) void]
  [soundio_device_supports_format ((* SoundIoDevice) SoundIoFormat) boolean]
  [soundio_device_supports_layout ((* SoundIoDevice) (* SoundIoChannelLayout)) boolean]
  [soundio_device_supports_sample_rate ((* SoundIoDevice) int) boolean]
  [soundio_device_unref ((* SoundIoDevice)) void]
  [soundio_disconnect ((* SoundIo)) void]
  [soundio_flush_events ((* SoundIo)) void]
  [soundio_force_device_scan ((* SoundIo)) void]
  [soundio_format_string (SoundIoFormat) string]
  [soundio_get_backend ((* SoundIo) int) SoundIoBackend]
  ;; [soundio_get_bytes_per_frame (SoundIoFormat #|channel_count|# int) int]
  ;; [soundio_get_bytes_per_sample (SoundIoFormat) int]
  ;; [soundio_get_bytes_per_second (SoundIoFormat #|channel_count|# int #|sample_rate|# int) int]
  [soundio_get_channel_name (SoundIoChannelId) string]
  [soundio_get_input_device ((* SoundIo) int) (* SoundIoDevice)]
  [soundio_get_output_device ((* SoundIo) int) (* SoundIoDevice)]
  [soundio_have_backend (SoundIoBackend) boolean]
  [soundio_input_device_count ((* SoundIo)) int]
  [soundio_instream_begin_read ((* SoundIoInStream) (* *SoundIoChannelArea) (* int)) int]
  [soundio_instream_create ((* SoundIoDevice)) (* SoundIoInStream)]
  [soundio_instream_destroy ((* SoundIoInStream)) void]
  [soundio_instream_end_read ((* SoundIoInStream)) int]
  [soundio_instream_get_latency ((* SoundIoInStream) (* double)) int]
  [soundio_instream_open ((* SoundIoInStream)) int]
  [soundio_instream_pause ((* SoundIoInStream) boolean) int]
  [soundio_instream_start ((* SoundIoInStream)) int]
  [soundio_output_device_count ((* SoundIo)) int]
  [soundio_outstream_begin_write ((* SoundIoOutStream) (* *SoundIoChannelArea) (* int)) int]
  [soundio_outstream_clear_buffer ((* SoundIoOutStream)) int]
  [soundio_outstream_create ((* SoundIoDevice)) (* SoundIoOutStream)]
  [soundio_outstream_destroy ((* SoundIoOutStream)) void]
  [soundio_outstream_end_write ((* SoundIoOutStream)) int]
  [soundio_outstream_get_latency ((* SoundIoOutStream) (* double)) int]
  [soundio_outstream_open ((* SoundIoOutStream)) int]
  [soundio_outstream_pause ((* SoundIoOutStream) boolean) int]
  [soundio_outstream_start ((* SoundIoOutStream)) int]
  [soundio_parse_channel_id ((* char) int) SoundIoChannelId]
  [soundio_ring_buffer_advance_read_ptr ((* SoundIoRingBuffer) int) void]
  [soundio_ring_buffer_advance_write_ptr ((* SoundIoRingBuffer) int) void]
  [soundio_ring_buffer_capacity ((* SoundIoRingBuffer)) int]
  [soundio_ring_buffer_clear ((* SoundIoRingBuffer)) void]
  [soundio_ring_buffer_create ((* SoundIo) int) (* SoundIoRingBuffer)]
  [soundio_ring_buffer_destroy ((* SoundIoRingBuffer)) void]
  [soundio_ring_buffer_fill_count ((* SoundIoRingBuffer)) int]
  [soundio_ring_buffer_free_count ((* SoundIoRingBuffer)) int]
  [soundio_ring_buffer_read_ptr ((* SoundIoRingBuffer)) (* char)]
  [soundio_ring_buffer_write_ptr ((* SoundIoRingBuffer)) (* char)]
  [soundio_sort_channel_layouts ((* SoundIoChannelLayout) int) void]
  [soundio_strerror (int) string]
  [soundio_version_major () int]
  [soundio_version_minor () int]
  [soundio_version_patch () int]
  [soundio_version_string () string]
  [soundio_wait_events ((* SoundIo)) void]
  [soundio_wakeup ((* SoundIo)) void])
;; </ffi>

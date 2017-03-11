
(soundio_version_string)
(define soundio (soundio_create))
(soundio_connect soundio)
(soundio_flush_events soundio)
(define out-idx (soundio_default_output_device_index soundio))
(define device (soundio_get_output_device soundio out-idx))
(define stream (soundio_outstream_create device))

(define pi 3.1415926535)
(define two-pi (* 2 pi))
(define timestamp 0)
(define *sample* 0.0)

(define sine
  (lambda (time freq)
    (sin (* two-pi freq time))))

(define square
  (lambda (time freq)
    (let ([ft (* two-pi freq time)])
      (+ (- (* 2 (floor ft))
            (floor (* 2 ft)))
         1))))

(define underflow-callback
  (let ([code (foreign-callable
               (lambda (stream)
                 (display "underflow!\n"))
               ((* SoundIoOutStream))
               void)])
    (lock-object code)
    (make-ftype-pointer UnderflowCallback (foreign-callable-entry-point code))))

(define write-callback
  (let ((code (foreign-callable
               (lambda (stream frame-count-min frame-count-max)
                 (let* ([layout (ftype-&ref SoundIoOutStream (layout) stream)]
                        [channel-count (ftype-ref SoundIoChannelLayout (channel_count) layout)]
                        [sample-rate (ftype-ref SoundIoOutStream (sample_rate) stream)]
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
                       (if (not (zero? err))
                           (exit))
                       (let* ([fc (ftype-ref int () frame-count)]
                              [areas (ftype-ref *SoundIoChannelArea () areas)])
                         (if (not (zero? fc))
                             (begin
                               (do ([frame 0 (+ frame 1)])
                                   ((= frame fc) 0)
                                 (let* ([t (inexact (/ (+ timestamp frame) sample-rate))]
                                        [k 300])
                                   (set! *sample* 0.0)
                                   (do ([i 1 (+ i 1)])
                                       ((= i k) 0)
                                     (set! *sample* (+ *sample*
                                                       ;; (- (random 2.0) 1.0)
                                                       (sine t (+ 440.0 i))
                                                       ;; (square t (+ 440.0 i))
                                                       )))
                                   (set! *sample* (/ *sample* k))
                                   (do ([channel 0 (+ channel 1)])
                                       ((= channel channel-count) 0)
                                     (let* ([ptr (ftype-ref SoundIoChannelArea (ptr) areas channel)]
                                            [step (ftype-ref SoundIoChannelArea (step) areas channel)])
                                       (ftype-set! float () ptr (* (/ step (ftype-sizeof float))
                                                                   frame)
                                                   *sample*)))))
                               (set! timestamp (+ timestamp fc))
                               (if (not (zero? (soundio_outstream_end_write stream)))
                                   (exit))))
                         (if (< 0 (- frames-left fc))
                             (batch (- frames-left fc))))))
                   (foreign-free (ftype-pointer-address frame-count))
                   (unlock-ftype-pointer areas)
                   (unlock-ftype-pointer frame-count)
                   (if (< 480000 timestamp)
                       (begin ;(profile-dump-html)
                              (exit))))
                 )
               ((* SoundIoOutStream) int int)
               void)))
    (lock-object code)
    (make-ftype-pointer WriteCallback (foreign-callable-entry-point code))
    ))

;; TODO ensure sample type

(soundio_outstream_open stream)

(printf "latency: ~f\n" (ftype-ref SoundIoOutStream (software_latency) stream))

(soundio_outstream_start stream)


(let loop ()
  (soundio_wait_events soundio)
  (loop))

(soundio_outstream_destroy stream)
(soundio_device_unref device)
(soundio_destroy soundio)

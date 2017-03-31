(load "soundio.ss")

(fork-thread
 (lambda ()
   (let* ([pi 3.1415926535]
          [two-pi (* 2 pi)]
          [sine (lambda (time freq)
                  (sin (* two-pi freq time)))]
          [square (lambda (time freq)
                    (let ([ft (* two-pi freq time)])
                      (+ (- (* 2 (floor ft))
                            (floor (* 2 ft)))
                         1)))]
          [write-callback (lambda (time channel)
                            (let ([k 120]
                                  [sample 0.0])
                              (do ([i 0 (+ i 1)]
                                   [sample 0.0 (+ sample (sine time (+ 440.0 i)))])
                                  ((= i k) (/ sample k)))))]
          [sio (open-default-out-stream write-callback)])
     (start-out-stream sio))))

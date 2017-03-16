(load "soundio.ss")

(define pi 3.1415926535)
(define two-pi (* 2 pi))

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
  (lambda ()
    (display "undeflow!\n")))

(define write-callback
  (lambda (time channel)
    (let ([k 100]
          [sample 0.0])
      (do ([i 1 (+ i 1)])
          ((= i k) 0)
        (set! sample (+ sample
                        ;; (- (random 2.0) 1.0)
                        (sine time (+ 440.0 i))
                        ;; (square time (+ 440.0 i))
                        )))
      (/ sample k))))

(define sio (open-default-out-stream write-callback underflow-callback))
(start-out-stream sio)

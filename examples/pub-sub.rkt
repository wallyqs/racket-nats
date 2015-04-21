#lang racket

(require "../nats.rkt")

(define worker-response "{\"result\":~a}~n")
(define nats-io (nats-connect #:host "127.0.0.1" #:port 4222))

;; Uses the with-nats-io helper to process the protocol
(printf "Subscribing to 'workers.double ~n")

(nats-sub "workers.double"
          (lambda (msg)
            (define result (* 2 (string->number (bytes->string/utf-8 msg))))
            (nats-pub "workers.results" (format worker-response result) nats-io)) nats-io)

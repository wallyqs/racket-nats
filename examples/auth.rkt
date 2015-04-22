#lang racket

(require "../nats.rkt")

(define io 
  (nats-connect #:host "127.0.0.1" 
                #:port 4222
                #:user "foobar"
                #:password "hogehoge"))

(with-nats-io io
  #:raw (lambda (payload)
          (nats-pub "echo" payload io)
          (printf "From the wire: ~a ~n" payload)))

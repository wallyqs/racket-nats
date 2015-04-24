#lang racket

(require "../nats.rkt")

(define io (nats-connect))

(with-nats-io io
  #:raw (lambda (payload)
          (printf "From the wire: ~s ~n" payload)))

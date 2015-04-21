;; 
;;     (The MIT License)
;; 
;;  Copyright (c) 2015 Waldemar Quevedo. All rights reserved.
;; 
;; Permission is hereby granted, free of charge, to any person
;;  obtaining a copy of this software and associated documentation
;;  files (the "Software"), to deal in the Software without
;;  restriction, including without limitation the rights to use, copy,
;;  modify, merge, publish, distribute, sublicense, and/or sell copies
;;  of the Software, and to permit persons to whom the Software is
;;  furnished to do so, subject to the following conditions:
;; 
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.
;; 
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
;; BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
;; ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
;; CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.
;;
#lang racket

(require json)

;; Protocol
(define CONNECT "CONNECT {\"verbose\":false,\"pedantic\":false}\r\n")
(define PING    "PING \r\n")              ;; Received periodically by the server
(define PONG    "PONG \r\n")              ;;
(define SUB     "SUB ~a ~a\r\n")          ;; SUB some.interest ssid
(define UNSUB   "UNSUB ~a ~a\r\n")        ;; UNSUB ssid max
(define PUB     "PUB ~a ~a ~a\r\n~a\r\n") ;; PUB some.interest optional-inbox message-bytes\r\n
                                          ;; content\r\n

;; Track number of subscriptions
(define ssid 1)


(define (send-command cmd nats-out)
  (fprintf nats-out cmd)
  (flush-output nats-out))


(define (process-nats-protocol io callback)
  (let* ([nats-in  (car io)]
         [nats-out (cdr io)]
         [payload  (read-line nats-in)]
         [maybe-op (read (open-input-string payload))])

    (match maybe-op
      ['INFO   (process-info payload)]
      ['PING   (send-command PONG nats-out)]
      ['PONG   (send-command PING nats-out)]
      ['MSG    (process-msg   payload callback nats-in)]
      ['-ERR   'skip]
      ['+OK    'skip]
      [_       'skip])))


(define (process-info payload)
  (let* ([info-pair  (string-split payload " ")]
         [info-op    (car info-pair)]
         [info-msg   (car (cdr info-pair))]
         [server-info (string->jsexpr info-msg)])

    (printf "Server Version: ~a ~nServer Id: ~a~n"
            (hash-ref server-info 'version)
            (hash-ref server-info 'server_id))))

(define (process-msg payload sub-callback nats-in)
  (let* ([lst (string-split payload " ")]
         [op       (string-trim (list-ref lst 0))] ;; removing whitespace
         [subject  (string-trim (list-ref lst 1))] ;; so that equality checks
         [csid     (string-trim (list-ref lst 2))] ;; and so that
         [msgbytes (string-trim (list-ref lst 3))] ;; msgbytes is casted to number correctly
         ;; Get the next line right away
         [content  (read-bytes (string->number msgbytes) nats-in)])

    ;; e.g. (nats-sub "hello.world" (lambda (msg) ... ))
    (sub-callback (list subject csid content))))

(define (nats-connect
         #:host [host "127.0.0.1"]
         #:port [port 4222])

  (define-values (nats-in nats-out) (tcp-connect host port))
  (send-command CONNECT nats-out)

  (printf "Connected to NATS server at ~a:~a~n" host port)
  (cons nats-in nats-out))


(define (with-nats-io nats-io callback)
  (define main-cust (make-custodian))
  (parameterize ([current-custodian main-cust])
    (define (loop)
      (process-nats-protocol nats-io callback)
      (loop))
    (thread-wait (thread loop))
    (lambda ()
      (printf "Shutting down...")
      (custodian-shutdown-all main-cust))))


(define (nats-sub subject callback io)
  (define nats-in  (car io))
  (define nats-out (cdr io))
  (set! ssid (+ 1 ssid)) ;; start with ssid:2

  ;; send the subcription message
  (send-command (format SUB subject (number->string ssid)) nats-out)

  (with-nats-io io
    (lambda (msg) ;; a list
      (let* ([received-subject (list-ref msg 0)]
             [csid    (list-ref msg 1)]
             [content (list-ref msg 2)])

        (if (equal? received-subject subject)
            (callback content)
            'skip)))))


(define (nats-pub subject content io)
  (define nats-in  (car io))
  (define nats-out (cdr io))
  (send-command
   (format PUB subject " " (string-length content) content) nats-out))


(provide nats-sub)
(provide nats-pub)
(provide nats-connect)
(provide with-nats-io)

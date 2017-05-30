#|
 This file is a part of harmony
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.harmony.core)

(defclass drain (cl-mixed:drain)
  ((decoder :initform (lambda (samples drain)) :accessor decoder)
   (server :initarg :server :initform NIL :accessor server)
   (channel-function :initform NIL :accessor channel-function)
   (remix-factor :initform 0 :accessor remix-factor)))

(defmethod initialize-instance ((drain drain) &rest args &key server)
  (unless server
    (error "The SERVER initarg is required, but not given."))
  (apply #'call-next-method
         drain
         :channel NIL
         :samplerate (samplerate server)
         args)
  (setf (slot-value drain 'cl-mixed:channel) (initialize-channel drain)))

(defmethod initialize-instance :after ((drain drain) &key)
  (setf (remix-factor drain) (coerce (/ (samplerate (server drain))
                                         (cl-mixed:samplerate (cl-mixed:channel drain)))
                                      'single-float))
  (setf (channel-function drain) (cl-mixed-cffi:direct-segment-mix (cl-mixed:handle drain)))
  (setf (cl-mixed-cffi:direct-segment-mix (cl-mixed:handle drain)) (cffi:callback drain-mix)))

(cffi:defcallback drain-mix :void ((samples cl-mixed-cffi:size_t) (segment :pointer))
  (let* ((drain (cl-mixed:pointer->object segment))
         (real-samples (floor samples (remix-factor drain))))
    ;; Process the channel to get the samples from the buffers
    (cffi:foreign-funcall-pointer
     (channel-function drain) ()
     cl-mixed-cffi:size_t samples
     :pointer segment
     :void)
    ;; Decode samples from the drain
    (funcall (decoder drain) real-samples drain)))
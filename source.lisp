#|
 This file is a part of harmony
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.harmony)

(defclass source (fadable)
  ((looping-p :initarg :loop :initform NIL :accessor looping-p)
   (paused-p :initarg :paused :initform NIL :accessor paused-p)
   (ended-p :initform NIL :accessor ended-p)
   (sample-position :initform 0 :accessor sample-position)))

(defgeneric process (source samples))

(defmethod print-object ((source source) stream)
  (print-unreadable-object (source stream :type T)
    (format stream "~:[~; looping~]~:[~; paused~]~:[~; ended~]~:[~; playing~]"
            (looping-p source) (paused-p source) (ended-p source)
            (and (not (paused-p source)) (not (ended-p source))))))

(defmethod initialize-instance :after ((source source) &key volume)
  (setf (cl-mixed-cffi:direct-segment-mix (handle source)) (cffi:callback source-mix)))

(defmethod shared-initialize :after ((source source) slots &key volume)
  (when volume (setf (volume source) volume)))

(defmethod reinitialize-instance :after ((source source) &key (paused NIL p-p))
  (seek source 0)
  (setf (ended-p source) NIL)
  (unless p-p
    (setf (paused-p source) NIL)))

(defmethod (setf paused-p) :before (value (source source))
  (when value
    (unless (paused-p source)
      (with-body-in-server-thread ((server source))
        (map NIL #'clear (outputs source))))))

(defmethod pause ((source source))
  (setf (paused-p source) T)
  source)

(defmethod resume ((source source))
  (when (ended-p source)
    (seek source 0))
  (setf (paused-p source) NIL)
  source)

(defmethod stop ((source source))
  (setf (ended-p source) T)
  source)

(defmethod seek ((source source) position &key (mode :absolute) (by :sample))
  (ecase by
    (:second
     (setf position (round (* position (samplerate (packed-audio source))))))
    (:sample))
  (ecase mode
    (:relative
     (setf mode :absolute)
     (incf position (sample-position source)))
    (:absolute))
  (seek-to-sample source position)
  (setf (ended-p source) NIL)
  (setf (sample-position source) position)
  source)

(defgeneric seek-to-sample (source position))

(cffi:defcallback source-mix :void ((samples cl-mixed-cffi:size_t) (segment :pointer))
  (let ((source (pointer->object segment)))
    (when (and source (not (paused-p source)))
      ;; We need to handle ended-p like this in order to make
      ;; sure that the last samples that were processed before
      ;; ended-p was set still get out before we clear the
      ;; buffers (by setting paused-p to T).
      (cond ((ended-p source)
             (setf (paused-p source) T))
            (T
             (process source samples)
             ;; Count current stream position
             (perform-fading source samples)
             (incf (sample-position source) samples))))))

(defgeneric play (server source-ish mixer &key paused loop fade volume name &allow-other-keys))

(defmethod play (server (class symbol) mixer &rest initargs)
  (apply #'play server (find-class class) mixer initargs))

(defmethod play ((server server) source-ish (mixer symbol) &rest initargs)
  (apply #'play server source-ish (segment mixer server) initargs))

(defmethod play ((server server) (class class) (mixer mixer) &rest initargs)
  (add (apply #'make-instance class :server server initargs)
       mixer))

(defmethod play ((server server) (source source) (mixer mixer) &rest initargs)
  (add (apply #'reinitialize-instance source :server server initargs)
       mixer))

(defclass unpack-source (source)
  ((remix-factor :initform 0 :accessor remix-factor)
   (packed-audio :initform NIL :accessor packed-audio)
   (unpack-mix-function :initform NIL :accessor unpack-mix-function)))

(defgeneric initialize-packed-audio (source))

(defmethod initialize-instance ((source unpack-source) &key)
  (call-next-method)
  (setf (packed-audio source) (initialize-packed-audio source))
  (setf (remix-factor source) (coerce (/ (samplerate (packed-audio source))
                                         (samplerate (server source)))
                                      'single-float))
  (cl-mixed::with-error-on-failure ()
    (cl-mixed-cffi:make-segment-unpacker (handle (packed-audio source)) (samplerate (server source)) (handle source)))
  (setf (unpack-mix-function source) (cl-mixed-cffi:direct-segment-mix (handle source))))

(defmethod process :around ((source unpack-source) samples)
  (let ((endpoint-samples (floor (* samples (remix-factor source)))))
    ;; Decode
    (call-next-method source endpoint-samples)
    ;; Unpack
    (cffi:foreign-funcall-pointer
     (unpack-mix-function source) ()
     cl-mixed-cffi:size_t samples
     :pointer (handle source))))

;; Convenience
(defun fill-for-unpack-source (source samples direct-read arg)
  (declare (type unpack-source source)
           (type fixnum samples)
           (type function direct-read))
  (let* ((pack (cl-mixed:packed-audio source))
         (buffer (cl-mixed:data pack))
         (bytes (* samples
                   (cl-mixed:samplesize (cl-mixed:encoding pack))
                   (cl-mixed:channels pack)))
         (read (funcall direct-read arg buffer bytes)))
    (when (< read bytes)
      (cond ((looping-p source)
             (loop while (< read bytes)
                   do (seek-to-sample source 0)
                      (let ((new-read (funcall direct-read arg buffer (- bytes read))))
                        (incf read new-read)
                        (setf (sample-position source) new-read))))
            (T
             (memclear (cffi:inc-pointer buffer read) (- bytes read))
             (setf (ended-p source) T))))))

(cl-mixed::define-field-accessor volume unpack-source :float :volume)
(cl-mixed::define-field-accessor bypass unpack-source :bool :bypass)

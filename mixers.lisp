#|
 This file is a part of harmony
 (c) 2017 Shirakumo http://tymoon.eu (shinmera@tymoon.eu)
 Author: Nicolas Hafner <shinmera@tymoon.eu>
|#

(in-package #:org.shirakumo.fraf.harmony)

(defclass mixer (segment cl-mixed:mixer)
  ((buffers :initform NIL :accessor buffers)))

(defgeneric channels-per-source (mixer))

(defmethod initialize-instance :after ((segment mixer) &key)
  (let ((buffers (make-array (channels-per-source segment))))
    (dotimes (i (length buffers))
      (setf (aref buffers i) (cl-mixed:make-buffer (buffersize (context segment)))))
    (setf (buffers segment) buffers)))

(defmethod add :before ((segment cl-mixed:segment) (mixer mixer))
  (let ((buffers (buffers mixer)))
    (dotimes (i (length buffers))
      (setf (cl-mixed:output-field :buffer i segment) (aref buffers i)))))

(defmethod add :around ((segment cl-mixed:segment) (mixer mixer))
  (with-body-in-mixing-context ((context mixer)
                               ;; Apparently synchronising is unbearably slow.
                               #-(and sbcl windows) :synchronize #-(and sbcl windows) T)
    (call-next-method))
  segment)

(defmethod withdraw :around ((segment cl-mixed:segment) (mixer mixer))
  (with-body-in-mixing-context ((context mixer) :synchronize T)
    (call-next-method))
  segment)

(defmethod sources ((mixer mixer))
  (loop for v being the hash-values of (cl-mixed:sources mixer)
        collect v))

(defclass basic-mixer (cl-mixed:basic-mixer mixer)
  ()
  (:default-initargs
   :channels 2))

(defmethod channels-per-source ((segment basic-mixer))
  (channels segment))

(defclass space-mixer (cl-mixed:space-mixer mixer)
  ())

(defmethod channels-per-source ((segment space-mixer))
  1)

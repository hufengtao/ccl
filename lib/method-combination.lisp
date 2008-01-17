; -*- Mode:Lisp; Package:CCL; -*-
;;;
;;;   Copyright (C) 1994-2001 Digitool, Inc
;;;   This file is part of OpenMCL.  
;;;
;;;   OpenMCL is licensed under the terms of the Lisp Lesser GNU Public
;;;   License , known as the LLGPL and distributed with OpenMCL as the
;;;   file "LICENSE".  The LLGPL consists of a preamble and the LGPL,
;;;   which is distributed with OpenMCL as the file "LGPL".  Where these
;;;   conflict, the preamble takes precedence.  
;;;
;;;   OpenMCL is referenced in the preamble as the "LIBRARY."
;;;
;;;   The LLGPL is also available online at
;;;   http://opensource.franz.com/preamble.html


;;;;;;;;;;;;;;;
;;
;; define-method-combination.lisp
;; Copyright 1990-1994, Apple Computer, Inc.
;; Copyright 1995-1996 Digitool, Inc.

;;

;;;;;;;;;;;;;;;
;
; Change History
;
; 05/31/96 bill list method combination is not :identity-with-one-argument
; ------------- MCL-PPC 3.9
; 12/01/93 bill specifier-match-p uses EQUAL instead of EQ
; ------------- 3.0d13
; 04/30/93 bill no-applicable-primary-method -> make-no-applicable-method-function
; ------------  2.0
; 11/05/91 gb   experiment with INLINE.
; 09/26/91 bill %badarg had the wrong number of args in with-call-method-context.
;               Mix in Flavors Technology's optimization.
; 07/21/91 gb   Use DYNAMIC-EXTENT vice DOWNWARD-FUNCTION.
; 06/26/91 bill method-combination's direct-superclass is metaobject
;-------------- 2.0b2
; 02/13/91 bill New File.
;------------ 2.0b1
;

; MOP functions pertaining to method-combination:
;
; COMPUTE-DISCRIMINATING-FUNCTION generic-function (not implemented)
; COMPUTE-EFFECTIVE-METHOD generic-function method-combination methods
; FIND-METHOD-COMBINATION generic-function method-combination-type method-combination-options
; Readers for method-combination objects
; METHOD-COMBINATION-NAME
; METHOD-COMBINATION-OPTIONS
; METHOD-COMBINATION-ORDER
; METHOD-COMBINATION-OPERATOR
; METHOD-COMBINATION-IDENTITY-WITH-ONE-ARGUMENT

(in-package "CCL")

(defclass method-combination (metaobject)
  ((name :reader method-combination-name :initarg :name)
   (options :reader method-combination-options :initarg :options :initform nil)))

(defclass short-method-combination (method-combination) 
  ((operator :reader method-combination-operator :initarg :operator :initform nil)
   (identity-with-one-argument :reader method-combination-identity-with-one-argument
                               :initarg :identity-with-one-argument
                               :initform nil))
  (:documentation "Generated by the simple form of define-method-combination"))

(defclass long-method-combination (method-combination)
  ((expander :reader method-combination-expander :initarg :expander
             :documentation "The expander is called by compute-effective-method with args: gf mc options methods args")
   )
  (:documentation "Generated by the long form of define-method-combination"))

(defmethod print-object ((object method-combination) stream)
  (print-unreadable-object (object stream :type t)
    (let* ((name (method-combination-name object))
           (options (method-combination-options object)))
      (declare (dynamic-extent options))
      (prin1 name stream)
      (dolist (option options)
        (pp-space stream)
        (prin1 option stream)))))

; Hash a method-combination name to a method-combination-info vector
(defvar *method-combination-info* (make-hash-table :test 'eq))

(defmacro method-combination-info (method-combination-type)
  `(gethash ,method-combination-type *method-combination-info*))

; Need to special case (find-method-combination #'find-method-combination ...)
(defmethod find-method-combination ((generic-function standard-generic-function)
                                    method-combination-type
                                    method-combination-options)
  (%find-method-combination
   generic-function method-combination-type method-combination-options))

(defun %find-method-combination (gf type options)
  (declare (ignore gf))
  (if (eq type 'standard)
    (progn
      (unless (null options)
        (error "STANDARD method-combination accepts no options."))
      *standard-method-combination*)
    (let ((mci (method-combination-info type)))
      (unless mci
        (error "~s is not a method-combination type" type))
      (labels ((same-options-p (o1 o2)
                 (cond ((null o1) (null o2))
                       ((null o2) nil)
                       ((or (atom o1) (atom o2)) nil)
                       ((eq (car o1) (car o2)) 
                        (same-options-p (cdr o1) (cdr o2)))
                       (t nil))))
        (dolist (mc (population-data (mci.instances mci)))
          (when (same-options-p options (method-combination-options mc))
            (return-from %find-method-combination mc))))
      (let ((new-mc 
             (case (mci.class mci)
               (short-method-combination
                (unless (or (null options)
                            (and (listp options)
                                 (null (cdr options))
                                 (memq (car options)
                                       '(:most-specific-first :most-specific-last))))
                  (error "Illegal method-combination options: ~s" options))
                (destructuring-bind (&key identity-with-one-argument
                                          (operator type)
                                          &allow-other-keys)
                                    (mci.options mci)
                  (make-instance 'short-method-combination
                                 :name type
                                 :identity-with-one-argument identity-with-one-argument
                                 :operator operator
                                 :options options)))
               (long-method-combination
                (make-instance 'long-method-combination
                               :name type
                               :options options
                               :expander (mci.options mci)))
               (t (error "Don't understand ~s method-combination" type)))))
        (push new-mc (population-data (mci.instances mci)))
        new-mc))))
    
; Push GF on the MCI.GFS population of its method-combination type.
(defun register-gf-method-combination (gf &optional (mc (%gf-method-combination gf)))
  (unless (eq mc *standard-method-combination*)
    (let* ((name (method-combination-name mc))
           (mci (or (method-combination-info name)
                    (error "~s not a known method-combination type" name)))
           (gfs (mci.gfs mci)))
      (pushnew gf (population-data gfs)))
    mc))

(defun unregister-gf-method-combination (gf &optional (mc (%gf-method-combination gf)))
  (unless (eq mc *standard-method-combination*)
    (let* ((name (method-combination-name mc))
           (mci (or (method-combination-info name)
                    (error "~s not a known method-combination type" name)))
           (gfs (mci.gfs mci)))
      (setf (population-data gfs) (delq gf (population-data gfs))))
    mc))


; Need to special case (compute-effective-method #'compute-effective-method ...)
(defmethod compute-effective-method ((generic-function standard-generic-function)
                                     (method-combination standard-method-combination)
                                     methods)
  (%compute-standard-effective-method generic-function method-combination methods))

(defun %compute-standard-effective-method (generic-function method-combination methods)
  (declare (ignore method-combination))
  (make-standard-combined-method methods nil generic-function t))

(defvar *method-combination-evaluators* (make-hash-table :test 'eq))

(defmacro get-method-combination-evaluator (key)
  `(gethash ,key *method-combination-evaluators*))

(defmacro define-method-combination-evaluator (name arglist &body body)
  (setq name (require-type name 'symbol))
  (unless (and arglist (listp arglist) (eq (length arglist) 2))
    (error "A method-combination-evaluator must take two args."))
  `(%define-method-combination-evaluator ',name #'(lambda ,arglist ,@body)))

(defun %define-method-combination-evaluator (operator function)
  (setq operator (require-type operator 'symbol))
  (setq function (require-type function 'function))
  (record-source-file operator 'method-combination-evaluator)
  (setf (get-method-combination-evaluator operator) function)
  (maphash #'(lambda (name mci)
               (when (eq operator (or (getf (mci.options mci) :operator) name))
                 (clear-method-combination-caches name mci)))
           *method-combination-info*)
  function)

(defmethod compute-effective-method ((generic-function standard-generic-function)
                                     (method-combination short-method-combination)
                                     methods)
  (or (get-combined-method methods generic-function)
      (put-combined-method
       methods
       (let* ((arounds nil)
              (primaries nil)
              (iwoa (method-combination-identity-with-one-argument method-combination))
              (reverse-p (eq (car (method-combination-options method-combination))
                             :most-specific-last))
              (operator (method-combination-operator method-combination))
              (name (method-combination-name method-combination))
              qualifiers
              q)
         (dolist (m methods)
           (setq qualifiers (method-qualifiers m))
           (unless (and qualifiers (null (cdr qualifiers))
                        (cond ((eq (setq q (car qualifiers)) name)
                               (push m primaries))
                              ((eq q :around)
                               (push m arounds))
                              (t nil)))
             (%invalid-method-error m "invalid method qualifiers: ~s" qualifiers)))
         (when (null primaries)
           (return-from compute-effective-method
             (make-no-applicable-method-function generic-function)))
         (setq arounds (nreverse arounds))
         (unless reverse-p (setq primaries (nreverse primaries)))
         (or (optimized-short-effective-method generic-function operator iwoa arounds primaries)
             (let ((code (if (and iwoa (null (cdr primaries)))
                           `(call-method ,(car primaries) nil)
                           `(,operator ,@(mapcar #'(lambda (m) `(call-method ,m nil)) primaries)))))
               (make-effective-method
                (if arounds
                  `(call-method ,(car arounds)
                                (,@(cdr arounds) (make-method ,code)))
                  code)))))
       generic-function)))

(defun optimized-short-effective-method (gf operator iwoa arounds primaries)
  (let* ((functionp (functionp (fboundp operator)))
         (evaluator (unless functionp (get-method-combination-evaluator operator))))
    (when (or functionp evaluator)
      (let ((code (if (and iwoa (null (cdr primaries)))
                    (let ((method (car primaries)))
                      (if (call-next-method-p method)
                        #'(lambda (&rest args)
                            (declare (dynamic-extent args))
                            (%%call-method* method nil args))
                        (method-function method)))
                    (if functionp
                      (let ((length (length primaries))
                            (primaries primaries))
                        #'(lambda (&rest args)
                            (declare (dynamic-extent args))
                            (let* ((results (make-list length))
                                   (results-tail results))
                              (declare (cons results-tail))
                              (declare (dynamic-extent results))
                              (dolist (method primaries)
                                (setf (car results-tail)
                                      (%%call-method* method nil args))
                                (pop results-tail))
                              (apply operator results))))
                      (let ((primaries primaries))
                        #'(lambda (&rest args)
                            (declare (dynamic-extent args))
                            (funcall evaluator primaries args)))))))
        (if arounds
          (let* ((code-method (make-instance 'standard-method
                                             :function code
                                             :generic-function gf
                                             :name (function-name gf)))
                 (first-around (car arounds))
                 (rest-arounds (nconc (cdr arounds) (list code-method))))
            #'(lambda (&rest args)
                (declare (dynamic-extent args))
                (%%call-method* first-around rest-arounds args)))
          code)))))

(defmethod compute-effective-method ((generic-function standard-generic-function)
                                     (method-combination long-method-combination)
                                     methods)
  (or (get-combined-method methods generic-function)
      (destructuring-bind (args-var . expander) 
                          (method-combination-expander method-combination)
        (let* ((user-form (funcall expander
                                   generic-function
                                   methods
                                   (method-combination-options method-combination)))
               (effective-method
                (if (functionp user-form)
                  user-form 
                  (make-effective-method user-form args-var))))
          (put-combined-method methods effective-method generic-function)))))

(defmacro with-call-method-context (args-var &body body)
  (labels ((bad-call-method-method (method)
             (error "~s is neither a method nor a ~s form." method 'make-method))
           (call-method-aux (method next-methods args-var)
             (unless (typep method 'standard-method)
               (if (and (listp method) (eq (car method) 'make-method))
                 (setq method (%make-method method))
                 (bad-call-method-method method)))
             (let ((real-next-methods nil))
               (dolist (m next-methods)
                 (cond ((typep m 'standard-method)
                        (push m real-next-methods))
                       ((and (listp m) (eq (car m) 'make-method))
                        (push (%make-method m) real-next-methods))
                       (t (bad-call-method-method m))))
               `(%%call-method* ,method
                                ',(nreverse real-next-methods)
                                ,args-var))))
    `(macrolet ((call-method (method &optional next-methods)
                  (funcall ',#'call-method-aux method next-methods ',args-var)))
       ,@body)))

(defun %make-method (make-method-form &optional
                                      args-var
                                      generic-function
                                      (method-class 'standard-method))
  (setq args-var (require-type args-var 'symbol))
  (unless (and (cdr make-method-form) (null (cddr make-method-form)))
    (%method-combination-error "MAKE-METHOD requires exactly one argument."))
  (let ((form (cadr make-method-form)))
    (make-instance 
     method-class
     :generic-function generic-function
     :name (and (functionp generic-function) (function-name generic-function))
     :function (%make-function
                nil
                `(lambda (&rest ,(setq args-var (or args-var (make-symbol "ARGS"))))
                   (declare (ignore-if-unused ,args-var)
                            (dynamic-extent ,args-var))
                   (with-call-method-context ,args-var
                     ,form))
                nil))))

(defmethod call-next-method-p ((method standard-method))
  (call-next-method-p (%method-function method)))

(defmethod call-next-method-p ((function function))
  (let (lfbits)
    (and (logbitp $lfbits-method-bit
                  (setq lfbits (lfun-bits function)))
         (logbitp $lfbits-nextmeth-bit lfbits))))

(defun make-effective-method (form &optional (args-sym (make-symbol "ARGS")))
  (setq args-sym (require-type args-sym 'symbol))
  (let (m mf)
    (if (and (listp form)
             (eq (car form) 'call-method)
             (listp (cdr form))
             (typep (setq m (cadr form)) 'standard-method)
             (listp (cddr form))
             (null (cdddr form))
             (not (call-next-method-p (setq mf (%method-function m)))))
      mf
      (%make-function
       nil
       `(lambda (&rest ,args-sym)
          (declare (dynamic-extent ,args-sym))
          (with-call-method-context ,args-sym
            ,form))
       nil))))

;;;;;;;
;;
;; Expansions of the DEFINE-METHOD-COMBINATION macro
;;

;;
;; Short form
;;
(defun short-form-define-method-combination (name options)
  (destructuring-bind (&key documentation identity-with-one-argument
                            (operator name)) options
    (setq name (require-type name 'symbol)
          operator (require-type operator 'symbol)
          documentation (unless (null documentation)
                          (require-type documentation 'string)))
    (let* ((mci (method-combination-info name))
           (was-short? (and mci (eq (mci.class mci) 'short-method-combination))))
      (when (and mci (not was-short?))
        (check-long-to-short-method-combination name mci))
      (if mci
        (let ((old-options (mci.options mci)))
          (setf (mci.class mci) 'short-method-combination
                (mci.options mci) options)
          (unless (and was-short?
                       (destructuring-bind (&key ((:identity-with-one-argument id))
                                                 ((:operator op) name)
                                                 &allow-other-keys)
                                           old-options
                         (and (eq id identity-with-one-argument)
                              (eq op operator))))
            (update-redefined-short-method-combinations name mci)))
        (setf (method-combination-info name)
              (setq mci (%cons-mci 'short-method-combination options)))))
    (set-documentation name 'method-combination documentation))
  (record-source-file name 'method-combination)
  name)

(defun check-long-to-short-method-combination (name mci)
  (dolist (gf (population-data (mci.gfs mci)))
    (let ((options (method-combination-options (%gf-method-combination gf))))
      (unless (or (null options)
                  (and (listp options)
                       (null (cdr options))
                       (memq (car options) '(:most-specific-first :most-specific-last))))
        (error "Redefining ~s method-combination disagrees with the~
                method-combination arguments to ~s" name gf)))))

(defun update-redefined-short-method-combinations (name mci)
  (destructuring-bind (&key identity-with-one-argument (operator name)  documentation)
                      (mci.options mci)
    (declare (ignore documentation))
    (dolist (mc (population-data (mci.instances mci)))
      (when (typep mc 'long-method-combination)
        (change-class mc 'short-method-combination))
      (if (typep mc 'short-method-combination)
         (setf (slot-value mc 'identity-with-one-argument) identity-with-one-argument
               (slot-value mc 'operator) operator)
         (error "Bad method-combination-type: ~s" mc))))
  (clear-method-combination-caches name mci))

(defun clear-method-combination-caches (name mci)
  (dolist (gf (population-data (mci.gfs mci)))
    (clear-gf-cache gf))
  (when *effective-method-gfs*          ; startup glitch
    (let ((temp #'(lambda (mc gf)
                    (when (eq name (method-combination-name (%gf-method-combination gf)))
                      (remhash mc *effective-method-gfs*)
                      (remhash mc *combined-methods*)))))
      (declare (dynamic-extent temp))
      (maphash temp *effective-method-gfs*))))

;;
;; Long form
;;
(defun long-form-define-method-combination (name lambda-list method-group-specifiers
                                                 forms env)
  (let (arguments args-specified? generic-fn-symbol gf-symbol-specified?)
    (unless (verify-lambda-list lambda-list)
      (error "~s is not a proper lambda-list" lambda-list))
    (loop
      (unless (and forms (consp (car forms))) (return))
      (case (caar forms)
        (:arguments
         (when args-specified? (error ":ARGUMENTS specified twice"))
         (setq arguments (cdr (pop forms))
               args-specified? t)
         (do ((args arguments (cdr args)))
             ((null args))
           (setf (car args) (require-type (car args) 'symbol))))
        (:generic-function
         (when gf-symbol-specified? (error ":GENERIC-FUNCTION specified twice"))
         (setq generic-fn-symbol
               (require-type (cadr (pop forms)) '(and symbol (not null)))
               gf-symbol-specified? t))
        (t (return))))
    (multiple-value-bind (body decls doc) (parse-body forms env)
      (unless generic-fn-symbol (setq generic-fn-symbol (make-symbol "GF")))
      (multiple-value-bind (specs order-forms required-flags descriptions)
                           (parse-method-group-specifiers method-group-specifiers)
        (let* ((methods-sym (make-symbol "METHODS"))
               (args-sym (make-symbol "ARGS"))
               (options-sym (make-symbol "OPTIONS"))
               (code `(lambda (,generic-fn-symbol ,methods-sym ,options-sym)
                        ,@(unless gf-symbol-specified?
                            `((declare (ignore-if-unused ,generic-fn-symbol))))
                        (let* (,@(let* ((n -1)
                                        (temp #'(lambda (sym) 
                                                  `(,sym '(nth ,(incf n) ,args-sym)))))
                                   (declare (dynamic-extent temp))
                                   (mapcar temp arguments)))
                          ,@decls
                          (destructuring-bind ,lambda-list ,options-sym
                            (destructuring-bind
                              ,(mapcar #'car method-group-specifiers)
                              (seperate-method-groups
                               ,methods-sym ',specs
                               (list ,@order-forms)
                               ',required-flags
                               ',descriptions)
                              ,@body))))))
          `(%long-form-define-method-combination
            ',name (cons ',args-sym #',code) ',doc))))))

(defun %long-form-define-method-combination (name args-var.expander documentation)
  (setq name (require-type name 'symbol))
  (let* ((mci (method-combination-info name)))
    (if mci
      (progn
        (setf (mci.class mci) 'long-method-combination
              (mci.options mci) args-var.expander)
        (update-redefined-long-method-combinations name mci))
      (setf (method-combination-info name)
            (setq mci (%cons-mci 'long-method-combination args-var.expander)))))
  (set-documentation name 'method-combination documentation)
  (record-source-file name 'method-combination)
  name)

(defun update-redefined-long-method-combinations (name mci)
  (let ((args-var.expander (mci.options mci)))
    (dolist (mc (population-data (mci.instances mci)))
      (when (typep mc 'short-method-combination)
        (change-class mc 'long-method-combination))
      (if (typep mc 'long-method-combination)
        (setf (slot-value mc 'expander) args-var.expander)
        (error "Bad method-combination-type: ~s" mc))))
  (clear-method-combination-caches name mci))

; Returns four values:
; method-group specifiers with :order, :required, & :description parsed out
; Values for the :order args
; Values for the :required args
; values for the :description args
(defun parse-method-group-specifiers (mgs)
  (let (specs orders requireds descriptions)
    (dolist (mg mgs)
      (push nil specs)
      (push :most-specific-first orders)
      (push nil requireds)
      (push nil descriptions)
      (push (pop mg) (car specs))       ; name
      (loop
        (when (null mg) (return))
        (when (memq (car mg) '(:order :required :description))
          (destructuring-bind (&key (order :most-specific-first) required description)
                              mg
            (setf (car orders) order)
            (setf (car requireds) required)
            (setf (car descriptions) description))
          (return))
        (push (pop mg) (car specs)))
      (setf (car specs) (nreverse (car specs))))
    (values (nreverse specs)
            (nreverse orders)
            (nreverse requireds)
            (nreverse descriptions))))

(defun seperate-method-groups (methods specs orders requireds descriptions)
  (declare (ignore descriptions))
  (let ((res (make-list (length specs))))
    (dolist (m methods)
      (let ((res-tail res))
        (dolist (s specs (%invalid-method-error
                          m "Does not match any of the method group specifiers"))
          (when (specifier-match-p (method-qualifiers m) s)
            (push m (car res-tail))
            (return))
          (pop res-tail))))
    (do ((res-tail res (cdr res-tail))
         (o-tail orders (cdr o-tail))
         (r-tail requireds (cdr r-tail)))
        ((null res-tail))
      (case (car o-tail)
        (:most-specific-last)
        (:most-specific-first (setf (car res-tail) (nreverse (car res-tail))))
        (t (error "~s is neither ~s nor ~s" :most-specific-first :most-specific-last)))
      (when (car r-tail)
        (unless (car res-tail)
          ; should use DESCRIPTIONS here
          (error "A required method-group matched no method group specifiers"))))
    res))

(defun specifier-match-p (qualifiers spec)
  (flet ((match (qs s)
           (cond ((or (listp s) (eq s '*))
                  (do ((qs-tail qs (cdr qs-tail))
                       (s-tail s (cdr s-tail)))
                      ((or (null qs-tail) (atom s-tail))
                       (or (eq s-tail '*)
                           (and (null qs-tail) (null s-tail))))
                    (unless (or (eq (car s-tail) '*)
                                (equal (car qs-tail) (car s-tail)))
                      (return nil))))
                 ((atom s) (funcall s qs))
                 (t (error "Malformed method group specifier: ~s" spec)))))
    (declare (inline match))
    (dolist (s (cdr spec))
      (when (match qualifiers s)
        (return t)))))

;;;;;;;
;
; The user visible error functions
; We don't add any contextual information yet.
; Maybe we never will.
(setf (symbol-function 'method-combination-error) #'%method-combination-error)
(setf (symbol-function 'invalid-method-error) #'%invalid-method-error)

;;;;;;;
;
; The predefined method-combination types
;
(define-method-combination + :identity-with-one-argument t)
(define-method-combination and :identity-with-one-argument t)
(define-method-combination append :identity-with-one-argument t)
(define-method-combination list :identity-with-one-argument nil)
(define-method-combination max :identity-with-one-argument t)
(define-method-combination min :identity-with-one-argument t)
(define-method-combination nconc :identity-with-one-argument t)
(define-method-combination or :identity-with-one-argument t)
(define-method-combination progn :identity-with-one-argument t)

; And evaluators for the non-functions
(define-method-combination-evaluator and (methods args)
  (when methods
    (loop
      (if (null (cdr methods))
        (return (%%call-method* (car methods) nil args)))
      (unless (%%call-method* (pop methods) nil args)
        (return nil)))))

(define-method-combination-evaluator or (methods args)
  (when methods
    (loop
      (if (null (cdr methods))
        (return (%%call-method* (car methods) nil args)))
      (let ((res (%%call-method* (pop methods) nil args)))
        (when res (return res))))))

(define-method-combination-evaluator progn (methods args)
  (when methods
    (loop
      (if (null (cdr methods))
        (return (%%call-method* (car methods) nil args)))
      (%%call-method* (pop methods) nil args))))

#|

;(define-method-combination and :identity-with-one-argument t)
(defgeneric func (x) (:method-combination and))
(defmethod func and ((x window)) (print 3))
(defmethod func and ((x fred-window)) (print 2))
(func (front-window))

(define-method-combination example ()((methods positive-integer-qualifier-p))
  `(progn ,@(mapcar #'(lambda (method)
                        `(call-method ,method ()))
                    (sort methods #'< :key #'(lambda (method)
                                               (first (method-qualifiers method)))))))

(defun positive-integer-qualifier-p (method-qualifiers)
  (and (= (length method-qualifiers) 1)
       (typep (first method-qualifiers)'(integer 0 *))))

(defgeneric zork  (x)(:method-combination example))

(defmethod zork 1 ((x window)) (print 1))
(defmethod zork 2 ((x fred-window)) (print 2))
(zork (front-window))


|#


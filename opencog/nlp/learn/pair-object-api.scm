;
; pair-object-api.scm
;
; Define object-oriented class API's for pairs of things.
;
; Copyright (c) 2017 Linas Vepstas
;
; ---------------------------------------------------------------------
; OVERVIEW
; --------
; In this project, there's a generic theme of "pairs of things" that
; are statistically related. The can be pairs of words, they can be
; connector-sets, which are a pair of (word, disjunct), or they can
; be other things.
;
; For all of these pairs (x,y), we typically need to get the count
; N(x,y), the partial sums N(x,*) = sum_y N(x,y), and likewise N(*,y)
; and N(*,*).   We need to compute frequencies of observations, such
; as p(x,y) = N(x,y)/N(*,*).  We also need to compute entropies and
; mutual information, which can be infered from these frequencies.
; We also can compute cosine-similairy and other matrics of similarity,
; dervied solely from the observed frequency counts.
;
; All of these formulas are independent of the actual objects in the
; pairs.  Thus, it is useful to separae the various algorithms from
; the data that they operate on. Towards this end, this file defines
; some object-oriented OO API's for pairs, which the algos can assume,
; and the different types of pairs can implement.
;
; The object-system being used here is a roll-your-own type system,
; really quite simple, as it's well-suited for the desired task.
; It's simple, and minimal. The reasons for this are explained here:
;    http://community.schemewiki.org/?object-oriented-programming
; Basically, "object-oriented programming" is a mish-mash of more
; than half-a-dozen distinct concepts, almost all of which are
; not needed for this particular project.  The only thing we need
; is the ability to decorate objects with additional methods, kind-of
; like class inheritance, except that we really really need dynamic
; inheritance, i.e. arbitrary base classes, rather than a single,
; static base class, and so its totally unlike C++ inheritance, which
; is static, and a lot like C++ templates, which are dynamic.
; Basically, what is needed, and what is implemented here is called
; "parametric polymorphism".
;
; From what I can tell, tiny-CLOS and thus GOOPS does not support
; parametric polymorphism... !?? and so I go it alone. The system here
; is really really simple...
;
; The object system here is almost identical to this one:
;    http://community.schemewiki.org/?simple-object
; Read this URL to understand what is happening here.
;
; There are several API's here. The lowest-level ones are listed first.
;
; XXX FIXME ... the calling seuqence is exactly backeards. In order
; for overloading to work correct, attempts must be made to call
; methods on the base object first, and only later on the wrapper.
; For now, we blow this off, but in the long run, this needs to be
; fixed.
;
; ---------------------------------------------------------------------
;
; Example low-level API class. It has only six methods; these
; return pair-atoms on which counts are stored as values.
; Higher-evel objects use this object to fetch counts, store them
; into the database, or to return various statistics.
;
; The `make-pair-count-get-set` class, below, is a typical user
; of this class; it provides getters and setters for teh counts.
;
; See `make-any-link` for a working example.
;
; When called, this will create a new instance of the class
; i.e. will create a new object.
;
;  (define (make-ll-object-api-example)
;     (let ()
;        ; Return the atom-type of the left and right items.
;        ; For example both may be words, or maybe the right
;        ; side is a disjunct 'LgAnd
;        (define (get-left-type) 'WordNode)
;        (define (get-right-type) 'WordNode)
;        (define (get-pair-type) 'ListLink)
;
;        ; Return the observed count for PAIR, if it exists,
;        ; else return zero.
;        (define (get-pair-count PAIR) 42)
;
;        ; Return the atom holding the count, if it exists,
;        ; else return nil.
;        (define (get-pair PAIR) "foobar")
;
;        ; Return the atom holding the count, creating it if
;        ; it does not yet exist.
;        (define (make-pair PAIR) "foobar")
;
;        ; Return the atom holding the N(*,y) count
;        (define (get-left-wildcard ITEM) "foobar")
;
;        ; Return the atom holding the N(x,*) count
;        (define (get-right-wildcard ITEM) "foobar")
;
;        ; Return the atom holding the N(*,*) count
;        (define (get-wild-wild) "foobar")
;
;     ; Methods on the class. To call these, quote the method name.
;     ; Example: (OBJ 'left-wildcard WORD) calls the
;     ; get-left-wildcard method, passing WORD as the argument.
;     (lambda (message . args)
;        (apply (case message
;              ((left-type) get-left-type)
;              ((right-type) get-right-type)
;              ((pair-type) get-pair-type)
;              ((pair-count) get-pair-count)
;              ((item-pair) get-pair)
;              ((make-pair) make-pair)
;              ((left-wildcard) get-left-wildcard)
;              ((right-wildcard) get-right-wildcard)
;              ((wild-wild) get-wild-wild)
;              (else (error "Bad method call on low-level API")))
;           args))))
;
;
; ---------------------------------------------------------------------

(use-modules (srfi srfi-1))

(define-public (add-pair-wildcards LLOBJ)
"
  pair-wildcards LLOBJ - Extend LLOBJ with wildcard methods.

  Extend the LLOBJ with addtional methods to get wild-card lists,
  that is, lists of all pairs with a specific item on the left,
  or on the right.  This generates these lists in a generic way,
  that probably work for most kinds of pairs. However, you can
  overload them with custom getters, if you wish.

  Here, the LLOBJ is expected to be an object, with methods for
  'left-type and 'right-type on it, just as described above.

  The lists of pairs will be lists of type 'pair-type (usually
  ListLink's), with the desired item on the left or right, and
  an atom of 'left-type or 'right-type on the other side.
"
	(let ((llobj LLOBJ)
			(l-supp '())
			(r-supp '())
		)

		; Return a list of all of the atoms that might ever appear on
		; the left-hand-side of a pair.  This is the set of items x
		; for which 0 < N(x,y) for some item y, and N(x,y) the count
		; of ever having observed the pair (x,y).
		;
		; Actually, we cheat, for performance reasons. Instead of
		; computing the set desribed above, we just *assume* that
		; every atom of 'left-type is a part of the support. We may
		; regret this cheat, someday, but for now it works. It's
		; certainly faster than computing the correct thing.
		;
		; Actually, if someone needs something better, they can
		; overload this method.
		(define (get-left-support)
			(if (null? l-supp)
				(set! l-supp (cog-get-atoms (llobj 'left-type))))
			l-supp)

		(define (get-right-support)
			(if (null? r-supp)
				(set! r-supp (cog-get-atoms (llobj 'right-type))))
			r-supp)

		(define (get-left-support-size) (length (get-left-support)))
		(define (get-right-support-size) (length (get-right-support)))

		; Return a list of all pairs with the ITEM on the right side,
		; and an object of type (LLOBJ 'left-type) on the left. The
		; pairs are just ListLink's (of arity two). That is, it returns
		; a list of atoms of the form
		;
		;    ListLink
		;         (LLOBJ 'left-type)
		;         ITEM
		;
		(define (get-left-stars ITEM)
			(define want-type (LLOBJ 'left-type))
			(define pair-type (LLOBJ 'pair-type))
			(filter
				(lambda (lnk)
					(define oset (cog-outgoing-set lnk))
					(and
						(equal? 2 (cog-arity lnk))
						(equal? want-type (cog-type (first oset)))
						(equal? ITEM (second oset))
					))
				(cog-incoming-by-type ITEM pair-type)))

		; Same as above, but on the right.
		(define (get-right-stars ITEM)
			(define want-type (LLOBJ 'right-type))
			(define pair-type (LLOBJ 'pair-type))
			(filter
				(lambda (lnk)
					(define oset (cog-outgoing-set lnk))
					(and
						(equal? 2 (cog-arity lnk))
						(equal? ITEM (first oset))
						(equal? want-type (cog-type (second oset)))
					))
				(cog-incoming-by-type ITEM pair-type)))


	; Methods on this class.
	(lambda (message . args)
		(case message
			((left-support)       (get-left-support))
			((right-support)      (get-right-support))
			((left-support-size)  (get-left-support-size))
			((right-support-size) (get-right-support-size))
			((left-stars)         (apply get-left-stars args))
			((right-stars)        (apply get-right-stars args))
			(else (apply llobj (cons message args))))
		)))

; ---------------------------------------------------------------------

(define-public (add-pair-count-api LLOBJ)
"
  add-pair-count-api LLOBJ - Extend LLOBJ with count-getters.

  Extend the LLOBJ with additional methods to get and set
  the count values for wild-card counts, and total counts.
  Basically, this decorates the class with additional methods
  that get and set these counts in \"standardized\" places.
  Other classes can overload these methods; these just provide
  a reasonable default.

  These methods do NOT compute the counts! They merely provide a
  way to access these, as cached values, and they provide a way
  to set the cached value. Thus, this class is meant to provide
  support for some computational class, which does compute these
  counts.

  Here, the LLOBJ is expected to be an object, with methods for
  'item-pair 'make-pair 'left-wildcard 'right-wildcard and 'wild-wild
  on it, in the form documented above for the \"low-level API class\".
"
	(let ((llobj LLOBJ))

		(define (get-count ATOM)
			(cog-tv-count (cog-tv ATOM)))

		(define (set-count ATOM CNT)
			(cog-set-tv! ATOM (cog-new-ctv 0 0 CNT)))

		; Get the left wildcard count
		(define (get-left-wild-count ITEM)
			(get-count (llobj 'left-wildcard ITEM)))

		; Get the right wildcard count
		(define (get-right-wild-count ITEM)
			(get-count (llobj 'right-wildcard ITEM)))

		; Set the left wildcard count
		; Return the atom that holds this count.
		(define (set-left-wild-count ITEM CNT)
			(set-count (llobj 'left-wildcard ITEM) CNT))

		; Set the right wildcard count
		; Return the atom that holds this count.
		(define (set-right-wild-count ITEM CNT)
			(set-count (llobj 'right-wildcard ITEM) CNT))

		; Get the wildcard-wildcard count
		(define (get-wild-wild-count)
			(get-count (llobj 'wild-wild)))

		; Set the wildcard-wildcard count
		; Return the atom that holds this count.
		(define (set-wild-wild-count CNT)
			(set-count (llobj 'wild-wild) CNT))

		; Methods on this class.
		(lambda (message . args)
			(case message
				((left-wild-count)      (apply get-left-wild-count args))
				((set-left-wild-count)  (apply set-left-wild-count args))
				((right-wild-count)     (apply get-right-wild-count args))
				((set-right-wild-count) (apply set-right-wild-count args))
				((wild-wild-count)      (get-wild-wild-count))
				((set-wild-wild-count)  (apply set-wild-wild-count args))
				(else (apply llobj (cons message args))))
		))
)

; ---------------------------------------------------------------------

(define-public (add-pair-freq-api LLOBJ)
"
  add-pair-freq-api LLOBJ - Extend LLOBJ with frequency getters.

  Extend the LLOBJ with additional methods to get and set
  the observation frequencies, entropies and mutual infomation.
  Basically, this decorates the class with additional methods
  that get and set these frequencies and entropies in \"standardized\"
  places. Other classes can overload these methods; these just
  provide a reasonable default.

  Here, the LLOBJ is expected to be an object, with methods for
  'item-pair 'make-pair 'left-wildcard and 'right-wildcard on it,
  in the form documented above for the \"low-level API class\".
"
	(let ((llobj LLOBJ))

		; Key under which the frequency values are stored.
		(define freq-key (PredicateNode "*-FrequencyKey-*"))

		; Return the observed frequency on ATOM
		(define (get-freq ATOM)
			(cog-value-ref (cog-value ATOM freq-key) 0))

		; Return the observed - log_2(frequency) on ATOM
		(define (get-logli ATOM)
			(cog-value-ref (cog-value ATOM freq-key) 1))

		; Return the observed - frequency * log_2(frequency) on ATOM
		(define (get-entropy ATOM)
			(cog-value-ref (cog-value ATOM freq-key) 2))

		; Set both a frequency count, and a -log_2(frequency) on
		; the ATOM.
		(define (set-freq ATOM FREQ)
			; 1.4426950408889634 is 1/0.6931471805599453 is 1/log 2
			(define ln2 (* -1.4426950408889634 (log FREQ)))
			(define ent (* FREQ ln2))
			(cog-set-value! ATOM freq-key (FloatValue FREQ ln2 ent)))

		; ------
		; The key under which the MI is stored.
		(define mi-key (PredicateNode "*-Mutual Info Key-*"))

		; Get the (floating-point) mutual information on ATOM.
		(define (get-mi ATOM)
			(cog-value-ref (cog-value ATOM mi-key) 0))

		; Get the (floating-point) fractional mutual information on ATOM.
		; This is the Yuret "lexical attraction" value.
		(define (get-fmi ATOM)
			(cog-value-ref (cog-value ATOM mi-key) 1))

		; Set the MI value for ATOM.
		(define (set-mi ATOM MI FMI)
			(cog-set-value! ATOM mi-key (FloatValue MI FMI)))

		; ----------------------------------------------------
		; Return the observational frequency on PAIR.
		; If the PAIR does not exist (was not oberved) return 0.
		(define (get-pair-freq PAIR)
			(get-freq (llobj 'item-pair PAIR)))

		(define (get-pair-logli PAIR)
			(get-logli (llobj 'item-pair PAIR)))

		(define (get-pair-entropy PAIR)
			(get-entropy (llobj 'item-pair PAIR)))

		; Set the frequency and log-frequency on PAIR
		; Return the atom that holds this count.
		(define (set-pair-freq PAIR FREQ)
			(set-freq (llobj 'make-pair PAIR) FREQ))

		; ----------------------------------------------------

		; Return the MI value on the pair.
		; The MI is defined as
		; - P(x,y) log_2 P(x,y) / P(x,*) P(*,y)
		(define (get-pair-mi PAIR)
			(get-mi (llobj 'item-pair PAIR)))

		; Return the fractional MI (lexical atraction) on the pair.
		; - log_2 P(x,y) / P(x,*) P(*,y)
		; It differs from the MI above only by the leading probability.
		(define (get-pair-fmi PAIR)
			(get-fmi (llobj 'item-pair PAIR)))

		(define (set-pair-mi PAIR MI FMI)
			(set-mi (llobj 'item-pair PAIR) MI FMI))

		; ----------------------------------------------------
		; Get the left wildcard frequency
		(define (get-left-wild-freq ITEM)
			(get-freq (llobj 'left-wildcard ITEM)))

		(define (get-left-wild-logli ITEM)
			(get-logli (llobj 'left-wildcard ITEM)))

		; Get the right wildcard frequency
		(define (get-right-wild-freq ITEM)
			(get-freq (llobj 'right-wildcard ITEM)))

		(define (get-right-wild-logli ITEM)
			(get-logli (llobj 'right-wildcard ITEM)))

		; Set the left wildcard frequency.
		; Return the atom that holds this value.
		(define (set-left-wild-freq ITEM FREQ)
			(set-freq (llobj 'left-wildcard ITEM) FREQ))

		; Set the right wildcard frequency.
		; Return the atom that holds this value.
		(define (set-right-wild-freq ITEM FREQ)
			(set-freq (llobj 'right-wildcard ITEM) FREQ))

		; ----------------------------------------------------
		; Methods on this class.
		(lambda (message . args)
			(case message
				((pair-freq)           (apply get-pair-freq args))
				((pair-logli)          (apply get-pair-logli args))
				((pair-entropy)        (apply get-pair-entropy args))
				((pair-mi)             (apply get-pair-mi args))
				((pair-fmi)            (apply get-pair-fmi args))
				((set-pair-freq)       (apply set-pair-freq args))
				((set-pair-mi)         (apply set-pair-mi args))

				((left-wild-freq)      (apply get-left-wild-freq args))
				((left-wild-logli)     (apply get-left-wild-logli args))
				((set-left-wild-freq)  (apply set-left-wild-freq args))

				((right-wild-freq)     (apply get-right-wild-freq args))
				((right-wild-logli)    (apply get-right-wild-logli args))
				((set-right-wild-freq) (apply set-right-wild-freq args))

				(else (apply llobj (cons message args))))
		))
)

; ---------------------------------------------------------------------
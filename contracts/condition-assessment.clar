;; Condition Assessment Contract
;; Manages product condition evaluation and refurbishment processes

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-ASSESSMENT-NOT-FOUND (err u301))
(define-constant ERR-INVALID-SCORE (err u302))
(define-constant ERR-REFURBISHMENT-NOT-FOUND (err u303))
(define-constant ERR-INVALID-STATUS (err u304))

;; Condition scores (1-5 scale)
(define-constant CONDITION-POOR u1)
(define-constant CONDITION-FAIR u2)
(define-constant CONDITION-GOOD u3)
(define-constant CONDITION-VERY-GOOD u4)
(define-constant CONDITION-EXCELLENT u5)

;; Refurbishment statuses
(define-constant REFURB-PENDING u1)
(define-constant REFURB-IN-PROGRESS u2)
(define-constant REFURB-COMPLETED u3)
(define-constant REFURB-FAILED u4)
(define-constant REFURB-NOT-VIABLE u5)

;; Assessment categories
(define-constant CATEGORY-COSMETIC u1)
(define-constant CATEGORY-FUNCTIONAL u2)
(define-constant CATEGORY-STRUCTURAL u3)
(define-constant CATEGORY-ELECTRONIC u4)

;; Data structures
(define-map condition-assessments
  { assessment-id: uint }
  {
    product-id: uint,
    return-id: uint,
    assessor: principal,
    assessment-date: uint,
    overall-condition: uint,
    cosmetic-score: uint,
    functional-score: uint,
    structural-score: uint,
    electronic-score: uint,
    notes: (string-ascii 300),
    photos-hash: (optional (string-ascii 64)),
    refurbishment-recommended: bool,
    estimated-refurb-cost: uint,
    estimated-resale-value: uint
  }
)

(define-map detailed-findings
  { assessment-id: uint, finding-id: uint }
  {
    category: uint,
    issue-description: (string-ascii 200),
    severity: uint,
    repair-required: bool,
    estimated-cost: uint,
    parts-needed: (string-ascii 100)
  }
)

(define-map refurbishment-processes
  { refurb-id: uint }
  {
    assessment-id: uint,
    technician: principal,
    start-date: uint,
    target-completion: uint,
    actual-completion: (optional uint),
    status: uint,
    total-cost: uint,
    parts-used: (string-ascii 200),
    quality-check-passed: bool,
    certification-level: uint,
    warranty-period: uint
  }
)

(define-map quality-standards
  { category: uint }
  {
    min-score-threshold: uint,
    critical-checks: (string-ascii 200),
    testing-procedures: (string-ascii 300),
    certification-required: bool
  }
)

;; Data variables
(define-data-var next-assessment-id uint u1)
(define-data-var next-refurb-id uint u1)
(define-data-var contract-owner principal tx-sender)

;; Initialize quality standards
(map-set quality-standards { category: CATEGORY-COSMETIC }
  { min-score-threshold: u3, critical-checks: "Surface damage, scratches, dents",
    testing-procedures: "Visual inspection, photo documentation", certification-required: false })
(map-set quality-standards { category: CATEGORY-FUNCTIONAL }
  { min-score-threshold: u4, critical-checks: "All features operational",
    testing-procedures: "Full functionality test, performance benchmarks", certification-required: true })
(map-set quality-standards { category: CATEGORY-STRUCTURAL }
  { min-score-threshold: u4, critical-checks: "Structural integrity, safety",
    testing-procedures: "Stress testing, safety compliance check", certification-required: true })
(map-set quality-standards { category: CATEGORY-ELECTRONIC }
  { min-score-threshold: u4, critical-checks: "Electrical safety, performance",
    testing-procedures: "Electrical testing, calibration verification", certification-required: true })

;; Authorization check
(define-private (is-authorized (caller principal))
  (is-eq caller (var-get contract-owner))
)

;; Public functions

;; Create condition assessment
(define-public (create-assessment
  (product-id uint)
  (return-id uint)
  (cosmetic-score uint)
  (functional-score uint)
  (structural-score uint)
  (electronic-score uint)
  (notes (string-ascii 300))
  (photos-hash (optional (string-ascii 64)))
)
  (let ((assessment-id (var-get next-assessment-id)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= cosmetic-score u1) (<= cosmetic-score u5)) ERR-INVALID-SCORE)
    (asserts! (and (>= functional-score u1) (<= functional-score u5)) ERR-INVALID-SCORE)
    (asserts! (and (>= structural-score u1) (<= structural-score u5)) ERR-INVALID-SCORE)
    (asserts! (and (>= electronic-score u1) (<= electronic-score u5)) ERR-INVALID-SCORE)

    (let ((overall-condition (calculate-overall-condition cosmetic-score functional-score structural-score electronic-score))
          (refurb-recommended (< overall-condition u4))
          (estimated-cost (calculate-refurb-cost overall-condition))
          (resale-value (calculate-resale-value overall-condition)))

      (map-set condition-assessments
        { assessment-id: assessment-id }
        {
          product-id: product-id,
          return-id: return-id,
          assessor: tx-sender,
          assessment-date: block-height,
          overall-condition: overall-condition,
          cosmetic-score: cosmetic-score,
          functional-score: functional-score,
          structural-score: structural-score,
          electronic-score: electronic-score,
          notes: notes,
          photos-hash: photos-hash,
          refurbishment-recommended: refurb-recommended,
          estimated-refurb-cost: estimated-cost,
          estimated-resale-value: resale-value
        }
      )

      (var-set next-assessment-id (+ assessment-id u1))
      (ok assessment-id)
    )
  )
)

;; Add detailed finding
(define-public (add-finding
  (assessment-id uint)
  (category uint)
  (issue-description (string-ascii 200))
  (severity uint)
  (repair-required bool)
  (estimated-cost uint)
  (parts-needed (string-ascii 100))
)
  (let ((finding-id (get-next-finding-id assessment-id)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? condition-assessments { assessment-id: assessment-id })) ERR-ASSESSMENT-NOT-FOUND)
    (asserts! (and (>= category u1) (<= category u4)) ERR-INVALID-STATUS)
    (asserts! (and (>= severity u1) (<= severity u5)) ERR-INVALID-SCORE)

    (map-set detailed-findings
      { assessment-id: assessment-id, finding-id: finding-id }
      {
        category: category,
        issue-description: issue-description,
        severity: severity,
        repair-required: repair-required,
        estimated-cost: estimated-cost,
        parts-needed: parts-needed
      }
    )

    (ok finding-id)
  )
)

;; Start refurbishment process
(define-public (start-refurbishment
  (assessment-id uint)
  (target-completion uint)
  (estimated-cost uint)
)
  (let ((refurb-id (var-get next-refurb-id)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? condition-assessments { assessment-id: assessment-id })) ERR-ASSESSMENT-NOT-FOUND)

    (map-set refurbishment-processes
      { refurb-id: refurb-id }
      {
        assessment-id: assessment-id,
        technician: tx-sender,
        start-date: block-height,
        target-completion: target-completion,
        actual-completion: none,
        status: REFURB-IN-PROGRESS,
        total-cost: estimated-cost,
        parts-used: "",
        quality-check-passed: false,
        certification-level: u0,
        warranty-period: u0
      }
    )

    (var-set next-refurb-id (+ refurb-id u1))
    (ok refurb-id)
  )
)

;; Complete refurbishment
(define-public (complete-refurbishment
  (refurb-id uint)
  (actual-cost uint)
  (parts-used (string-ascii 200))
  (quality-passed bool)
  (certification-level uint)
  (warranty-period uint)
)
  (let ((refurb-process (unwrap! (map-get? refurbishment-processes { refurb-id: refurb-id }) ERR-REFURBISHMENT-NOT-FOUND)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status refurb-process) REFURB-IN-PROGRESS) ERR-INVALID-STATUS)

    (map-set refurbishment-processes
      { refurb-id: refurb-id }
      (merge refurb-process {
        actual-completion: (some block-height),
        status: (if quality-passed REFURB-COMPLETED REFURB-FAILED),
        total-cost: actual-cost,
        parts-used: parts-used,
        quality-check-passed: quality-passed,
        certification-level: certification-level,
        warranty-period: warranty-period
      })
    )

    (ok true)
  )
)

;; Private functions

;; Calculate overall condition score
(define-private (calculate-overall-condition (cosmetic uint) (functional uint) (structural uint) (electronic uint))
  (/ (+ cosmetic functional structural electronic) u4)
)

;; Calculate estimated refurbishment cost
(define-private (calculate-refurb-cost (condition uint))
  (if (< condition u3)
    u1000
    (if (< condition u4)
      u500
      u200
    )
  )
)

;; Calculate estimated resale value
(define-private (calculate-resale-value (condition uint))
  (* condition u300)
)

;; Get next finding ID for assessment
(define-private (get-next-finding-id (assessment-id uint))
  (+ (fold count-findings (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10) u0) u1)
)

(define-private (count-findings (finding-id uint) (count uint))
  (if (is-some (map-get? detailed-findings { assessment-id: u1, finding-id: finding-id }))
    (+ count u1)
    count
  )
)

;; Read-only functions

;; Get assessment details
(define-read-only (get-assessment (assessment-id uint))
  (map-get? condition-assessments { assessment-id: assessment-id })
)

;; Get detailed finding
(define-read-only (get-finding (assessment-id uint) (finding-id uint))
  (map-get? detailed-findings { assessment-id: assessment-id, finding-id: finding-id })
)

;; Get refurbishment process
(define-read-only (get-refurbishment (refurb-id uint))
  (map-get? refurbishment-processes { refurb-id: refurb-id })
)

;; Get quality standards
(define-read-only (get-quality-standards (category uint))
  (map-get? quality-standards { category: category })
)

;; Check if product meets quality standards
(define-read-only (meets-quality-standards (assessment-id uint))
  (match (map-get? condition-assessments { assessment-id: assessment-id })
    assessment (and
      (>= (get cosmetic-score assessment) u3)
      (>= (get functional-score assessment) u4)
      (>= (get structural-score assessment) u4)
      (>= (get electronic-score assessment) u4)
    )
    false
  )
)

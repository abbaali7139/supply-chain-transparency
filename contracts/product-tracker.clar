;; Product Tracker Smart Contract
;; Comprehensive supply chain transparency system for tracking products
;; from origin to final consumer with authenticity verification

;; Constants
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-STAGE (err u400))
(define-constant ERR-PRODUCT-EXISTS (err u409))
(define-constant ERR-INVALID-INPUT (err u422))
(define-constant ERR-ACCESS-DENIED (err u403))
(define-constant ERR-STAGE-SEQUENCE (err u406))

(define-constant CONTRACT-OWNER tx-sender)

;; Valid supply chain stages in sequence
(define-constant VALID-STAGES 
  (list 
    "sourced" 
    "manufactured" 
    "quality-check" 
    "packaged" 
    "shipped" 
    "distributed" 
    "retail" 
    "sold"
  )
)

;; Data Structures

;; Product registry - main product information
(define-map products
  { product-id: uint }
  {
    name: (string-ascii 100),
    category: (string-ascii 50),
    manufacturer: principal,
    current-stage: (string-ascii 13),
    creation-timestamp: uint,
    is-active: bool,
    total-stages: uint
  }
)

;; Product stage history - tracks complete journey
(define-map stage-history
  { product-id: uint, stage-index: uint }
  {
    stage: (string-ascii 13),
    timestamp: uint,
    handler: principal,
    notes: (string-ascii 200),
    location: (string-ascii 100)
  }
)

;; Product certifications
(define-map certifications
  { product-id: uint, cert-index: uint }
  {
    cert-type: (string-ascii 50),
    issuer: principal,
    timestamp: uint,
    expiry: uint,
    cert-data: (string-ascii 200)
  }
)

;; Authorized handlers for each product
(define-map authorized-handlers
  { product-id: uint, handler: principal }
  { authorized: bool, role: (string-ascii 30) }
)

;; Global counters
(define-data-var next-product-id uint u1)
(define-data-var total-products uint u0)

;; Private Functions

;; Validate stage sequence
(define-private (is-valid-stage-sequence (current-stage (string-ascii 13)) (new-stage (string-ascii 13)))
  (let
    (
      (current-index (index-of VALID-STAGES current-stage))
      (new-index (index-of VALID-STAGES new-stage))
    )
    (match current-index
      curr-idx (match new-index
        new-idx (>= new-idx curr-idx)
        false
      )
      false
    )
  )
)

;; Check if handler is authorized for product
(define-private (is-authorized-handler (product-id uint) (handler principal))
  (default-to false
    (get authorized (map-get? authorized-handlers { product-id: product-id, handler: handler }))
  )
)

;; Get next stage index for product
(define-private (get-next-stage-index (product-id uint))
  (default-to u0
    (get total-stages (map-get? products { product-id: product-id }))
  )
)

;; Get next certification index for product (simplified approach)
(define-private (get-next-cert-index (product-id uint))
  (let
    ((check-0 (if (is-some (map-get? certifications { product-id: product-id, cert-index: u0 })) u1 u0))
     (check-1 (if (is-some (map-get? certifications { product-id: product-id, cert-index: u1 })) u1 u0))
     (check-2 (if (is-some (map-get? certifications { product-id: product-id, cert-index: u2 })) u1 u0))
     (check-3 (if (is-some (map-get? certifications { product-id: product-id, cert-index: u3 })) u1 u0))
     (check-4 (if (is-some (map-get? certifications { product-id: product-id, cert-index: u4 })) u1 u0)))
    (+ check-0 check-1 check-2 check-3 check-4)
  )
)

;; Public Functions

;; Register a new product in the supply chain
(define-public (register-product
    (name (string-ascii 100))
    (category (string-ascii 50))
    (manufacturer principal)
    (initial-notes (string-ascii 200))
    (initial-location (string-ascii 100))
  )
  (let
    (
      (product-id (var-get next-product-id))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len category) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? products { product-id: product-id })) ERR-PRODUCT-EXISTS)
    
    ;; Create product record
    (map-set products
      { product-id: product-id }
      {
        name: name,
        category: category,
        manufacturer: manufacturer,
        current-stage: "sourced",
        creation-timestamp: current-time,
        is-active: true,
        total-stages: u1
      }
    )
    
    ;; Add initial stage
    (map-set stage-history
      { product-id: product-id, stage-index: u0 }
      {
        stage: "sourced",
        timestamp: current-time,
        handler: tx-sender,
        notes: initial-notes,
        location: initial-location
      }
    )
    
    ;; Authorize manufacturer and original registrant
    (map-set authorized-handlers
      { product-id: product-id, handler: tx-sender }
      { authorized: true, role: "registrant" }
    )
    (map-set authorized-handlers
      { product-id: product-id, handler: manufacturer }
      { authorized: true, role: "manufacturer" }
    )
    
    ;; Update counters
    (var-set next-product-id (+ product-id u1))
    (var-set total-products (+ (var-get total-products) u1))
    
    (ok product-id)
  )
)

;; Update product stage in supply chain
(define-public (update-stage
    (product-id uint)
    (new-stage (string-ascii 13))
    (notes (string-ascii 200))
    (location (string-ascii 100))
  )
  (let
    (
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
      (current-stage (get current-stage product))
      (stage-index (get total-stages product))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (get is-active product) ERR-ACCESS-DENIED)
    (asserts! (or (is-authorized-handler product-id tx-sender) (is-eq tx-sender CONTRACT-OWNER)) ERR-UNAUTHORIZED)
    (asserts! (is-valid-stage-sequence current-stage new-stage) ERR-STAGE-SEQUENCE)
    
    ;; Update product current stage
    (map-set products
      { product-id: product-id }
      (merge product {
        current-stage: new-stage,
        total-stages: (+ stage-index u1)
      })
    )
    
    ;; Add stage history
    (map-set stage-history
      { product-id: product-id, stage-index: stage-index }
      {
        stage: new-stage,
        timestamp: current-time,
        handler: tx-sender,
        notes: notes,
        location: location
      }
    )
    
    (ok true)
  )
)

;; Add quality or compliance certification
(define-public (add-certification
    (product-id uint)
    (cert-type (string-ascii 50))
    (cert-data (string-ascii 200))
    (expiry uint)
  )
  (let
    (
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
      (cert-index (get-next-cert-index product-id))
      (current-time (unwrap-panic (get-stacks-block-info? time (- stacks-block-height u1))))
    )
    (asserts! (get is-active product) ERR-ACCESS-DENIED)
    (asserts! (or (is-authorized-handler product-id tx-sender) (is-eq tx-sender CONTRACT-OWNER)) ERR-UNAUTHORIZED)
    (asserts! (> expiry current-time) ERR-INVALID-INPUT)
    
    (map-set certifications
      { product-id: product-id, cert-index: cert-index }
      {
        cert-type: cert-type,
        issuer: tx-sender,
        timestamp: current-time,
        expiry: expiry,
        cert-data: cert-data
      }
    )
    
    (ok cert-index)
  )
)

;; Authorize new handler for product
(define-public (authorize-handler
    (product-id uint)
    (handler principal)
    (role (string-ascii 30))
  )
  (let
    (
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
    )
    (asserts! (or 
      (is-eq tx-sender (get manufacturer product))
      (is-eq tx-sender CONTRACT-OWNER)
      (is-authorized-handler product-id tx-sender)
    ) ERR-UNAUTHORIZED)
    
    (map-set authorized-handlers
      { product-id: product-id, handler: handler }
      { authorized: true, role: role }
    )
    
    (ok true)
  )
)

;; Transfer product custody
(define-public (transfer-custody
    (product-id uint)
    (new-handler principal)
    (role (string-ascii 30))
  )
  (let
    (
      (product (unwrap! (map-get? products { product-id: product-id }) ERR-NOT-FOUND))
    )
    (asserts! (get is-active product) ERR-ACCESS-DENIED)
    (asserts! (or (is-authorized-handler product-id tx-sender) (is-eq tx-sender CONTRACT-OWNER)) ERR-UNAUTHORIZED)
    
    (try! (authorize-handler product-id new-handler role))
    (ok true)
  )
)

;; Read-only Functions

;; Get product information
(define-read-only (get-product (product-id uint))
  (map-get? products { product-id: product-id })
)

;; Get product stage history
(define-read-only (get-stage-history (product-id uint) (stage-index uint))
  (map-get? stage-history { product-id: product-id, stage-index: stage-index })
)

;; Get product certification
(define-read-only (get-certification (product-id uint) (cert-index uint))
  (map-get? certifications { product-id: product-id, cert-index: cert-index })
)

;; Verify product authenticity
(define-read-only (verify-authenticity (product-id uint))
  (let
    (
      (product (map-get? products { product-id: product-id }))
    )
    (match product
      product-data (ok {
        exists: true,
        is-active: (get is-active product-data),
        manufacturer: (get manufacturer product-data),
        current-stage: (get current-stage product-data)
      })
      (ok { exists: false, is-active: false, manufacturer: CONTRACT-OWNER, current-stage: "" })
    )
  )
)

;; Get total products count
(define-read-only (get-total-products)
  (var-get total-products)
)

;; Check if handler is authorized
(define-read-only (check-authorization (product-id uint) (handler principal))
  (map-get? authorized-handlers { product-id: product-id, handler: handler })
)

;; VoltFi - DeFi Lending Protocol 

;; ======= CONSTANTS =======
(define-constant MAX-LTV u70)
(define-constant LIQUIDATION-THRESHOLD u80)
(define-constant MAX-PRICE u1000000000000) ;; Maximum allowed price (1M USD in micro-USD)
(define-constant MAX-AMOUNT u1000000000000) ;; Maximum amount to prevent overflow

;; Access Control Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u403))
(define-constant ERR-CONTRACT-PAUSED (err u409))
(define-constant ERR-INVALID-PRINCIPAL (err u410))

;; ======= DATA STRUCTURES =======

;; Maps
(define-map lp-balances { user: principal } uint)
(define-map positions { user: principal } { collateral: uint, debt: uint })
(define-map price-feed { symbol: (buff 8) } uint) ;; e.g. {symbol: "STX"} => price in micro-USD

;; Access Control Maps
(define-map authorized-oracles principal bool)

;; Variables
(define-data-var total-stx uint u0)
(define-data-var lp-total-supply uint u0)

;; Access Control Variables
(define-data-var contract-paused bool false)
(define-data-var admin principal CONTRACT-OWNER)

;; ======= HELPER FUNCTIONS =======

(define-private (check-not-paused)
  (if (var-get contract-paused)
    ERR-CONTRACT-PAUSED
    (ok true)
  )
)

(define-private (is-authorized-oracle (oracle principal))
  (or 
    (is-eq oracle (var-get admin))
    (default-to false (map-get? authorized-oracles oracle))
  )
)

;; Input validation helper for principals
(define-private (is-valid-principal (principal-to-check principal))
  (and 
    (not (is-eq principal-to-check (as-contract tx-sender)))
    (not (is-eq principal-to-check 'SP000000000000000000002Q6VF78))
  )
)

;; ======= ACCESS CONTROL FUNCTIONS =======

(define-public (set-admin (new-admin principal))
  (if (is-eq tx-sender (var-get admin))
    (if (is-valid-principal new-admin)
      (let ((old-admin-value (var-get admin))) ;; Capture old admin before change
        (var-set admin new-admin)
        (print {
          event: "admin-changed",
          old-admin: old-admin-value,
          new-admin: new-admin,
          block-height: stacks-block-height
        })
        (ok new-admin)
      )
      ERR-INVALID-PRINCIPAL
    )
    ERR-NOT-AUTHORIZED
  )
)

(define-public (add-oracle (oracle principal))
  (if (is-eq tx-sender (var-get admin))
    (if (is-valid-principal oracle)
      (let ((current-admin (var-get admin))) ;; Capture admin value
        (map-set authorized-oracles oracle true)
        (print {
          event: "oracle-added",
          oracle: oracle,
          admin: current-admin,
          block-height: stacks-block-height
        })
        (ok oracle)
      )
      ERR-INVALID-PRINCIPAL
    )
    ERR-NOT-AUTHORIZED
  )
)

(define-public (remove-oracle (oracle principal))
  (if (is-eq tx-sender (var-get admin))
    (if (is-valid-principal oracle)
      (let ((current-admin (var-get admin))) ;; Capture admin value
        (map-delete authorized-oracles oracle)
        (print {
          event: "oracle-removed",
          oracle: oracle,
          admin: current-admin,
          block-height: stacks-block-height
        })
        (ok oracle)
      )
      ERR-INVALID-PRINCIPAL
    )
    ERR-NOT-AUTHORIZED
  )
)

(define-public (pause-contract)
  (if (is-eq tx-sender (var-get admin))
    (let ((current-admin (var-get admin))) ;; Capture admin value
      (var-set contract-paused true)
      (print {
        event: "contract-paused",
        admin: current-admin,
        block-height: stacks-block-height
      })
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)

(define-public (unpause-contract)
  (if (is-eq tx-sender (var-get admin))
    (let ((current-admin (var-get admin))) ;; Capture admin value
      (var-set contract-paused false)
      (print {
        event: "contract-unpaused",
        admin: current-admin,
        block-height: stacks-block-height
      })
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)

;; ======= EVENT LOGGING FUNCTIONS =======

(define-private (log-lp-deposit (user principal) (amount uint) (lp-tokens uint))
  (print {
    event: "lp-deposit",
    user: user,
    stx-amount: amount,
    lp-tokens-minted: lp-tokens,
    total-pool: (var-get total-stx),
    total-lp-supply: (var-get lp-total-supply),
    block-height: stacks-block-height
  })
)

(define-private (log-lp-withdraw (user principal) (lp-amount uint) (stx-amount uint))
  (print {
    event: "lp-withdraw",
    user: user,
    lp-tokens-burned: lp-amount,
    stx-amount: stx-amount,
    total-pool: (var-get total-stx),
    total-lp-supply: (var-get lp-total-supply),
    block-height: stacks-block-height
  })
)

(define-private (log-collateral-deposit (user principal) (amount uint) (total-collateral uint))
  (print {
    event: "collateral-deposit",
    user: user,
    amount: amount,
    total-collateral: total-collateral,
    block-height: stacks-block-height
  })
)

(define-private (log-borrow (user principal) (amount uint) (new-debt uint) (ltv uint))
  (print {
    event: "borrow",
    user: user,
    borrowed-amount: amount,
    total-debt: new-debt,
    ltv: ltv,
    pool-balance: (var-get total-stx),
    block-height: stacks-block-height
  })
)

(define-private (log-repay (user principal) (amount uint) (remaining-debt uint))
  (print {
    event: "repay",
    user: user,
    repaid-amount: amount,
    remaining-debt: remaining-debt,
    pool-balance: (var-get total-stx),
    block-height: stacks-block-height
  })
)

(define-private (log-price-update (symbol (buff 8)) (price uint) (oracle principal))
  (print {
    event: "price-update",
    symbol: symbol,
    price: price,
    oracle: oracle,
    block-height: stacks-block-height
  })
)

;; ======= ORACLE FUNCTIONS =======

(define-public (set-price (symbol (buff 8)) (price uint))
  (let ((valid-symbol (is-eq (len symbol) u3))
        (valid-price (and (> price u0) (<= price MAX-PRICE)))
        (is-authorized (is-authorized-oracle tx-sender)))
    (try! (check-not-paused))
    (if (not is-authorized)
      ERR-NOT-AUTHORIZED
      (if (and valid-symbol valid-price)
        (begin
          (map-set price-feed { symbol: symbol } price)
          (log-price-update symbol price tx-sender)
          (ok price)
        )
        (if (not valid-symbol)
          (err u700) ;; error code for invalid symbol length
          (err u701) ;; error code for invalid price
        )
      )
    )
  )
)

(define-private (get-price (symbol (buff 8)))
  (match (map-get? price-feed { symbol: symbol })
    price (ok price)
    (err u500)
  )
)

(define-private (get-ltv (collateral uint) (debt uint))
  (match (get-price 0x535458) ;; "STX"
    price
      (let ((collateral-value (* collateral price)))
        (if (> collateral-value u0)
          (ok (/ (* debt u100) collateral-value))
          (err u501)
        )
      )
    err (err err)
  )
)

;; ======= LP SECTION =======

(define-public (lp-deposit (amount uint))
  (let (
    (sender tx-sender)
    (total-supply (var-get lp-total-supply))
    (total-pool (var-get total-stx))
  )
    (try! (check-not-paused))
    ;; Input validation
    (if (or (is-eq amount u0) (> amount MAX-AMOUNT))
        (err u610) ;; Invalid amount
        (let (
          (lp-to-mint (if (is-eq total-supply u0)
                          amount
                          (if (is-eq total-pool u0)
                              amount
                              (/ (* amount total-supply) total-pool)
                          )
                      ))
        )
          (try! (stx-transfer? amount sender (as-contract tx-sender)))
          (var-set total-stx (+ total-pool amount))
          (var-set lp-total-supply (+ total-supply lp-to-mint))
          (map-set lp-balances { user: sender }
            (+ (default-to u0 (map-get? lp-balances { user: sender })) lp-to-mint))
          (log-lp-deposit sender amount lp-to-mint)
          (ok lp-to-mint)
        )
    )
  )
)

(define-public (lp-withdraw (lp-amount uint))
  (let (
    (sender tx-sender)
    (user-balance (default-to u0 (map-get? lp-balances { user: sender })))
    (total-supply (var-get lp-total-supply))
    (total-pool (var-get total-stx))
  )
    (try! (check-not-paused))
    ;; Input validation
    (if (or (is-eq lp-amount u0) (> lp-amount MAX-AMOUNT))
      (err u611) ;; Invalid LP amount
      (if (>= user-balance lp-amount)
        (let (
          (withdraw-amount (if (is-eq total-supply u0)
                               u0
                               (/ (* lp-amount total-pool) total-supply)
                           ))
        )
          (try! (as-contract (stx-transfer? withdraw-amount (as-contract tx-sender) sender)))
          (map-set lp-balances { user: sender } (- user-balance lp-amount))
          (var-set lp-total-supply (- total-supply lp-amount))
          (var-set total-stx (- total-pool withdraw-amount))
          (log-lp-withdraw sender lp-amount withdraw-amount)
          (ok withdraw-amount)
        )
        (err u602)
      )
    )
  )
)

;; ======= VAULT SECTION =======

(define-public (deposit-collateral (amount uint))
  (let ((sender tx-sender))
    (try! (check-not-paused))
    ;; Input validation
    (if (or (is-eq amount u0) (> amount MAX-AMOUNT))
      (err u607) ;; Invalid amount
      (begin
        (try! (stx-transfer? amount sender (as-contract tx-sender)))
        (let ((position (default-to { collateral: u0, debt: u0 }
                                    (map-get? positions { user: sender })))
              (new-collateral (+ amount (get collateral position))))
          (map-set positions { user: sender }
                   { collateral: new-collateral,
                     debt: (get debt position) })
          (log-collateral-deposit sender amount new-collateral)
          (ok amount)
        )
      )
    )
  )
)

(define-public (borrow (amount uint))
  (let ((sender tx-sender)
        (position (default-to { collateral: u0, debt: u0 }
                              (map-get? positions { user: sender }))))
    (try! (check-not-paused))
    ;; Input validation
    (if (or (is-eq amount u0) (> amount MAX-AMOUNT))
      (err u612) ;; Invalid borrow amount
      (let (
        (total-collateral (get collateral position))
        (new-debt (+ (get debt position) amount))
        (pool-balance (var-get total-stx))
      )
        (match (get-ltv total-collateral new-debt)
          ltv
            (if (and (<= ltv MAX-LTV) (<= amount pool-balance))
                (begin
                  (try! (as-contract (stx-transfer? amount (as-contract tx-sender) sender)))
                  (map-set positions { user: sender }
                           { collateral: total-collateral, debt: new-debt })
                  (var-set total-stx (- pool-balance amount))
                  (log-borrow sender amount new-debt ltv)
                  (ok amount)
                )
                (err u400)
            )
          err (err err)
        )
      )
    )
  )
)

(define-public (repay-debt (amount uint))
  (let ((sender tx-sender)
        (position (default-to { collateral: u0, debt: u0 }
                              (map-get? positions { user: sender }))))
    (try! (check-not-paused))
    ;; Input validation
    (if (or (is-eq amount u0) (> amount MAX-AMOUNT))
      (err u613) ;; Invalid repay amount
      (let ((current-debt (get debt position)))
        (if (is-eq current-debt u0)
          (err u605)
          (let ((repay-amount (if (<= amount current-debt) amount current-debt))
                (new-debt (if (<= amount current-debt) (- current-debt amount) u0)))
            (try! (stx-transfer? repay-amount sender (as-contract tx-sender)))
            (var-set total-stx (+ (var-get total-stx) repay-amount))
            (map-set positions { user: sender }
                     { collateral: (get collateral position), debt: new-debt })
            (log-repay sender repay-amount new-debt)
            (ok new-debt)
          )
        )
      )
    )
  )
)

;; ======= EMERGENCY ADMIN FUNCTIONS =======

;; Admin function to handle undercollateralized positions manually
(define-public (admin-clear-position (target principal))
  (if (is-eq tx-sender (var-get admin))
    (if (is-valid-principal target)
      (match (map-get? positions { user: target })
        position
          (match (get-ltv (get collateral position) (get debt position))
            ltv
              (if (>= ltv LIQUIDATION-THRESHOLD)
                (let ((current-admin (var-get admin))
                      (position-collateral (get collateral position))
                      (position-debt (get debt position)))
                  (map-delete positions { user: target })
                  (print {
                    event: "admin-position-cleared",
                    admin: current-admin,
                    target: target,
                    collateral: position-collateral,
                    debt: position-debt,
                    ltv: ltv,
                    block-height: stacks-block-height
                  })
                  (ok position-collateral)
                )
                (err u402) ;; Position not liquidatable
              )
            err (err err)
          )
        (err u608) ;; No position found
      )
      ERR-INVALID-PRINCIPAL
    )
    ERR-NOT-AUTHORIZED
  )
)

;; ======= READ-ONLY FUNCTIONS =======

(define-read-only (get-user-lp-balance (user principal))
  (default-to u0 (map-get? lp-balances { user: user }))
)

(define-read-only (get-user-position (user principal))
  (map-get? positions { user: user })
)

(define-read-only (get-pool-stats)
  {
    total-stx: (var-get total-stx),
    total-lp-supply: (var-get lp-total-supply),
    contract-paused: (var-get contract-paused),
    admin: (var-get admin)
  }
)

(define-read-only (get-asset-price (symbol (buff 8)))
  (map-get? price-feed { symbol: symbol })
)

(define-read-only (get-user-health-factor (user principal))
  (match (map-get? positions { user: user })
    position
      (let (
        (collateral (get collateral position))
        (debt (get debt position))
      )
        (if (is-eq debt u0)
          (ok u999999) ;; Very high health factor if no debt
          (match (get-ltv collateral debt)
            ltv (ok (/ u8000 ltv)) ;; Health factor = 80% / current LTV
            err (err err)
          )
        )
      )
    (err u608) ;; No position found
  )
)

(define-read-only (is-position-liquidatable (user principal))
  (match (map-get? positions { user: user })
    position
      (match (get-ltv (get collateral position) (get debt position))
        ltv (>= ltv LIQUIDATION-THRESHOLD)
        err false
      )
    false
  )
)

(define-read-only (get-max-borrowable (user principal))
  (match (map-get? positions { user: user })
    position
      (let ((collateral (get collateral position)))
        (match (get-price 0x535458) ;; "STX"
          price
            (let (
              (collateral-value (* collateral price))
              (max-debt-value (/ (* collateral-value MAX-LTV) u100))
              (current-debt (get debt position))
            )
              (if (> max-debt-value current-debt)
                (ok (/ (- max-debt-value current-debt) price))
                (ok u0)
              )
            )
          err (err err)
        )
      )
    (ok u0)
  )
)

(define-read-only (is-oracle-authorized (oracle principal))
  (is-authorized-oracle oracle)
)

(define-read-only (get-contract-admin)
  (var-get admin)
)

(define-read-only (is-contract-paused)
  (var-get contract-paused)
)

(define-read-only (get-utilization-rate)
  (let (
    (total-pool (var-get total-stx))
  )
    (if (> total-pool u0)
      ;; For now, return 0 utilization rate since we can't easily calculate total borrowed
      ;; This would need to be implemented with additional tracking variables
      u0
      u0
    )
  )
)

;; Helper function to get current block height (for compatibility)
(define-read-only (get-current-block-height)
  stacks-block-height
)

;; ======= RISK MONITORING FUNCTIONS =======

;; Get all positions that should be liquidated (for monitoring)
(define-read-only (get-risky-positions-count)
  ;; This is a simplified version - in practice you'd need to iterate through positions
  ;; For now, returns 0 as a placeholder
  u0
)

;; Check protocol health
(define-read-only (get-protocol-health)
  {
    total-collateral-value: u0, ;; Would need price calculations
    total-debt-value: u0,       ;; Would need to track total debt
    protocol-ltv: u0,           ;; Overall protocol loan-to-value
    at-risk-positions: u0       ;; Number of positions near liquidation
  }
)

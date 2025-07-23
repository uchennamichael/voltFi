(define-constant MAX-LTV u70)
(define-constant LIQUIDATION-THRESHOLD u80)

;; Maps
(define-map lp-balances { user: principal } uint)
(define-map positions { user: principal } { collateral: uint, debt: uint })
(define-map price-feed { symbol: (buff 8) } uint) ;; e.g. {symbol: "STX"} => price in micro-USD

;; Variables
(define-data-var total-stx uint u0)
(define-data-var lp-total-supply uint u0)

;; ======= Oracle Function =======

(define-public (set-price (symbol (buff 8)) (price uint))
  (let ((valid-symbol (if (is-eq (len symbol) u3) true false)))
    (if valid-symbol
      (begin
        (map-set price-feed { symbol: symbol } price)
        (ok price)
      )
      (err u700) ;; error code for invalid symbol length
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
    (lp-to-mint (if (is-eq total-supply u0)
                    amount
                    (if (is-eq total-pool u0)
                        amount
                        (/ (* amount total-supply) total-pool)
                    )
                ))
  )
    (if (is-eq amount u0)
        (ok u0)
        (let (
          (transfer-result (stx-transfer? amount sender (as-contract tx-sender)))
        )
          (if (is-eq transfer-result (ok true))
            (begin
              (var-set total-stx (+ total-pool amount))
              (var-set lp-total-supply (+ total-supply lp-to-mint))
              (map-set lp-balances { user: sender }
                (+ (default-to u0 (map-get? lp-balances { user: sender })) lp-to-mint))
              (ok lp-to-mint)
            )
            (err u600)
          )
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
    (if (>= user-balance lp-amount)
      (let (
        (withdraw-amount (if (is-eq total-supply u0)
                             u0
                             (/ (* lp-amount total-pool) total-supply)
                         ))
        (transfer-result (stx-transfer? withdraw-amount (as-contract tx-sender) sender))
      )
        (if (is-eq transfer-result (ok true))
          (begin
            (map-set lp-balances { user: sender } (- user-balance lp-amount))
            (var-set lp-total-supply (- total-supply lp-amount))
            (var-set total-stx (- total-pool withdraw-amount))
            (ok withdraw-amount)
          )
          (err u601)
        )
      )
      (err u602)
    )
  )
)

;; ======= VAULT SECTION =======

(define-public (deposit-collateral (amount uint))
  (let ((sender tx-sender))
    (if (is-eq amount u0)
      (err u607) ;; error code for zero amount
      (let ((transfer-result (stx-transfer? amount sender (as-contract tx-sender))))
        (if (is-eq transfer-result (ok true))
          (let ((position (default-to { collateral: u0, debt: u0 }
                                      (map-get? positions { user: sender }))))
            (map-set positions { user: sender }
                     { collateral: (+ amount (get collateral position)),
                       debt: (get debt position) })
            (ok amount)
          )
          (err u602)
        )
      )
    )
  )
)
(define-public (borrow (amount uint))
  (let ((sender tx-sender)
        (position (default-to { collateral: u0, debt: u0 }
                              (map-get? positions { user: sender }))))
    (let (
      (total-collateral (get collateral position))
      (new-debt (+ (get debt position) amount))
      (pool-balance (var-get total-stx))
    )
      (match (get-ltv total-collateral new-debt)
        ltv
          (if (and (<= ltv MAX-LTV) (<= amount pool-balance))
              (let (
                (transfer-result (stx-transfer? amount (as-contract tx-sender) sender))
              )
                (if (is-eq transfer-result (ok true))
                  (begin
                    (map-set positions { user: sender }
                             { collateral: total-collateral, debt: new-debt })
                    (var-set total-stx (- pool-balance amount))
                    (ok amount)
                  )
                  (err u603)
                )
              )
              (err u400)
          )
        err (err err)
      )
    )
  )
)

(define-public (repay-debt (amount uint))
  (let ((sender tx-sender)
        (position (default-to { collateral: u0, debt: u0 }
                              (map-get? positions { user: sender }))))
    (let ((current-debt (get debt position)))
      (if (is-eq current-debt u0)
        (err u605)
        (let ((repay-amount (if (<= amount current-debt) amount current-debt))
              (new-debt (if (<= amount current-debt) (- current-debt amount) u0)))
          (let ((transfer-result (stx-transfer? repay-amount sender (as-contract tx-sender))))
            (if (is-eq transfer-result (ok true))
              (begin
                (var-set total-stx (+ (var-get total-stx) repay-amount))
                (map-set positions { user: sender }
                         { collateral: (get collateral position), debt: new-debt })
                (ok new-debt)
              )
              (err u604)
            )
          )
        )
      )
    )
  )
)
(define-public (liquidate (target principal))
  (match (map-get? positions { user: target })
    position
      (let ((ltv-result (get-ltv (get collateral position) (get debt position))))
        (match ltv-result
          ltv
            (if (>= ltv LIQUIDATION-THRESHOLD)
                (let ((collateral-amount (get collateral position)))
                  (map-delete positions { user: target })
                  (if (is-eq (stx-transfer? collateral-amount
                                            (as-contract tx-sender) tx-sender) (ok true))
                      (ok collateral-amount)
                      (err u606)
                  )
                )
                (err u402)
            )
          err (err err)
        )
      )
    (err u608) ;; error code for no position found
  )
)

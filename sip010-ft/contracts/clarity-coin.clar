(impl-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))

;; No maximum supply!
(define-fungible-token clarity-coin)

;; The transfer function should assert that the sender is equal to the tx-sender to prevent principals from transferring 
;; tokens they do not own. It should also unwrap and print the memo if it is not none. We use match to conditionally call 
;; print if the passed memo is a some.
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
        (asserts! (is-eq tx-sender sender) err-not-token-owner)
        (try! (ft-transfer? clarity-coin amount sender recipient))
        (match memo to-print (print to-print) 0x)
        (ok true)
    )
)

;; A static function that returns a human-readable name for our token.
(define-read-only (get-name)
    (ok "Clarity Coin")
)

;; A static function that returns a human-readable symbol for our token.
(define-read-only (get-symbol)
    (ok "CC")
)

;; the value returned by this function is purely for display reasons. 
;; Let us follow along with STX and introduce 6 decimals.
(define-read-only (get-decimals)
    (ok u6)
)

;; This function returns the balance of a specified principal. We simply wrap the built-in function that retrieves the balance.
(define-read-only (get-balance (who principal))
    (ok (ft-get-balance clarity-coin who))
)

;; This function returns the total supply of our custom token. We again simply wrap the built-in function for it.
(define-read-only (get-total-supply)
    (ok (ft-get-supply clarity-coin))
)

;; This function has the same purpose as get-token-uri in SIP009. It should return a link to a metadata file for the token. 
;; Our practice fungible token does not have a website so we can return none.
(define-read-only (get-token-uri)
    (ok none)
)

;; we add a convenience function to mint new tokens that only the contract deployer can successfully call.
(define-public (mint (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ft-mint? clarity-coin amount recipient)
    )
)
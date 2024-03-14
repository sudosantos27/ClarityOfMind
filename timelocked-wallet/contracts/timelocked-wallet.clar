
;; title: timelocked-wallet
;; version:

;; SUMMARY:
;; A user can deploy the time-locked wallet contract.
;; Then, the user specifies a block height at which the wallet unlocks and a beneficiary.
;; Anyone, not just the contract deployer, can send tokens to the contract.
;; The beneficiary can claim the tokens once the specified block height is reached.
;; Additionally, the beneficiary can transfer the right to claim the wallet to a different principal.

;; DESCRIPTION: 
;; the contract will feature the following public functions:
;; lock, takes the principal, unlock height, and an initial deposit amount.
;; claim, transfers the tokens to the tx-sender if and only if the unlock height has been reached and the tx-sender is equal to the beneficiary.
;; bestow, allows the beneficiary to transfer the right to claim the wallet.


;; Owner
(define-constant contract-owner tx-sender)

;; Errors
(define-constant err-owner-only (err u100)) ;; Somebody other than the contract owner called lock
(define-constant err-already-locked (err u101)) ;; The contract owner tried to call lock more than once.
(define-constant err-unlock-in-past (err u102)) ;; The passed unlock height is in the past.
(define-constant err-no-value (err u103)) ;; The owner called lock with an initial deposit of zero (u0).
(define-constant err-beneficiary-only (err u104)) ;; Somebody other than the beneficiary called claim or lock.
(define-constant err-unlock-height-not-reached (err u105)) ;; The beneficiary called claim but the unlock height has not yet been reached.

;; Data
(define-data-var beneficiary (optional principal) none)
(define-data-var unlock-height uint u0)

;; The lock function does nothing more than transferring some tokens from the tx-sender to itself and setting the two variables.
(define-public (lock (new-beneficiary principal) (unlock-at uint) (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only) ;; Only the contract owner may call lock
        (asserts! (is-none (var-get beneficiary)) err-already-locked) ;; The wallet cannot be locked twice.
        (asserts! (> unlock-at block-height) err-unlock-in-past) ;; The passed unlock height should be at some point in the future; that is, it has to be larger than the current height.
        (asserts! (> amount u0) err-no-value) ;; The initial deposit should be larger than zero. Also, the deposit should succeed (below).
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set beneficiary (some new-beneficiary))
        (var-set unlock-height unlock-at)
        (ok true)
    )
)

(define-public (bestow (new-beneficiary principal))
    (begin
        (asserts! (is-eq (some tx-sender) (var-get beneficiary)) err-beneficiary-only) ;; checks if the tx-sender is the current beneficiary
        (var-set beneficiary (some new-beneficiary)) ;; update the beneficiary to the passed principal
        ;; the principal is stored as an (optional principal). We thus need to wrap the tx-sender in a (some ...) before we do the comparison.
        (ok true)
    )
)

(define-public (claim)
    (begin
        ;; check if the tx-sender is the beneficiary
        (asserts! (is-eq (some tx-sender) (var-get beneficiary)) err-beneficiary-only)
        ;; Check that the unlock height has been reached.
        (asserts! (>= block-height (var-get unlock-height)) err-unlock-height-not-reached)
        (as-contract (stx-transfer? (stx-get-balance tx-sender) tx-sender (unwrap-panic (var-get beneficiary))))
    )
)


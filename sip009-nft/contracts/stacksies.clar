;; Adding this line makes it impossible to deploy the contract if it does not fully implement the SIP009 trait.
(impl-trait 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9.nft-trait.nft-trait)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))

(define-non-fungible-token stacksies uint)

(define-data-var last-token-id uint u0)

;; We use a variable to track the last token ID.
(define-read-only (get-last-token-id)
    (ok (var-get last-token-id))
)

;; The idea of get-token-uri is to return a link to metadata for the specified NFT. 
;; Our practice NFT does not have a website so we can return none.
(define-read-only (get-token-uri (token-id uint))
    (ok none)
)

;; The get-owner function only has to wrap the built-in nft-get-owner?.
(define-read-only (get-owner (token-id uint))
    (ok (nft-get-owner? stacksies token-id))
)

;; The transfer function should assert that the sender is equal to the tx-sender to prevent principals from transferring 
;; tokens they do not own.
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender sender) err-not-token-owner)
        (nft-transfer? stacksies token-id sender recipient)
    )
)

;; A simple guard to check if the tx-sender is equal to the contract-owner constant will prevent others from minting new tokens. 
;; The function will increment the last token ID and then mint a new token for the recipient.
(define-public (mint (recipient principal))
    (let
        (
            (token-id (+ (var-get last-token-id) u1))
        )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (try! (nft-mint? stacksies token-id recipient))
        (var-set last-token-id token-id)
        (ok token-id)
    )
)
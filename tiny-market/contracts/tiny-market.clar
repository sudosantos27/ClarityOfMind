(use-trait nft-trait 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9.nft-trait.nft-trait)
(use-trait ft-trait 'SP3FBR2AGK5H9QBDH3EEN6DF8EK8JY7RX8QJ5SVTE.sip-010-trait-ft-standard.sip-010-trait)

(define-constant contract-owner tx-sender)

;; listing errors
(define-constant err-expiry-in-past (err u1000)) ;; he expiry block height is in the past
(define-constant err-price-zero (err u1001)) ;; the listing price is zero

;; cancelling and fulfilling errors
(define-constant err-unknown-listing (err u2000)) ;; The listing the tx-sender wants to cancel or fulfil does not exist.
(define-constant err-unauthorised (err u2001)) ;; The tx-sender tries to cancel a listing it did not create.
(define-constant err-listing-expired (err u2002)) ;; The listing the tx-sender tries to fill has expired.
(define-constant err-nft-asset-mismatch (err u2003)) ;; The provided NFT asset trait reference does not match the NFT contract of the listing.
(define-constant err-payment-asset-mismatch (err u2004)) ;; The provided payment asset trait reference does not match the payment asset contract of the listing.
(define-constant err-maker-taker-equal (err u2005)) ;; The maker and the taker (seller and the buyer) are equal.
(define-constant err-unintended-taker (err u2006)) ;; The buyer is not the intended taker.
(define-constant err-asset-contract-not-whitelisted (err u2007)) ;; The NFT asset the seller is trying to list is not whitelisted.
(define-constant err-payment-contract-not-whitelisted (err u2008));; The requested payment asset is not whitelisted.

;; The most efficient way to store the individual listings is by using a data map that uses an unsigned integer as a key. 
;; The integer functions as a unique identifier and will increment for each new listing.
(define-map listings
    uint
    {
        maker: principal,
        ;; A listing does not need to have an intended taker, so we make it optional
        taker: (optional principal),
        token-id: uint,
        nft-asset-contract: principal,
        expiry: uint,
        price: uint,
        ;; If the seller wants to be paid in STX, then there is no payment asset. If the seller wants to be paid using a SIP010 token, 
        ;; then its token contract will be stored
        payment-asset-contract: (optional principal) 
    }
)

(define-data-var listing-nonce uint u0)

;; The whitelist itself is a simple map that stores a boolean for a given contract principal.
(define-map whitelisted-asset-contracts principal bool)

;; is-whitelisted allows anyone to check if a particular contract is whitelisted or not
(define-read-only (is-whitelisted (asset-contract principal))
    (default-to false (map-get? whitelisted-asset-contracts asset-contract))
)

;; set-whitelisted is used to update the whitelist
(define-public (set-whitelisted (asset-contract principal) (whitelisted bool))
    (begin
        (asserts! (is-eq contract-owner tx-sender) err-unauthorised);; Only the contract owner will have the ability to modify the whitelist.
        (ok (map-set whitelisted-asset-contracts asset-contract whitelisted))
    )
)

(define-private (transfer-nft (token-contract <nft-trait>) (token-id uint) (sender principal) (recipient principal))
    (contract-call? token-contract transfer token-id sender recipient)
)

(define-private (transfer-ft (token-contract <ft-trait>) (amount uint) (sender principal) (recipient principal))
    (contract-call? token-contract transfer amount sender recipient none)
)

;; Principals will call into a function list-asset to put their NFT up for sale. The call will have to include a 
;; trait reference and a tuple that contains the information to store in the listing map
(define-public (list-asset (nft-asset-contract <nft-trait>) (nft-asset {taker: (optional principal), token-id: uint, expiry: uint, price: uint, payment-asset-contract: (optional principal)}))
    ;; Retrieve the current listing ID to use by reading the listing-nonce variable.
    (let ((listing-id (var-get listing-nonce)))
        ;; Assert that the NFT asset is whitelisted.
        (asserts! (is-whitelisted (contract-of nft-asset-contract)) err-asset-contract-not-whitelisted)
        ;; Assert that the provided expiry height is somewhere in the future.
        (asserts! (> (get expiry nft-asset) block-height) err-expiry-in-past)
        ;; Assert that the listing price is larger than zero.
        (asserts! (> (get price nft-asset) u0) err-price-zero)
        ;; If a payment asset is given, assert that it is whitelisted.
        (asserts! (match (get payment-asset-contract nft-asset) payment-asset (is-whitelisted payment-asset) true) err-payment-contract-not-whitelisted)
        ;; Transfer the NFT from the tx-sender to the marketplace.
        (try! (transfer-nft nft-asset-contract (get token-id nft-asset) tx-sender (as-contract tx-sender)))
        ;; Store the listing information in the listings data map.
        (map-set listings listing-id (merge {maker: tx-sender, nft-asset-contract: (contract-of nft-asset-contract)} nft-asset))
        ;; Increment the listing-nonce variable.
        (var-set listing-nonce (+ listing-id u1))
        ;; Return an ok to materialise the changes.
        (ok listing-id) ;; return the listing ID when everything goes well as a convenience for frontends and other contracts that interact with the marketplace.
    )
)

;; read-only function that returns a listing by ID
(define-read-only (get-listing (listing-id uint))
    (map-get? listings listing-id)
)

(define-public (cancel-listing (listing-id uint) (nft-asset-contract <nft-trait>))
    (let (
        (listing (unwrap! (map-get? listings listing-id) err-unknown-listing))
        (maker (get maker listing))
        )
        (asserts! (is-eq maker tx-sender) err-unauthorised)
        (asserts! (is-eq (get nft-asset-contract listing) (contract-of nft-asset-contract)) err-nft-asset-mismatch)
        (map-delete listings listing-id)
        (as-contract (transfer-nft nft-asset-contract (get token-id listing) tx-sender maker))
    )
)

(define-private (assert-can-fulfil (nft-asset-contract principal) (payment-asset-contract (optional principal)) (listing {maker: principal, taker: (optional principal), token-id: uint, nft-asset-contract: principal, expiry: uint, price: uint, payment-asset-contract: (optional principal)}))
    (begin
        ;; Retrieve the listing from the listings data map and abort if it does not exist.
        (asserts! (not (is-eq (get maker listing) tx-sender)) err-maker-taker-equal)
        ;; Assert that the taker is not equal to the maker.
        (asserts! (match (get taker listing) intended-taker (is-eq intended-taker tx-sender) true) err-unintended-taker)
        ;; Assert that the expiry block height has not been reached.
        (asserts! (< block-height (get expiry listing)) err-listing-expired)
        ;; Assert that the provided NFT trait reference is equal to the principal stored in the listing.
        (asserts! (is-eq (get nft-asset-contract listing) nft-asset-contract) err-nft-asset-mismatch)
        ;; Assert that the payment asset trait reference, if any, is equal to the one stored in the listing.
        (asserts! (is-eq (get payment-asset-contract listing) payment-asset-contract) err-payment-asset-mismatch)
        (ok true)
    )
)

(define-public (fulfil-listing-stx (listing-id uint) (nft-asset-contract <nft-trait>))
    (let (
        (listing (unwrap! (map-get? listings listing-id) err-unknown-listing))
        (taker tx-sender)
        )
        (try! (assert-can-fulfil (contract-of nft-asset-contract) none listing))
        (try! (as-contract (transfer-nft nft-asset-contract (get token-id listing) tx-sender taker)))
        (try! (stx-transfer? (get price listing) taker (get maker listing)))
        (map-delete listings listing-id)
        (ok listing-id)
    )
)

(define-public (fulfil-listing-ft (listing-id uint) (nft-asset-contract <nft-trait>) (payment-asset-contract <ft-trait>))
    (let (
        (listing (unwrap! (map-get? listings listing-id) err-unknown-listing))
        (taker tx-sender)
        )
        (try! (assert-can-fulfil (contract-of nft-asset-contract) (some (contract-of payment-asset-contract)) listing))
        (try! (as-contract (transfer-nft nft-asset-contract (get token-id listing) tx-sender taker)))
        (try! (transfer-ft payment-asset-contract (get price listing) taker (get maker listing)))
        (map-delete listings listing-id)
        (ok listing-id)
    )
)
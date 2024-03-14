
;; title: multisig-vault

;; SUMMARY: 
;; simplified DAO that allows its members to vote on which principal is allowed to withdraw the DAO's token balance. 
;; The DAO will be initialised once when deployed, after which members can vote in favour or against specific principals.

;; DESCRIPTION:
;; The initialising call will define the members (a list of principals) and the number of votes required to be allowed 
;; to withdraw the balance.
;; The voting mechanism will work as follows:

;; - Members can issue a yes/no vote for any principal.
;; - Voting for the same principal again replaces the old vote.
;; - Anyone can check the status of a vote.
;; - Anyone can tally all the votes for a specific principal.

;; Once a principal reaches the number of votes required, it may withdraw the tokens.

;; Owner
(define-constant contract-owner tx-sender)

;; Errors
(define-constant err-owner-only (err u100)) ;; Someone other than the owner is trying to initialise.
(define-constant err-already-locked (err u101)) ;; The vault is already locked.
(define-constant err-more-votes-than-members-required (err u102)) ;; The initialising call specifies an amount of votes required that is larger the number of members.
(define-constant err-not-a-member (err u103)) ;; non-member tries to vote
(define-constant err-votes-required-not-met (err u104))

;; Variables
(define-data-var members (list 100 principal) (list))
(define-data-var votes-required uint u1)
(define-map votes {member: principal, recipient: principal} {decision: bool})
;; The members will be stored in a list with a given maximum length. The votes themselves will be stored in a map that uses a 
;; tuple key with two values: the principal of the member issuing the vote and the principal being voted for.
;; it is important to note that such member lists are not sufficient for larger projects as they can quickly become expensive to use.

;; The start function will be called by the contract owner to initialise the vault. It is a simple function that updates 
;; the two variables with the proper guards in place.
(define-public (start (new-members (list 100 principal)) (new-votes-required uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (len (var-get members)) u0) err-already-locked)
        (asserts! (>= (len new-members) new-votes-required) err-more-votes-than-members-required)
        (var-set members new-members)
        (var-set votes-required new-votes-required)
        (ok true)
    )
)

(define-public (vote (recipient principal) (decision bool))
    (begin
        ;; make sure the tx-sender is one of the members
        (asserts! (is-some (index-of (var-get members) tx-sender)) err-not-a-member)
        (ok (map-set votes {member: tx-sender, recipient: recipient} {decision: decision}))
    )
)

;; read-only function to retrieve a vote
(define-read-only (get-vote (member principal) (recipient principal))
    ;; If a member never voted for a specific principal before, we will default to a negative vote of false.
    (default-to false (get decision (map-get? votes {member: member, recipient: recipient})))
    ;; Use map-get? to retrieve the vote tuple. The function will return a some or a none.
    ;; get returns the value of the specified key in a tuple. If get is supplied with a (some tuple), it will return a (some value). If get is supplied none, it returns none.
    ;; default-to attempts to unwrap the result of get. If it is a some, it returns the wrapped value. If it is none, it returns the default value, in this case false.
)

;; fold will iterate over input-list, calling accumulator-function for every element in the list. The accumulator function 
;; receives two parameters: the next member in the list and the previous accumulator value. The value returned by the 
;; accumulator function is used as the input for the next accumulator call.
;; Since we want to count the number of positive votes, we should increment the accumulator value only when the vote for the 
;; principal is true. There is no built-in function that can do that so we have to create a custom accumulator as a private function.
(define-private (tally (member principal) (accumulator uint))
    (if (get-vote member tx-sender) (+ accumulator u1) accumulator)
)

(define-read-only (tally-votes)
    (fold tally (var-get members) u0)
)
;; The tally-votes function returns the result of folding over the members list. Our custom accumulator function tally calls 
;; the get-vote read-only function we created earlier with the current current member from the list and the tx-sender. 
;; The result of this call will be either true or false. If the result is true, then tally returns the accumulator 
;; incremented by one. Otherwise, it returns just the current accumulator value.


(define-public (withdraw)
    (let
        (
            (recipient tx-sender)
            (total-votes (tally-votes))
        )
        ;; It will tally the votes for tx-sender and check if it is larger than or equal to the number of votes required.
        (asserts! (>= total-votes (var-get votes-required)) err-votes-required-not-met)
        (try! (as-contract (stx-transfer? (stx-get-balance tx-sender) tx-sender recipient)))
        (ok total-votes)
    )
)

;;  It is definitely not required as users can transfer tokens to a contract principal directly. The function will be useful when writing unit tests later.
(define-public (deposit (amount uint))
    (stx-transfer? amount tx-sender (as-contract tx-sender))
)

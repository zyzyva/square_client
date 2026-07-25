# Slice 04 — Square-hosted subscription checkout links

Blocks: none
Blocked by: none
Parallel-safe with: 01, 03

## Intent

The library covers catalog, customers, payments, plans, subscriptions, and
webhooks, but has no module for Square-hosted online checkout. An app that
wants to send a customer a hosted subscription checkout link must hand-roll
the payment-link API call — which happened in a shell script during a real
client provisioning on 2026-07-25, and picked the wrong location on a
multi-location account, rendering another company's name as the checkout
page heading. This slice adds first-class subscription checkout links with
the two failure modes from that night made impossible by design.

## Externally visible behavior

A new public checkout capability exposes one operation: create a subscription
checkout link. The caller provides the application, the plan key, the
variation key, the Square location identifier, and optional extras. On success
the caller gets the hosted checkout URL and the payment link identifier. On
failure the caller gets a descriptive error and nothing was created.

Two design constraints are load-bearing and non-negotiable:

1. Price, currency, and product name are sourced from the JSON plan catalog
   through the existing plan reader. There is no way for the caller to supply
   an amount, currency, or display name. Square rejects a payment link whose
   price disagrees with the plan variation, and a caller-supplied amount is a
   second place for the number to live and drift.
2. The location identifier is a required input, and the operation fails fast
   without it — before any API call, with an error message that says the
   location determines the merchant name rendered on the hosted checkout page
   and therefore must be chosen deliberately. The library never lists
   locations and picks one.

## Edge cases (each one is an error, returned before or instead of a link)

- Unknown plan key or unknown variation key for the given app: error naming
  the key that failed to resolve.
- Variation exists but is marked inactive in the catalog: refused — inactive
  variations are not for sale.
- Variation exists but has no Square variation ID for the current environment
  (sandbox versus production): error naming the plan, variation, and
  environment, pointing at the provisioning tasks as the remedy.
- Missing or empty location identifier: the fail-fast error described above.
- Square API unreachable: the library's established API-unavailable error
  convention, consistent with the other modules.
- Square returns a non-success response: the error detail Square provided is
  surfaced, consistent with how the catalog module reports API errors.

## Acceptance criteria

1. Happy path, verified against the mocked HTTP layer: the request body the
   library sends carries the variation's price and currency exactly as the
   catalog JSON defines them, the product name from the catalog, the caller's
   location identifier, and the current environment's Square variation ID; the
   returned value carries the hosted checkout URL and the payment link ID that
   the mocked Square response contained.
2. One test per edge case above, asserting the specific error and that no
   HTTP request was made for the pre-flight failures (unknown keys, inactive,
   missing variation ID, missing location).
3. No test makes a live network call; the HTTP mocking pattern matches the
   existing test suite.
4. README gains a checkout section documenting the capability, its inputs,
   and the two design constraints, consistent with the existing doc style.
   CHANGELOG records the addition under Added.
5. This slice carries the version bump in the project file for the whole
   four-slice wave — a new public module is a minor version increase for
   every consumer.
6. mix check clean while in flight; mix check.all clean before merge.

## Out of scope

- Payment links for one-time purchases (subscription variations only in this
  slice; the catalog's one-time-purchases section is untouched).
- Listing, updating, or deleting existing payment links.
- Webhook handling for payment-link events.
- Any subscription-record syncing after checkout completes (existing webhook
  and subscription machinery already owns that).
- site_forge's dependency pin bump (coordinated separately by the machine
  coordinator; noted here only so the release is tagged and communicated).

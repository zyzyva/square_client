# Slice 01 — Plan variation currency must never reach Square empty

Blocks: 02
Blocked by: none
Parallel-safe with: 03, 04

## Intent

A subscription plan variation created through this library must always carry a
currency by the time the request reaches Square. Today a catalog JSON file with
no currency field produces a variation request with a null currency, and Square
rejects it with "If subscription phase pricing type is STATIC, price amount and
currency must be set." This broke a real production provisioning run for
site_forge on 2026-07-25.

## Root cause (verified)

The variation struct constructor already defaults currency to USD, but only
when the currency key is entirely absent. Both provisioning tasks (sandbox and
production) build their arguments by reading the currency field out of the JSON
config and passing it along explicitly — so when the config omits currency, the
tasks pass an explicit null, the "put if absent" default never fires, and null
goes to Square.

## Externally visible behavior

- Creating a plan variation with the currency absent results in USD being sent
  to Square.
- Creating a plan variation with the currency explicitly null (the value read
  from a config file that omits the field) also results in USD being sent.
- Creating a plan variation with any explicitly provided currency sends that
  currency through unchanged.
- This holds for every path that constructs a variation: the public catalog
  function called with a plain map, the variation struct constructor, and both
  provisioning mix tasks reading a catalog JSON that lacks currency fields.

## Edge cases

- Currency present but set to an empty string in the JSON: treat the same as
  missing — default to USD. An empty string is never a valid currency.
- The one-time-purchases section of the catalog JSON is not in scope; only
  subscription plan variations.

## Acceptance criteria

1. A test drives variation creation with no currency given and asserts, via the
   mocked HTTP layer, that the request body Square would receive carries USD.
2. A test does the same with currency explicitly null and asserts USD.
3. A test with an explicit non-USD currency asserts pass-through unchanged.
4. A test with currency as empty string asserts USD.
5. All existing tests still pass; mix check is clean.

## Out of scope

- Validating that a provided currency is a real ISO code.
- Multi-currency catalog support.
- Changes to the init_plans scaffold template (it already includes currency).
- CHANGELOG entry: yes, under Fixed. Version bump is coordinated in slice 04.

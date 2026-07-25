# Slice 02 — Provisioning validates the whole plan definition before creating anything

Blocks: none
Blocked by: 01
Parallel-safe with: none (shares the variation-validity rule introduced in 01)

## Intent

A failed provisioning run must not leave objects stranded in a real merchant
catalog. On 2026-07-25 the production setup task created a base plan, then
failed on every variation (currency error), leaving an empty base plan in a
live Square production account. Square does not allow deleting subscription
plans once created — archive is the best available remedy — so after-the-fact
cleanup cannot make this safe. The only honest fix is to refuse to create
anything until the entire plan definition is known to be valid.

## Externally visible behavior

- Both provisioning tasks (sandbox setup and production setup) validate every
  plan they are about to create, and every active variation under it, before
  making any Square API call.
- Validity means: the plan has a name; each active variation has a name, a
  billing cadence, and a positive integer amount. Currency is guaranteed by
  slice 01 and is not a user-facing validation failure.
- If anything is invalid, the task prints a report naming each offending plan
  and variation and the specific field that is missing or wrong, creates
  nothing, and exits with a failure status. Zero HTTP requests are made.
- If validation passes, behavior is unchanged from today for the happy path.
- If a Square API call fails mid-run despite valid input (network, auth, API
  rejection), the task stops processing that plan, prints exactly which objects
  it already created in this run with their Square IDs, names the cleanup task
  as the remedy for stranded objects, and finishes with a failure status
  instead of a success banner.

## Edge cases

- Free plans are skipped by validation exactly as they are skipped by creation.
- Inactive variations are not validated (they are never created).
- Plans that already have all their Square IDs configured are not re-validated
  for creation fields; the task's existing sync path handles them.
- Dry-run mode performs the same validation and reporting but, as today, never
  calls Square.

## Acceptance criteria

1. A test feeds a config missing a variation amount, runs the provisioning
   flow against a mocked HTTP layer, and asserts the mock received zero
   requests and the task reported failure naming the plan, variation, and
   field.
2. A test with a fully valid config asserts creation proceeds exactly as
   before (existing tests keep passing).
3. A test simulates the base plan creating successfully and a variation call
   failing, and asserts the output lists the created base plan's Square ID,
   mentions the cleanup task by name, and the run signals failure rather than
   printing the success banner.
4. Both tasks share one validation implementation — the rule cannot drift
   between sandbox and production paths.
5. mix check is clean.

## Out of scope

- Automatic deletion or archiving of stranded objects (Square forbids plan
  deletion; silent archive of production objects is riskier than reporting).
- Validation of the one-time-purchases section.
- Rollback of config-file ID writes for objects that were successfully created
  (a created object's ID being recorded is correct even when a later step
  fails).
- CHANGELOG entry: yes, under Fixed/Changed. Version bump coordinated in
  slice 04.

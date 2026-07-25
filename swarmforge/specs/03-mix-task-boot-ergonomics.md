# Slice 03 — Mix tasks must not boot the consuming application

Blocks: none
Blocked by: none
Parallel-safe with: 01, 04

## Intent

All five square mix tasks (init_plans, list_plans, setup_plans,
setup_production, cleanup_plans) currently boot the consuming application in
full before doing their work. In a real app this starts the whole supervision
tree: on 2026-07-25 a provisioning run buried its own confirmation prompt
under hundreds of lines of Oban and ExAws log output (the operator concluded
the task had hung), and started a second Oban instance racing the already
running dev server. The tasks only need three things: the consuming app's
configuration, its priv directory resolvable on disk, and a working HTTP
client. None of those requires starting the app's supervisors.

## Externally visible behavior

- Running any of the five tasks in a consuming app does not start that app's
  supervision tree: no queue workers, no web endpoint, no repo, no background
  jobs. A dev server already running in another terminal is unaffected.
- The tasks still read the app's full runtime configuration (including values
  set in runtime config files), still resolve files under the app's priv
  directory, and the API-calling tasks still successfully make HTTP requests.
- Task output is readable as the primary content of the terminal: prompts
  (production confirmation, cleanup confirmation) appear promptly and are not
  buried under application log noise.

## Edge cases

- Tasks must still work when the consuming app has never been compiled in the
  current environment (compilation happens as part of the task, as today).
- The production setup task's environment switch (temporarily pointing
  configuration at the production API) must behave exactly as it does now.
- If some future consuming app genuinely needed its tree running for a task,
  that is explicitly not supported; these tasks are catalog-file and HTTP
  operations only.

## Acceptance criteria

1. No square mix task invokes the full application start path anymore; each
   loads configuration and application code without starting supervisors, and
   starts only the minimal runtime dependencies the HTTP client needs.
2. A test (or tests) covering each task's entry path asserts the task no
   longer triggers the full app start. Where the library's own test suite
   cannot observe a real consuming app's tree, the handoff must say so
   explicitly and name the manual verification performed instead.
3. Existing task behavior — argument parsing, dry-run, confirmation prompts,
   file reads and writes, API calls — is unchanged and covered by the existing
   and new tests.
4. Manual smoke verification in one real consuming app (contacts4us is the
   reference) is performed before this slice is called done, and its result is
   stated in the handoff: task output visible, prompt immediate, no second
   Oban instance, dev server untouched.
5. mix check is clean.

## Out of scope

- Silencing or reconfiguring the consuming app's logger while its tree runs
  (we simply never start the tree, so there is nothing to silence).
- Changes to what the tasks do once running.
- CHANGELOG entry: yes, under Changed. Version bump coordinated in slice 04.

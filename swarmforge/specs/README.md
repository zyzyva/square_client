# Slice Specs

Plain-English slice specs for square_client live here, numbered sequentially (e.g. `01-<slug>.md`).

Each spec names the externally visible behavior, edge cases, acceptance criteria, and what's explicitly out of scope. No code in specs — implementation is the coder's job.

Mark dependencies explicitly: `Blocks: X.Y` and `Blocked by: Z.W`. Call out parallel-safe groups so independent slices can run concurrently.

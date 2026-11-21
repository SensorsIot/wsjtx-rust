**Layer:** HOW. **Scope:** this project's development environment and procedures.

## Merge queue

A reviewed CR reaches master through the harness
[merge queue](../../../general/core/docs/Merge-Queue.md),
whose worker runs on HB9BLA ([machine](machine.md#machine)): the coordinator hands in the reviewed tip
(`python harness/general/core/tools/merge_queue.py submit <issue> <tip>`) and builds no merge
itself. The queue's records are local to HB9BLA.
The `queue:` section of `harness/project/config.yaml` names the tools the gate needs (Node 24
or later, npm, Cargo, rustc, `gh`, the MSVC linker), 20 GB free on every drive the gate uses, the
input environment of [Inputs](local-windows-development.md#inputs) and the `npm ci` setup of
the queue's worktree. The worker runs as a background job from the main checkout
`D:\Github\wsjtx-rust`, with the pinned harness:

```bash
python harness/general/core/tools/merge_queue.py worker
```

Priorities on HB9BLA ([heavy runs](../Agent-Working-Rules.md#who-changes-what)): the
station task `WSTX Rust Station HB9BLA` runs at High, above the gate; the gate runs at
ABOVE_NORMAL with unbounded build parallelism; agent builds and tests outside the gate
run at BelowNormal with a bounded `CARGO_BUILD_JOBS` (2, as
[Inputs](local-windows-development.md#inputs) sets it).

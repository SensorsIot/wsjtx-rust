**Layer:** HOW. **Scope:** this project's development environment and procedures.

## Project model documentation contract

### Required sequence for functional issues

1. Identify the current canonical contract, implemented baseline and affected owners.
2. Settle the changed promises in the issue, in the model's wording: each clause with the
   FR it derives from and the use-case step that carries it (M6.2, M6.11), each test case
   by identity and title (M6.5), and a negative test for each clause that prevents
   something. The coder writes them into the model with the code. An issue that changes the architecture lists its added and removed parts, ports and
   connections, written before `python tools/sysml.py oracle` runs and never from its
   output; its acceptance compares that list with `oracle`'s change lines.
3. Settle open decisions on behaviour, data, ownership, states, timing, errors and test
   oracles with the operator; unresolved ones block the issue. A device or protocol whose
   behaviour is unknown gets an experiment (`cr:experimenting`) within the
   [limits below](#limits-for-experiments), findings on the issue. The issue then passes the
   ready check of the [CR process](../../../general/core/docs/CR-Process.md): an agent that did not
   write it posts `Ready: PASS`. A model-readiness review is held only on request.
4. Implement against the model and declared normative references. Verification keeps
   independent expected values and does not generate its sole oracle from that code.
5. Test the function, for real where it matters (a few short transmissions need no prior
   review; long or unattended on-air running waits for it). Only when the function is OK,
   independently review the exact candidate to find undesired behaviour; then the gate.
   Keep test existence, actual execution, model readiness and live acceptance separate.
6. Before issue closure reconcile delivered functionality, test cases and model/source
   bindings, and the `@CodeDiffers` markers the change resolves (M6.13). Current issues retain approval, review, deployment and dated execution evidence.

### Limits for experiments

The limits the [CR process](../../../general/core/docs/CR-Process.md) leaves to the project:

- Throwaway scripts live in `D:/wstx-tmp/experiments/<issue>/`, are never committed and may
  hold radio addresses.
- Live runs log under `D:/wstx-tmp/live/<issue>/`, removed when the issue closes.
- The radio is keyed as in any agent test: the radio preflight and its lease first
  ([Keying the radio](deployment-authority.md#keying-the-radio)), and short test transmissions only.
- Anything that needs the operator (the Flex switched on) is prepared and dry-run first.
- Three real runs without an answer mean stop and report to the operator.

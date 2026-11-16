# Testing

**Status:** present-state. **Layer:** HOW. **Scope:** portable.

Tool-independent testing and verification discipline. The steps that run tests are the
[CR process](../CR-Process.md); per-language checks are each pack's `pack.yaml` and
`## Testing` chapter; a project's concrete accounts, commands and schedules are its
testing binding.

## Procedure

- **A check MUST be a real, runnable command.** An unwired check is labelled `Target` and
  **MUST NOT** be claimed as run.
- **Dry-run before apply.** Destructive or outward-facing operations preview first; the
  apply step is an explicit gate.
- **Verify in the live system after a change**: exercise the changed path and confirm the
  observable result.
- **Regression-first for bugs.** Reproduce with a failing check, fix, confirm it passes;
  `red_on_parent.py` proves the test fails without the fix.
- **Test the boundary.** Negative and permission cases for every endpoint; validation and
  error paths for every input.
- **A fake names its source.** A fake of a device or an external protocol names the
  captured real sample it is built from, or marks its assumption unverified.

## Cost levels

Every suite in `.harness/suites.yaml` declares one `cost`; it decides where the suite runs.

| Cost | What it is | Runs |
|---|---|---|
| 1 | compiler, syntax, format or lint check | push gate (the packs' checks, or a registered suite) |
| 2 | offline, with fixtures or stubs | push gate, on the suites a change selects |
| 3 | live, read-only | live acceptance after the deploy; schedules |
| 4 | live, with the test account | live acceptance, with the operator's consent or a [standing consent policy](../CR-Process.md#standing-deploy-and-consent-policies) |
| 5 | live, with effects outside the system | live acceptance, with the operator's consent or a [standing consent policy](../CR-Process.md#standing-deploy-and-consent-policies) |

**Test on the cheapest level that proves the case.** A cost-2 test proves the changed
source; a live (3–5) pass proves whatever revision is deployed, so it never counts as
evidence for an undeployed change. After the deploy, the live suites the change reaches
re-run as its acceptance.

A suite declares `paths` (the prefixes whose change selects it), optionally `needs`
(prerequisites, what it proves and does not prove), `changes` (what a cost-4/5 suite
changes) and `blocked` (why it must not run yet). Selection is a property of the
registry, never a per-run judgement and never a reason to delete a test.

A cost-4/5 live test records each setting it changes, with the value it found, and sets
all of them back at its end, after an abort too. A stop it triggers acts only on its own
run, never on another run or on the operator's use of the system. The project's bindings
name the settings.

### Functional test selection

Use one registry entry per independently runnable functional group. A group's `run`
uses its existing runner to name its tests; no second runner is required. `paths` always
declares every file the command reads and fingerprints, including shared code, fixtures
and test files. Optional `select` lists narrower prefixes for changes that directly
affect the group. Every `select` prefix must lie inside a declared `paths` prefix.

`depends_on: [group-name]` describes **impact**: a selected group also selects all its
downstream dependents, transitively. It does not mean that the named command must run
first, nor that changing a dependent requires testing its unchanged upstream group.
The producer groups' transitive inputs and registry entries also enter a dependent's
fingerprint and dirty-input checks; an earlier pass cannot hide a changed producer.
Declare shared contracts, validation and security effects explicitly. Review the
dependency map as enforcement policy; a test command's file reads alone do not establish
which changes can affect its behavior. Missing dependencies and cycles are refused.

For example, a display group can select `client/recording.js`, while the thin-link
regression group depends on the display group and a separate profile group selects
`client/app.js`. The display group may read both files but a reviewed dependency map
must establish why only its direct triggers affect that particular assertion. A
change to the model can explicitly select model/contract verification while implementation and
test-source changes select runtime groups; this is safe only when those checks and the
reviewed map cover contract changes. Otherwise keep broad contract triggers.

**Cycle budget.** The process is designed so that a small product CR completes its
entire cycle within ten minutes, from the start of work through implementation, tests,
review, push gate and push to the installed system. A small CR is a product change
confined to one area of the code, such as one module and its tests. Time spent waiting
on the operator and consented cost 3–5 suites fall outside it. The budget shapes the
process, the selection map and the gate. It never caps an individual step or cuts work
short. A cycle that exceeds it is a harness defect, fixed in the process, the map or
the gate. Three rules follow:

- **Minimal selection.** A change selects only the groups that test what it changed. A
  `select` that claims a whole source tree (`server/`, `src/`) for a group testing one
  part of it is a defect. Narrow `select` to the code the group's assertions exercise,
  and keep the full tree in `paths`. Declare `depends_on` only for an impact the map's
  reviewer can name. Chains of convenience that fan one change out to unrelated groups
  are refused in review.
- **Measurements only when time-critical.** Functional groups assert behaviour, not
  wall-clock budgets. Every timing, latency, cadence or throughput assertion is a
  measurement, and a measurement runs only when the change can alter what it measures
  (see [timing suites](#timing-suites)): a suite marked `timing: true` is selected only
  by its `timing_inputs`, such as a real-time processing pipeline, transport
  and compression, scheduling or cadence code and the measurement's own test files, or on
  request. A budget is never loosened to make a split pass.
- **Gate priority.** Measurement groups compete for the CPU with other work on the
  machine. The gate MUST therefore run its suites at raised process priority where the
  platform allows it (harness#28), so that concurrent development work
  gets only the CPU the suites leave over. A live service or operator workload on the
  same machine (a real-time capture, an application the operator uses) MUST run above the
  gate's priority, so that no gate or build starves it. Agent builds and tests outside
  the gate MUST run below normal priority with bounded build parallelism (for example on
  Windows: BelowNormal and `CARGO_BUILD_JOBS=4`). The live service's priority is set
  where the service is started (for example its scheduled task). The project's bindings
  name the service, its priority and the agent build settings.

If a changed input has no declared direct owner, every functional group declaring that
input is selected. A changed path outside all declarations selects every functional
group. Selection-policy edits (`.harness/` or the in-project harness code) also select
every functional group. These are conservative fallbacks, never a way to report an
unclassified change as green; they do not select timing suites, which only their timing
inputs, their own registry entry, a request or `--full` select. Legacy
registries without `select` or `depends_on` keep their existing prefix selection.
Full inputs, global/unowned files, policy entries and selector implementation identity
are fingerprinted; uncommitted declared inputs still refuse a run.

`gate.py --plan --base REV` shows selected commands and reasons without executing checks
or recording a pass; for a harness-only change it says so (not gated; the push
runs only the secret scan). `gate.py --full` checks all tracked inputs and runs every eligible
group without memo reuse. Cost levels, blocked suites, root-command restrictions,
compiler checks and live-consent requirements still apply. GitHub mode still defers
local validation; `--ci` retains full-HEAD validation without memos (a harness-only pull
request excepted) and refuses `--plan`.
A plan is not validation. A new map is a harness change: its `--plan` output on
representative changes is evidence for its review. The measured selection and elapsed
gate time of the product CRs that follow it then establish whether it saves effort
([Harness changes](../Harness-Changes.md), step 6). Estimates alone do not establish
an efficiency improvement.

The gate records where its time goes and what its suites reach, in the run ledger
(`core/tools/gate.py` docstring): per suite run its start, end, waits and selection
reason, and the tests its output names (`core/tools/reachability.py`, which also lists
every `Proves:`-tagged test no suite reaches and, with the project's model bindings, every
automated verification case that resolves to no reached test; a suite whose tests its
runner's lines do not name declares how its output is read, its `reach` entry). Beside the path selection
it reports a narrower **candidate selection** with both estimated wall times
(`core/tools/candidate.py`); the candidate never skips a suite, the path selection stays
what runs. A selector that skips suites is a separate harness change, justified by this
record; `report_cr.py --gate` summarises it ([CR reporting](../CR-Reporting.md#gate-retrospective)).

### Timing suites

A measurement belongs to a **timing suite** (`timing: true` in `.harness/suites.yaml`)
or to the timing part of a mixed suite. Each declares `timing_inputs`: path prefixes,
inside its `paths`, whose change can alter the measured timing. The rule of the push
gate is then one rule, with no exception:

- A timing suite runs when a changed path starts with one of its `timing_inputs`, when
  its own registry entry changed, when timing is requested, and in `--full` and `--ci`
  (which check every input). A functional `select`, an unmapped-input or unowned-path
  fallback, a policy edit and `depends_on` never select it. A timing suite has no
  `select`. When it is not selected although the change reads its inputs, the gate lists
  it as `TIMING  <suite> not run`.
- Timing is requested for a push by `Harness-Timing: yes` as a trailer of any commit
  since the base (it travels with the CR, also through the merge queue), by
  `HARNESS_TIMING_REQUEST=1` in the gate's environment, or by `gate.py --timing`. A request runs
  the timing suites whose `paths` the change touches, not every one.
- A **mixed suite** (functional, with `timing_inputs` and without `timing: true`) is
  selected as a functional group. The gate runs it with `HARNESS_TIMING=1` only when one
  of its timing inputs changed, timing is requested or the run is full, and otherwise
  with `HARNESS_TIMING=0`; its tests skip their timing assertions at `0` and run them at
  `1` or when the variable is unset (a run outside the gate measures). The value is part
  of the suite's fingerprint: a pass at `0` is no evidence for a run at `1`, while a pass
  at `1` also covers `0`. Every other suite runs with `HARNESS_TIMING=1`; the gate never
  reads `HARNESS_TIMING` as a request, so a gate started inside a suite judges its own change.

A project splits a measurement from a functional test by moving it into a timing suite
(by test name or file, as with any group) or by guarding the assertion with
`HARNESS_TIMING`. Either way the functional behaviour around it keeps running on every
functional change; only the clock assertion waits for a time-critical change. The
`timing_inputs` are reviewed like any selection map: they name the code that sets the
measured time, never a subset chosen to keep a measurement from running. A timing test
that reads its bound from the product contract (test-design, Oracle rule) has that bound
as an input too: its suite's `timing_inputs` list the model file that holds the bound,
so a change of the bound alone runs the measurement. A timing red
whose cause lies outside its suite's `timing_inputs` adds the cause's path to them with
its repair.

### Timing classes

A timing suite says *when* a measurement runs; a **timing class** says *what kind of
time* a timed test depends on, and so where it may run and how its red is judged
(harness#53). A project that binds classes (`timing_classes` in `.harness/config.yaml`,
`core/tools/timing_class.py`) labels each timed test with one class, in a comment in the
block directly above the test (where `Proves:` stands, e.g. `// Timing: radio`). Each
class binds:

- **clock**: the clocks its tests may use, each bound by the source patterns that show
  its use (`real`: `Instant::now`, `sleep`; `cpu`: process CPU time; `injected`: a driven
  test clock). A class with no clock counts in samples only.
- **isolation**: `any` (any neighbours), `declared` (only the neighbours its suite's
  `exclusive` tags admit) or `alone` (`exclusive: ["*"]`). A suite states the classes it
  runs with `timing_classes: [...]` in its registry entry.
- **red**: `never` (always a defect: the merge queue never reruns it), `rerun` (one rerun
  when the change does not touch the test, a green rerun recorded on the flake issue; the
  default of an unclassified test), `flake` (the same rerun, recorded in the queue's
  history only) or `inconclusive` (as `rerun`; its suite may exit 77, NOT RUN, when the
  measurement cannot be qualified).

The push gate checks, in its cost-1 step, every test in a changed test file: a test that
uses a clock its class does not allow, a test without a class that uses any bound clock,
and an unknown class; and the registry: a suite whose declared classes need more
isolation than its tags give. After the suites run it checks placement by use: a classed
test that a suite reached (reachability) where the suite lacks its class's isolation, or
which the suite's declared `timing_classes` leave out. `timing_classes.mode: warn` (the
default) reports these as `WARN`; `red` refuses the push. A project starts with `warn`,
labels and moves its tests, then turns it to `red`.

### Parallel suites

`gate.parallel: N` in `.harness/config.yaml` (default 1; `gate.py --parallel N` for one
run) lets the push gate run up to N selected suites at a time; the merge queue's batch
gate and its bisection go through the same gate. Suites are independent by default. A
suite names what it must not share:

- `exclusive: [tag, ...]`: no suite with one of these tags in its `exclusive` or `shared`
  list runs at the same time; `exclusive: ["*"]` runs the suite alone (a CPU or
  wall-clock measurement that other suites would disturb);
- `shared: [tag, ...]`: suites sharing a tag may overlap one another, but not a suite
  holding it `exclusive` (readers of a build output and the suite that rewrites it);
- `build: <command>` (or a list of commands): a build the suite needs. Each command runs
  once, serially, for all selected suites that name it, before any suite starts, so that
  concurrent suites do not build the same output at once. The suite's `run` stays
  complete on its own (it may repeat the build, which is then up to date); a failed
  build makes its suites red without running them.

A suite that measures in this run (a timing suite, or a mixed suite at
`HARNESS_TIMING=1`) runs alone, since a measurement beside other suites competes for the
CPU at the same priority. A project whose measurements are proven stable beside other
suites (wall-clock bounds on a simulated link rather than CPU budgets) sets
`gate.timing_alone: false` and keeps `exclusive: ["*"]` on the CPU measurements; that
choice and its evidence belong in the project's bindings.

Fixed ports, a device, the live system, a profile or lock directory under the user's
account, an output file two suites write and a build output one suite rewrites while
another executes it are such resources. The gate starts the longest suites first (mean of
their last passes), captures each suite's output and prints it whole, in name order;
the verdicts and the memo are those of a sequential run. `--live` always runs one
suite at a time.

## What a red means

A red result means one of three things, each with its own home, cadence and reader:

| Red means | Kind | Runs | Reader |
|---|---|---|---|
| the **code** is broken | **test** | when code changes | whoever ships the fix |
| the **live state** has drifted | **state sensor** | on a schedule | the operator |
| the **content** needs work | **content-audit check** | on a schedule and on demand, as a work list | the content owner |

**State sensor.** Drift arrives without a commit, so a sensor **MUST** run on a
schedule. A sensor **MUST** be read-only with respect to the state it judges and **MUST
NOT** repair it (its own log and a state file that stops an unchanged fault re-alerting
are not the state under judgement). A sensor **SHOULD** fail closed: an input it cannot
evaluate is not a healthy state. A sensor's logic is code and **SHOULD** carry a
fixture-driven cost-2 test.

**Scheduled operational writer.** A job whose purpose includes changing application
state, external systems, shared caches, backups or maintained artifacts (sync, cleanup,
repair) is an operation, not a sensor or a test, whatever its name or a `--check` flag
says. Every scheduled writer **MUST** have a documented standing authorization naming the
responsible role, its permitted effects and limits, and its failure, stop and recovery
procedure. A configured schedule alone **MUST NOT** be treated as approval. Widened
effects are reassessed before the job runs under them.

**Content-audit check.** A work list for a content owner, on its own plane; a red never
fails a code build or release.

Two placements are forbidden: a test on a schedule burns runs on an unchanged subject; a
sensor filed with the tests never runs when what it watches moves, and reads as coverage.

**A scheduled suite observes.** It is read-only against every live system; writes are
confined to temp directories and its own fixtures. A short-lived login of the test
account, logged out when the suite ends, is the one exception a binding may allow. A
suite that must change anything else runs only at live acceptance, with consent.

## Process promises

An operational process (backup, sync, renewal) is never discharged by its own success
signal: it cannot report its own absence or silent degradation. It is discharged by an
**independent outcome probe** (a different process, trigger and failure mode) and, where
the promise is usability, by a **drill** (a backup is proven by a restore).

## Worth the effort

Every promise of blast medium or high gets at least its cheapest check. Rigor scales
with blast:

- **high** (secret exposure, auth bypass, access-control leak, data loss, wrong money,
  a message to the wrong recipient, anything a user meets): negative and boundary cases on
  every barrier, and the independent review;
- **medium**: one positive and one key negative case;
- **low**: a test only where the logic is risky.

- **Live execution is rationed by cost and risk.** A promise earns a live test only when
  no independent sensor would catch its failure first.
- **No fake-objective tests.** A judgment call is reviewed, not tested; a green subjective
  test is false confidence.
- **Verifiable in seconds.** If verifying the test is as hard as verifying the code, split
  the code to expose a testable core.
- **Amortize by stability.** Stable behaviour earns durable live tests; churny behaviour
  gets cost-2 tests on its pure core.

## Automate first

- **Every test MUST be automated if any means exists**, including access to the connected
  systems it touches (APIs, mailboxes, panels driven headless, buses, DNS).
- **A manual test is a claim** that automation was attempted and is infeasible now,
  recorded with the reason and what would unblock it. An unjustified manual test is a
  defect.
- Exhaust the means before conceding manual: drive the real channel, feed its inbound
  through a hook, emulate the peer, observe, rig. A peer wrapper is a reusable asset.

## Test quality

Coverage measures that a test exists, not that it means anything:

- **Red on the parent.** A new or changed offline test **MUST** fail on the base with the
  product change removed (`python3 harness/core/tools/red_on_parent.py -- <command>`);
  one that stays green is vacuous.
- **Mutation smoke test.** Where the project wires a mutation tool (the packs name one as
  `Target`), tests for a changed promise face mechanically broken code and **MUST** turn red.
- **A suite's exit status is its verdict.** Every suite, every runner its entry line
  composes, **MUST** return non-zero when an assertion fails or a valid result cannot be
  established. A composed entry line **MUST** preserve its children's failures. Missing
  prerequisites are **unverified**, never a pass; zero checks run is never a pass. The
  suite's `needs` states its prerequisites, what it proves and its limits.
- **The gate observes the inputs.** Where strace is available (Linux), the push gate traces
  each suite and reports a file it reads that its `paths` do not cover, so an edit there
  can no longer leave the suite unselected. A suite that checks files named in its own
  data declares `inputs: named-by-data`; one whose own tests run strace declares
  `inputs: traces-itself`.
- **A surface scan states its surface.** A test that quantifies over an enumerated set
  also asserts that its enumeration is the whole surface, and states its sanctioned
  exceptions. Prefer: the runner discovers the surface from its owner; a closed set lives
  once in executable data every consumer reads.
- **Assert behaviour, never content.** A test asserts behaviour or structure (what a
  function returns, what a page shows, which elements a file declares), never a hash or a
  verbatim copy of a tracked source file. Such a pin proves nothing about behaviour, goes
  red on every edit of the pinned file, and makes the two files a conflict pair for every
  CR that touches either. A digest of an artefact that is not tracked (an upstream source
  the repository does not hold, a downloaded release) or of data the test generates is no
  pin; a digest of a tracked file is one, vendored or not: a vendored file's provenance
  digest belongs in its manifest or notice, not in a test. The push gate's cost-1 step
  lists a 64-hex literal in a changed test file that equals the sha256 (as stored, or with
  CRLF normalised to LF) of a tracked file (`core/tools/content_pin.py`), as a `WARN` by
  default and as a red check with `gate.content_pins: red`; the review checks the rule.
- **Wait on the event, not the clock.** A test reads a state only after the product has
  signalled it: a revision or a message of the expected kind and identity, an element drawn
  and stable. It takes a reply by its identity, never as the next message to arrive. A
  fixed pause before a read is a race.
- **Real time only in a measurement.** A functional test whose case needs a product timer or
  period to pass drives it (the runtime's or the browser's fake clock, or the bound set
  short through test configuration), and shows that nothing more happens by running past
  every pending timer, not by sleeping. Only a measurement waits real time, in a timing
  suite or the timing part of a mixed suite. A deadline that is not a number of the
  contract is a hang guard, set well above the observed time, and a case's setup runs on
  the fastest path that reaches its assertions: a throttled link, a cold load or a real
  device only where that is what the case proves.
- **A living document states only what it owns.** The project's functional description
  owns the durable definitions of the contract tests, the tests that show a promise at a
  part boundary (CR process, Accept). A detail test, of the inside of a part, lives with the
  code; the model names it only as part of its part's set, with no case. Executable
  assertions and fixture data remain their linked companions; fixture inventories, run
  histories and measurements belong to their executable or dated owner (the runner,
  registry, ledger), cited rather than restated. An issue plan or result is not the sole
  current test-case definition.

## Suite curation

A promise's tests **retire with the promise**, in the same change. A promise is proven
once per observation, by the cheapest test that sees it: a new case first extends the
cheapest existing test that carries the promise's `Proves:` tag and can reach the case, and
a costlier second proof stays only for a failure the cheaper one cannot see, which it names.
When a cheaper test takes over an assertion, the costlier one drops it, and a timing suite's
`timing_inputs` shrink to what it alone still measures. Suite size tracks the contract. A check **MAY** be deleted, merged
or cheapened while every escape it was built for (§Self-measurement) would still be caught.

## The accumulated suite is the standing reviewer

Tests written in earlier sessions are fresh-context checks on today's change, which is
why every change runs its affected cheap suites. A test authored in the same session as
the code it proves is **provisional** until a later session re-runs it; independence is
never claimed earlier. A recorded run names the content it validated (the gate's
fingerprint) and, for a live suite, the deployed revision where it can be determined.

## Completeness

Tests never invent intent, so the promise nobody wrote down is hunted: every code branch
serves a named owner (a promise or a named standard; an unowned branch is a wish to
escalate or dead code to remove); a periodic fresh-context exploratory probe reports
surprises as candidate promises for the operator; and escapes from real use are recorded.

## Self-measurement

A check that never demonstrably catches a defect is indistinguishable from one that does
nothing, so the method keeps an **escapes ledger** (template:
`core/templates/docs/Escapes-Ledger.md`). An **escape** is a defect caught later, or by a
more expensive check, than the cheapest check that should have caught it. A defect
discovered in use **MUST** receive its entry before its fix is reported done; an installed
CR that fails its acceptance or is reverted is such a defect. Each entry
names the **hole** and the **fix to the check**, and the fix is demonstrated against the
original defect, never asserted. Review rounds are effort, not escapes.

## Traceability

- Every contract test declares, next to itself, the promise it proves by its stable ID in
  the product contract, in one machine-parsable syntax. Unless the binding fixes another, it
  is a comment `Proves: <ID>` (several: `Proves: <ID>, <ID>`) directly above the test. A
  detail test carries no such tag; its part names it as a set.
- A changed promise names its proving test, or declares itself untestable by design.
- A promise upheld by an active control that can silently stop working (a runtime barrier,
  a build-time gate, a deploy-time configuration assertion) owes an **executed** test;
  "reviewed" never substitutes for "proven to fire".

---

**Authority:** the consuming project's bindings override on conflict; then the packs'
standards; then advisory.

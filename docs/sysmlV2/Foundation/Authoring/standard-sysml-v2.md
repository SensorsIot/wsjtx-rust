# SysML v2 companion documentation

**Status:** authoring rules. **Layer:** HOW. **Scope:** every project made with this harness.
This core chapter governs modeling, process and validation for textual SysML v2, the
product contract of every project. The project's documentation binding names the covered
model slices and validation commands.

Only functional product documentation is modeled: requirements, product behavior,
architecture/interfaces and their verification cases. Harness instructions, skills,
processes, standards and gate implementation documentation remain Markdown. This
chapter provides the rules used by the [authoring workflow](../../skills/sysml-authoring/SKILL.md).
The consuming project binding supplies model roots, IDs, domain values, tool/library pins
and runnable validation commands. This standard provides no compiler pack or gate registration.

## 1. The model is the contract; declare its scope

The approved model owns the product contract and is canonical for the implemented code.
A project keeps no active functional Markdown: retired specifications are archived,
clearly historical and are not inputs to continued preparation, validation or
implementation. Optional derived views are explanatory material and identify their model
source and revision; they are never a separately maintained specification.

A project adopting the harness with an existing FSD converts it into the model once, in a
reviewed migration: it records the exact baseline, preserves unresolved implementation
defects as defects, and rechecks concurrent code changes. The FSD is then archived and
leaves no required input.

The binding MUST identify which facts the model covers and which are outside it. A
partial model MUST declare its coverage; it MUST NOT imply that the whole project is
formalized.

A hand-written companion MUST identify its source elements. A generated companion MUST
have a reproducible generator or recorded source fingerprint and an up-to-date check.
Mechanical freshness does not prove that a human-written model preserves meaning;
independent review checks that relationship.

### Models intended to drive implementation

Declare whether the selected model slice is intended as an implementation contract.
The [conformance-review model-readiness mode](../../skills/conformance-review/SKILL.md#model-readiness-mode)
is an independent review held on request. Before implementing such a slice, settle its required observable behavior, data and
interface semantics, ownership, states, timing and failure policy, and independent test
oracles. Pin normative external references. Explicitly distinguish required decisions
from implementation choices that an agent may make.

An unresolved required decision makes that slice not implementation-ready. Parsing,
type checking, connectivity checks and a rendered view do not establish sufficiency
or prove runtime correctness. [Check](../CR-Process.md#check) reads the
issue and the model it names before coding; compiler and executable functional tests check
the resulting implementation.
The adopting project records its scope, readiness evidence and validation commands in
its own binding, rather than embedding project details in this reusable chapter.

## Models, architecture and views

The model represents the functional contract.
Architecture is the model's structure: actual
parts, their responsibilities, deployment, interfaces and connections. Behavior, states,
data, constraints and verification complete the contract as its scope requires.

A view selects existing model elements for human inspection. It MUST NOT create a
second deployment or supply connections, identity or ownership missing from the model.
Use an interconnection view for parts, ports and connections; use other views only when
they answer a concrete review question. Views are not additional functional inputs
required by an implementation agent. If a viewer misrepresents a valid model, repair
the viewer; do not change the functional contract merely to obtain a pleasing diagram.

Attributes MUST remain semantic model features even when a view presents them compactly.
A view MAY use attribute compartments, type references or an inspector instead of a
separate box for each field. Display labels MUST NOT substitute for missing attributes,
types or ownership. See [OMG SysML 2.0 Language](https://www.omg.org/spec/SysML/2.0/Language/PDF),
§7.26.5, for compartments as views of existing model elements.

## Organize a model for navigation and reuse

- Keep one top-level package and one coherent purpose per file. Choose a consistent
  package/path convention and a root that reaches the selected packages.
- Keep what a reader needs together: the requirements, behaviour and verification of one
  function of one part read as one slice. A file is divided by part and function, not by
  kind of element. Small examples need no empty tree.
- Reusable functional domain/language/platform definitions are independent of project models.
  A project may use reusable definitions; reusable material MUST NOT depend on that
  project's names, values, infrastructure or requirements.
- Import only what the project uses. Model third-party products through their interfaces.
- Separate explanations/rationale from the normative model when needed. Version control
  owns change history; model elements describe the declared current or target design.
- Explicitly distinguish implemented facts, planned requirements and unimplemented
  verification. A target component or allocation is not an executable implementation.

These are modeling conventions, not a requirement to migrate an unrelated project's
existing folders or to create one file per concept.

## Keep stable identities and traceability

Existing requirement, clause, function and test IDs MUST be preserved. A model short name
or declared trace metadata can carry an established ID; adopting SysML MUST NOT renumber
an existing project or change its tests' identities. New IDs follow the project scheme,
remain unique in their declared scope and are not reused for different meanings.

A covered functional slice SHOULD make this chain explicit:

**actor goal / use case → function → owned requirement → responsible component →
verification case → executable test or declared review method**

Each requirement has an identifiable owner. Functions are decomposed only far enough
to define their required behavior and tests. Use cases compose actor goals/functions;
they do not become a second implementation.

Definitions describe reusable types; usages represent actual elements. A `satisfy` or
`allocate` relationship names the appropriate usage rather than substituting its
definition. A function definition can have a corresponding named action usage to make
those relationships unambiguous. Reference actual implementation paths only when they
exist; target allocations are labeled as planned.

A `verify` relationship states what a case addresses. It does not mean the case ran or
passed. Test results remain dated execution evidence in the project's existing record
system, not verdicts invented in the model.

## Write requirements and behavior precisely

A requirement carries one concise normative statement using the project's MUST/SHOULD/MAY
vocabulary. Reference shared facts rather than duplicating their definitions. Prose
explains the rule; formal relationships express ownership and trace links.

Represent interfaces with typed ports/items and connections where useful. Keep transport,
payload, responsibility and authority distinct. Components sharing a physical connection
can still expose independent logical interfaces and failure states.

Connect actual part/port usages and retain deployment and selection identity through
their decomposition. State producer/consumer directions and semantic item types;
an empty port type name alone does not describe an exchange. Treat connections and
identity bindings as different relationships. Shared resources need an explicit common
authority, and population connections need an explicit selection/association policy.

A logical or deployment container MAY connect directly through its contained functional
parts' ports when it has no interface contract of its own. Authors SHOULD add container
ports and delegation when the container exposes an actual boundary contract; containment
alone does not require redundant forwarding ports. The model MUST preserve the actual
endpoint ownership and deployment context in either case.

For example, a network camera can expose a video interface carrying frames separately
from a control interface carrying pan commands and camera status. A shared network
transport does not merge those responsibilities: video may remain available when a
control capability is unsupported, and each interface reports its own failure outcome.

Values that are formalized have explicit types and units. Use the selected tool's
supported quantity/unit libraries or an explicitly defined domain unit; do not invent
a library symbol or claim dimensional validation for an untyped string. Unsettled values
stay visibly unresolved until the implementing CR settles them.

### Select constructs by meaning

The construct distinctions follow [OMG SysML 2.0 Language](https://www.omg.org/spec/SysML/2.0/Language/PDF),
§§7.7 (attributes), 7.11 (parts), 7.17 (actions), 7.18 (states) and 7.20 (constraints).
Apply them to the contract's meaning before choosing a diagram or implementation layout:

| Meaning | Modeling guidance |
|---|---|
| Component with its own identity, responsibilities or interactions | Use a part, at the appropriate logical or physical abstraction. |
| Scalar or structured data | Use typed attributes; nested data does not by itself create component identity. Memory contents are data; a physical memory module can be a part. |
| Current observable property | Use an attribute owned by the relevant occurrence, such as a part. Its value can vary during that owner's lifetime. |
| Supported domain and access capability | Describe applicable ranges, choices and read/write support with typed data and constraints. These describe what is supported, rather than another current value. |
| Operation | Use an action with inputs, effects, outputs and failure outcomes. An availability attribute can describe support for an operation; a Boolean named after the operation does not define its behavior. |
| State-based behavior | Use states and transitions for behavior activated by events and conditions, including entry/do/exit actions where relevant. |

Structured attribute values have data semantics. Their nested features are referential;
authors MUST NOT imply independently owned components merely by grouping fields. SysML
data values themselves do not change, but an attribute of an occurrence can take different
values over time (§7.7). The ordinary phrase "current state" can therefore mean the
current attribute values. Authors MUST distinguish this meaning from a SysML `state`
describing behavior (§7.18). Numeric values and guards can participate in state-based
behavior; a separate behavioral state for each numeric value needs a behavioral purpose.

### Keep capability, observation and request semantics distinct

For each modeled current observable property and context, the model MUST identify one
attribute and its owner. Other representations, such as an action input, cached observation or
history, MUST have an explicit distinct role and synchronization semantics. A supported
domain MUST NOT introduce a second current value of that property.

Capability descriptions and observations SHOULD use distinct domain types where their
meanings differ: a range or catalogue entry is different data from a runtime reading.
The contract MUST identify their source, ownership, applicability and update lifetime.
Capabilities can depend on model, firmware, installed options or operating context;
they are not universally immutable. Using SysML attributes for both kinds of data does
not require identical code types, storage, update policy or mutability.

- Capability data MUST preserve correlated choices and their context, such as a range
  applicable only to a selected mode or channel. Independent lists MUST NOT imply that
  every combination is supported. Applicable constraints express these relationships.
- The contract MUST distinguish supported, unsupported and unknown facts, including
  read-only versus writable access. Unknown limits or choices stay unknown; authors
  MUST NOT invent bounds, defaults or observations to complete a table.
- Defaults, requested inputs, applied effects and confirmed observations MUST have
  distinct meanings. A request is an action input for that operation; persistent desired
  data requires its own contract meaning and lifetime.
- Set and query actions MUST define their effects, observation source, confirmation and
  failure policy. Sending a request alone does not establish the confirmed current value;
  the contract determines what acknowledgement or observation establishes confirmation.

For example, each output of a power supply has one observable `voltage`. Its supported
range describes the domain and constrains applicable requests; it is not another current
voltage. `setVoltage` takes a temporary `requestedVoltage` input and changes the
physical supply, with the observable attribute reflecting the value confirmed under the
declared policy. `queryVoltage` retrieves or refreshes that attribute. These are two
actions concerning the same property. Their errors and any stale or unknown observation
status remain explicit; a failed set does not make its requested value an observation.

### Formalize behavior incrementally

Formal behavior is incremental, one function at a time:
1. Model its inputs, outputs, capabilities and named error outcomes.
2. Express guard order or derivations with appropriate calculations.
3. Add assumptions, required outcomes and constraints to the existing requirement;
   do not introduce a second requirement for the same meaning.
4. Represent meaningful state transitions and bounds.
5. Add independent positive, negative and boundary vectors.

Editorial judgments and third-party internals do not need artificial calculations.
Constraints checked for names/types are not automatically executed or mathematically
proved. Keep the distinction visible in validation evidence.

## Describe verification independently of the implementation

A verification definition identifies its subject and the requirements it verifies. Its
case description includes:
- stable case ID and purpose;
- setup/inputs and action;
- expected observation and independent oracle;
- test method and automated/manual status;
- the project's level in plain words and exact execution location;
- external effects/consent where relevant;
- the executable test binding, or explicit planned/unimplemented status.

Data-driven cases can share a verification definition with explicit case-specific vectors.
Include boundaries and failure outcomes; neither a self-generated expected result nor an
unevaluated model verdict is independent evidence.

## What belongs in the model

The model holds what is promised; the code holds how. A fact belongs in the model when two
correct implementations could not differ on it without someone outside the part noticing:
a user, another part, a peer system, or a test at the part boundary. The model describes a
part by its interfaces and its observable behaviour; internal state, data structures and
algorithms are code, unless the algorithm itself is the promise. Where a standard or a
reference implementation defines a behaviour, the model names that source and its version
and states only the product's own choices and deliberate differences.

The model has a formal skeleton and prose below it. The skeleton is parts and connections,
typed data and items, states, events and transitions, identities, and the links between
requirement, part and test. What an action does and what a rule says is prose in the
element that owns it, one sentence per effect or rule; it is formalised further only where
a tool or a test needs it. Everything below the prose is code. Data that several functions
share is skeleton and is defined once, with the part that holds it.

The model and the code are bound in both directions by stable names, never line numbers:
a part or a function of a part names the module that implements it; each promise has a
verification case bound to a test at the part boundary; the tests of the inside of a part
are named as a set on the part; code and contract tests carry a tag naming the requirement
they implement or prove. A detail test whose failure would be noticed outside the part shows a
missing promise.

## Marking what the model does not say

Something observable that the model does not state, two statements that disagree, and a
choice left to the coder on purpose are marked inside the element with typed metadata, so
that the validator rejects a misspelt mark and a tool lists the marks without reading text:

```sysml
part def Controller {
    @NotStated { what = "how the controller obtains the tank level"; }
}
```

The [shared model notes](../../templates/sysml/model-notes.sysml) define `NotStated`,
`Conflict` and `LeftOpen`, and `FollowsSource` and `DiffersFromSource` for a rule taken
from an external reference. The [shared model bindings](../../templates/sysml/model-bindings.sysml)
define `Status` and `Automation` for what the model declares, and `ImplementedIn`,
`TestedBy` and `DetailTests` for the references to code and tests. A project includes
the files it uses in its model. A binding whose tools read status and references
in another form keeps that form until the tools are changed.

A gap is never filled with a plausible value. Silence about the inside of a part is not a
gap. An edge case (the border of a declared set) is sorted by its consequence first and its
likelihood second. A harmful one, however rare, and a regular one that is noticed
outside the part are promises with a case condition that shows them. The set's stated
default, chosen to be the safe behaviour, covers the rest of what matters; a rare and
harmless one belongs to the code and its detail tests; an undecided one is marked.

## Derived documents and restructurings

A functional description written from the model for a reader is a view
([fsd-from-model](../../skills/fsd-from-model/SKILL.md)): it names its model files and
revision, adds no fact and is written again when needed. Moving model text, code or tests
without changing behaviour follows [restructuring](../../skills/restructuring/SKILL.md);
rewording, splitting or re-linking a requirement is a change of the contract.

## Worked example

The [neutral authoring example](../../templates/sysml/authoring-example.sysml) shows one
requirement per part with its subject and satisfier, a value defined once and referred to,
a verification case with its bound test and lettered conditions, and a mark for something
not stated. A declaration
executes nothing and computes no verdict. The selected project validator checks this kind
of example together with its matching language/library environment. The writing rules, by
kind of content, are in the [authoring skill](../../skills/sysml-authoring/SKILL.md).

## 2. Validate at the correct level

The project retains its approved test levels and execution policy. SysML adoption MUST
NOT silently reclassify live tests, grant consent or replace registry-based selection
with a model-driven gate that has not been implemented and reviewed.

| Check | Can establish | Cannot establish |
|---|---|---|
| Freshness/trace check | Covered source IDs, required links, scope and recorded source/model synchronization | Full SysML syntax, type correctness or equivalent behavior |
| Lightweight profile/lint check | The documented subset/conventions it actually implements | General SysML v2 language acceptance or proof |
| Pinned full SysML implementation | Parsing, resolution and semantic diagnostics supported by that exact tool/library version | Execution of tests or automatic proof of modeled constraints |
| Executable tests/review | Observed program results or stated review findings | Unmeasured hardware/platform behavior |

The project MUST record the language/specification version, validator distribution,
library version, invocation and validation scope. Pin and verify downloaded tools; tool
availability and permissions are project environment facts, not model assertions.

When semantic validation is a required check, a missing tool/library, unresolved import,
invalid model or failed invocation MUST fail it. A lint-only result MUST be reported as
lint-only, and skipped/unavailable checks MUST NOT be called semantic PASS. Inspect the
validator's diagnostics, not only whether its launcher returned zero.

Validation runs in the project's selected local or hosted execution mode, not automatically
in both. The selected command checks the complete declared model/library set so that
cross-file references are resolved together. Declared exceptions/warnings need review;
missing model files cannot be hidden by an empty successful scan.

No universal parser command is supplied here: the project binding names the actual,
working wrapper for its chosen pinned tool. The OMG reference implementation is one
option; another tool needs a documented compatible language/library version and evidence.

## 3. Authoring and change procedure

1. Read the project's scope binding and the affected model slice.
2. Take the meaning from the issue, whose promises and test cases are settled in the
   model's wording ([Define](../CR-Process.md#define)); preserve IDs and
   declared status.
3. Update the model's requirements, structure, behavior and verification links affected
   by the change, including producers and consumers of changed interfaces, together with
   the code ([Implement](../CR-Process.md#implement)): the promises as the issue words them, the structure as built.
4. Update only the derived views or fingerprints declared by the project binding.
5. Run the configured trace/freshness checks and full model validation. Run executable
   tests only where program behavior changed or another required check selects them.
6. Have an independent reviewer assess the touched meaning and trace chain.
7. Before issue closure, confirm the model holds the delivered functionality and durable
   test definitions. Archived specifications are not maintained. The issue retains
   approvals/results; it is not the sole specification.

### Implementation workflow

The changed requirements and their independent verification expectations are defined and
approved in the issue before implementation, in the model's wording. The coder writes them
into the model with the code, and the structure as built. Preserve stable identities,
owners, interfaces, state/error/timing decisions and executable or manual verification
bindings. Verify using the issue's independent expectations; neither implementation nor
generated expected results establish the contract by themselves.

Conflicts, unsupported language constructs and gaps are surfaced explicitly. They are
not repaired by editing a model to bless incorrect code or by weakening a validator; a
promise the issue does not name is not changed in the model.

### Learn from source-to-model differences

A discovered difference triggers correction and prevention. Correct the representation
against the issue and the code; a genuine requirement change needs its own approved
contract update. Record the mismatch and its cause, examine the modeling instructions
and checks that permitted it, and improve the reusable authoring guidance where a gap
is general. Keep project-specific facts and enforcement in the project's binding.

Add a focused regression example or check where it can detect the same class of mistake.
A well-formed model can still have reversed exchange directions or an ordinary connection
where identity requires a binding; negative fixtures should expose such semantic mistakes.
If a clear existing rule already covers the cause, enforce or clarify that rule rather
than multiplying duplicates. Repeat the correspondence review and affected checks before
implementation continues. These HOW lessons remain Markdown and are not product model elements.

## 4. Reference provenance

The [USKA SysML branch](https://github.com/USKAch/uska-webpage/tree/b568183a3ab88d0eca4cdbd3f86d4f34c4de3b3c/sysml)
provides a useful reference for stable identities, requirement/function/component/test
links, root navigation, separate explanations and honest tool limitations. Its checker
describes itself as a profile checker, not a full SysML parser; its full-language evidence
uses a pinned OMG pilot implementation.

Its model-primary policy, identifier migration, website-specific model and model-driven
test selection are project decisions. This reusable chapter adopts the general authoring
discipline; each adopting project declares its own model scope.

External language authority: [OMG SysML 2.0](https://www.omg.org/spec/SysML/2.0).
Tool reference: [OMG SysML v2 Pilot Implementation](https://github.com/Systems-Modeling/SysML-v2-Pilot-Implementation).

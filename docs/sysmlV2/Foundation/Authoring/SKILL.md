---
name: sysml-authoring
description: Write or change textual SysML v2 in the product contract so that each fact is stated once, owned by one part and connected by model relationships. Use this skill for every edit of a .sysml file, however small, such as adding or changing a requirement, clause, promise or test case, writing an issue's Functionality and Test cases into the model, modelling parts, interfaces, behaviour, data formats or screens, moving, splitting or cleaning model text, and reconciling the model with the code. Also use it when asked how something should be written in the model. Use conformance-review instead for an independent implementation-readiness review.
---

# SysML authoring

The rules are the [core SysML documentation standard](../../docs/standards/sysml-v2.md);
this skill applies them at the point of writing. Resolve these links from this canonical
skill's directory, even when a host entrypoint forwards here. The project's binding owns
the actual files, identity scheme, part names, domain facts, validator pins and commands,
and it wins over these rules where it fixes a form: its identity scheme, its status names
and the way it records links (for example a reciprocal `dependency` beside every `verify`).

## What the model is for

Every rule serves one of these; where a rule does not decide a case, they do.

- **One fact, one place.** Nothing is stated twice.
- **Connections are recorded.** Requirement, owning part, behaviour, data and test are
  joined by relationships that a tool and a reader can follow.
- **It can be coded and tested from.** A coder and a tester need nothing but the issue and
  the model.
- **A change is local.** Changing one function edits one area of the model.
- **Readable in slices.** One function's requirements, behaviour and tests read together,
  as a specification, without the rest of the model.
- **Current state and honest status.** The model says what holds now and what is built,
  planned or only defined; it never says that a test ran.

When readable and formal pull apart, readable wins: formalise where a definition or a
test needs it. Keep the change in proportion to the issue.

## What belongs in the model

The model holds what is promised; the code holds how. One question decides where a fact
belongs: **could two correct implementations differ on it without anyone outside the part
noticing?** If it would be noticed (by a user, another part, a peer system, a test at the
part boundary) it is a promise and belongs in the model. If not, it is the coder's choice
and belongs in the code, with a comment where it needs explaining. A model that also
holds the how duplicates the code and is too heavy to keep true.

The model has three levels, and each fact goes to the highest one that can hold it:

| Level | Holds | Written as |
|---|---|---|
| Skeleton | parts and connections, typed data and items, states, events and transitions, identities, and the links between requirement, part and test | formal elements and relationships |
| Prose | what an action does and what a rule says | sentences in the element that owns them, one per effect or rule |
| Code | everything below | the code, its comments and its detail tests |

Prose is the lowest level of the model, not a fault in it. A sentence is formalised
further only where a tool or a test needs it. What must never be prose is the skeleton: a
sentence that introduces a state, an event, a data value or a connection hides structure.

- **Stop at the part boundary.** Describe a part by its interfaces and its observable
  behaviour. Internal state, data structures and algorithms are code, unless the algorithm
  itself is the promise.
- **Refer to an external definition; do not copy it.** Where a standard or a reference
  implementation defines the behaviour, name the source and its version and state only the
  product's own choices and deliberate differences.
- **Silence about the inside of a part is not a gap.** Only something observable and
  undecided needs a marker (rule 8).
- **Point to the code and to the detail tests** (rule 11), so that the model can stay
  short about details and still lead to them.

## Before writing: find the home

1. **Find the owning part.** The architecture's parts stay intact: each promise belongs
   to one part, and no part is merged, split or bypassed to make a promise fit. A promise
   that needs two parts is each part's own promise plus the interface between them. An
   existing requirement that mixes the scope with something outside it stays where it
   is, is referred to, and is listed in the report; it is divided when its other half
   is worked on.
2. **Search before adding.** Look for the fact by its terms and its values. If it exists,
   change it there and refer to it; a second wording of the same rule is a defect.
3. **Read the slice:** the owning part with its ports, the items they carry and the parts
   on the other end; the requirements and the behaviour and data they refer to; the cases
   that verify them. Take the meaning from the issue; surface a conflict between the issue
   and the model before changing meaning.

## Core rules

These hold for every kind of content. Each names the harm it prevents, because the harm
decides the cases the rule does not spell out. The
[writing example](../../templates/sysml/authoring-example.sysml) shows them in one small model.

1. **State it once and refer to it.** A value, a type, a format, an interface or a rule has
   one definition; everything else names it. Two wordings of one thing drift apart, and the
   reader cannot tell which one holds.
2. **Write a connection as a relationship:** `subject`, `satisfy`, `verify`, a typed
   reference, a specialization or redefinition, `connect`, `bind`, or a dependency. Who
   owns a promise, what satisfies it, what verifies it and which defined value a rule uses
   are relationships, since no validator resolves a name in a sentence and no tool follows
   it. A typed feature, a parameter or a transition that uses the element is such a
   relationship already. Beyond that a sentence may name an element; do not add a
   dependency only so that a name has one, because a link without a role tells a reader
   nothing.
3. **Give every element its owner.** A requirement names its part as `subject` and a usage
   of that part satisfies it. A behaviour, a calculation or a data definition belongs to
   the definition of the part that performs or holds it. Where the subject is outside the
   product, the satisfier is the product part that handles it. Data follows its users:
   data one function uses is defined with that function; data several functions of a part
   share is defined once with the part, as typed data with one sentence per feature, and
   each function refers to it. "With the part" is one named place per part (its own
   package of shared data), also where the part's definition lies elsewhere; data that
   crosses a connection belongs to the interface.
   Shared data is skeleton and is never left to prose, because the other functions must
   be able to name it.
4. **Describe the present state.** Leave out dates, issue numbers, decision lists, and
   words that tell a history ("replaces", "formerly", "existing", "new", "remains"). Version
   control and the issue keep the history; in the model it hides the rule.
5. **Type every value:** a type and, where it has one, a unit or an external encoding.
   `String` is for text. A closed set of values is an enumeration, also when it hides in
   prose or in a set of Boolean flags. A property of each member of such a set (a code,
   a colour, a default) is a typed feature when another element or a test has to name
   it, and one sentence on the member otherwise.
6. **Write a promise as a requirement and a rule as an element.** An attribute fixed to
   `true` and asserted in a constraint is a promise written as data: make it a requirement.
   A rule is one sentence in the element that owns it; it gets a formal body only where
   the formula itself is the promise or a tool evaluates it.
7. **Be complete over every declared set, by a default.** For a set the model declares
   (state and event, request and status, input and effect, a range, a length, the
   fields of a record), say once what holds for every
   member it does not list. One sentence removes the doubt whether a case was forgotten or
   means "nothing happens"; a line for every combination is not asked for.

   **Edge cases** are the points on the border of a declared set: the ends of a range,
   the empty and the full collection, the first and the last state, two events at once,
   an input that is missing, late, repeated, oversize or of another version. Go through the borders of each set the
   change declares. Where two sets meet (a state and an event, a setting and an input),
   the case belongs to the element that reacts. Sort each case by two questions, the
   consequence first:

   - *What does it cost if it is handled wrongly?* Harm outside the part (a wrong action
     on the outside world, wrong or lost data, a stop) or only a blemish.
   - *Can it occur in operation?* Regularly, rarely, or only through a fault.

   | The edge case | Its home |
   |---|---|
   | Cannot occur, because the model's types or structure exclude it | None. Prefer making a case impossible over describing it. |
   | Harmful, however rare | A promise: the behaviour at the border, stated on the reacting element, and a lettered condition with its expected value in a verification case. |
   | Regular, and someone outside the part would act differently because of it | The same. |
   | Covered by the stated default | Nothing more. Choose the default so that it is the safe behaviour; that makes most rare cases cost nothing. |
   | Rare and harmless | The coder's: the code and its detail tests. |
   | Observable and undecided | A marker (rule 8). |

   Likelihood never removes a harmful case, and it is an estimate: call a case rare only
   when it needs a fault or an unusual coincidence. Deliver the list of the cases with
   their homes in the report of the change, so that a reviewer can tell a considered case
   from a forgotten one; the list is not kept in the model.
8. **Mark what the model does not say,** with the metadata of the shared
   [model notes](../../templates/sysml/model-notes.sysml), inside the element it concerns.
   Import the definitions by name where a wildcard would hide a name of the project.
   A marker is typed, so the validator rejects a misspelt one and a tool lists them
   without reading text:

   ```sysml
   part def Controller {
       @NotStated { what = "how the controller obtains the tank level"; }
   }
   attribute def TankLimits {
       attribute fullPercent : Integer = 95 {
           @Conflict { what = "95 here, about 90 in PanelTexts::fullHint"; }
       }
   }
   action def ReportOnSelection {
       @LeftOpen { what = "how a non-finite input is rejected, if the result stays in range"; }
   }
   ```

   `NotStated` is a fact a coder needs and the model lacks; it needs a decision.
   `Conflict` is two statements that disagree, in the model or between the model, the
   code and a named reference; name both. `LeftOpen` is a choice left to the coder on
   purpose, with the limit it must respect. Never fill a gap with a plausible value: an
   invented value reads like a decision. A marker about two elements stands beside them
   and names both: `metadata limitConflict : Conflict about A, B { what = "..."; }`.
   Where a rule follows an external reference, mark
   it `@FollowsSource`, and a deliberate difference from it `@DiffersFromSource`, so that
   a gap filled from the reference and an intended deviation never look alike.
9. **Keep identities stable.** An existing identity keeps its meaning and is never reused.
   Splitting a requirement keeps the old identity on the part that keeps its core meaning;
   new ones follow the project's scheme, and the report names every new identity it needs.
   Names are identities too: code and tests cite elements by name, so an element keeps
   its name where it can, and the report lists every renamed or re-packaged element
   with the code that cites it.
   A retired identity stays listed as retired, in the present tense, where the binding
   keeps such a list; that is a fact about the identity, not history. A verification case
   that shows nothing at a part boundary retires into the detail tests of its part
   ([requirements-and-cases](references/requirements-and-cases.md) rule 10).
   Write an identity in the form the binding's tools read; the example shows the
   language's short-name form.
10. **Wrap lines at about 100 characters,** so that a diff shows what changed. A long
    sentence is split with `+`. A string a tool reads as one value (a path, a test name)
    is not split: break the line before it.
11. **Bind the model to the code, in both directions, by stable names.** The shared
    [model bindings](../../templates/sysml/model-bindings.sysml) give the forms
    `@ImplementedIn`, `@TestedBy`, `@DetailTests`, `@Status` and
    `@Automation`; a binding whose tools read another form keeps that form until they are
    changed.
    - *Part to code:* the part, or the function of a part, names the module that
      implements it, once. A requirement inherits that and names a module only when it
      differs.
    - *Promise to test:* each promise has at least one verification case, bound to the
      test that shows it at the part boundary (a contract test). A value the model holds
      as data is read from the model by that test, not written again; how is the
      binding's.
    - *Part to detail tests:* the tests of the inside of a part, where it has any, are
      named as a set on the part (the test module and what it covers), not one case each.
    - *Code to model:* a module and a contract test carry a tag naming the requirement
      they implement or prove, in the form the binding gives; a detail test carries none.

    Name a module, a function or a test, never a line number. A detail test whose failure
    would be noticed outside the part shows a missing promise: add the requirement and
    make it a contract test.

## Rules by kind of content

Read the reference for each kind the change touches; most changes touch one or two.

| The change concerns | Read |
|---|---|
| A requirement, clause or verification case | [requirements-and-cases](references/requirements-and-cases.md) |
| Parts, ports, items, connections | [structure-and-interfaces](references/structure-and-interfaces.md) |
| An action sequence, a state machine, a calculation | [behaviour](references/behaviour.md) |
| A message, record, file or wire format, a mapping to external codes | [data-and-formats](references/data-and-formats.md) |
| What a screen shows and how an operator acts on it | [user-interface](references/user-interface.md) |

## Check before returning

Run over the model files the change touched, and repair every hit the change added:

- History: `grep -nE "20[0-9]{2}-[0-9]{2}-[0-9]{2}|#[0-9]+" <files>`, and read the hits for
  "replaces", "formerly", "existing", "remains".
- Long lines: `grep -nE ".{101,}" <files>`
- Then read each changed element once more:
  - Is each fact defined once, and named everywhere else?
  - Is every owner, satisfier, verifier and used value a relationship, and is there no
    dependency without a role?
  - Does every requirement have a subject and a satisfier, and every behaviour or data
    definition an owning part?
  - Is every value typed, and every closed set an enumeration?
  - Over each declared set, is every member covered or the default stated, is the
    default the safe behaviour, and is the list of edge cases with their homes in
    the report?
  - Is everything observable that a coder would have to guess marked `@NotStated`,
    `@Conflict` or `@LeftOpen`? Is anything in the change a detail that belongs in the code?
  - Does any sentence introduce a state, an event, a shared value or a connection that
    has no element?
  - Did the change grow the model? A later edit that only rewrites should leave it about
    as large, counted in characters. A first conversion that types what was prose and
    adds owners and links may grow; say in the report what the growth consists of.
  - Does every part name its module and its detail tests, and every promise its test?
  - The checks of each kind reference you read.
  - Did the change stay in one area of the model? If not, say why in the report.

## Procedure

1. Identify the affected slice, its stable identities, current and target status and
   active companions, as "Before writing" describes.
2. Establish ownership and meaning before syntax. Apply the standard's construct,
   capability/observation/request, type/unit and interface rules. Trace changed
   producers, consumers and verification cases together.
3. Reconcile the slice against its declared source and normative references. Before
   coding, an unresolved required decision stays a blocker, while a declared
   implementation choice can remain open. [Check](../../docs/CR-Process.md#check)
   reads this; a [model-readiness review](../conformance-review/SKILL.md#model-readiness-mode)
   is held on request.
4. Write by the rules above and run the check before returning.
5. Run the binding's trace and complete model validation commands. Inspect the
   diagnostics and report the actual check scope. An unavailable validator is
   outstanding; neither syntax acceptance nor a verification declaration is execution.
   Keep existing test selection, execution placement and consent policy.
6. Reconcile delivered functionality and durable case definitions in the canonical
   contract; record review and execution evidence on the issue. Report every marker added
   under rule 8. A mismatch prompts correction against the issue and the code, and a
   reusable improvement of these rules only when its cause generalizes.

## Source-fidelity examples

Preserve source meaning before choosing convenient model types. A source selector's
choices are catalogue values; a frequency measurement carries a frequency unit such as
Hz. A Boolean status is not a numeric measurement, and an implementation's storage type
alone establishes neither meaning. Keep capability, request and observation roles distinct.

When reconciling text such as `label = "mode; ready"`, preserve the complete quoted
value; a delimiter inside the string does not end the assignment. Check nested features
in the declared slice as well as top-level identities. Actual source values and mappings
belong to the project's model and binding.

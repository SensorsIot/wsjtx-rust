---
name: fsd-from-model
description: Write a readable functional specification (FSD) for one part, function, interface, protocol or screen as a derived view of the SysML model, for a person to read and assess. Use whenever someone asks for an FSD, a functional description, a specification document, an interface or protocol description, "explain this part of the model in plain text", or a document to review what something does; also to test whether a model slice is complete enough to document. The model stays the contract; this never creates a second specification.
---

# FSD from the model

An FSD written here is a **view**: a document a person can read from top to bottom,
produced from the model at one revision. The model is the product contract
([SysML standard](../../docs/standards/sysml-v2.md), "Models, architecture and views"); the
FSD adds no fact, decides nothing and is never an input for coding or for a later FSD. It
is written again from the model when it is needed again, not maintained. Say so in its
header, with the model files and the revision it was written from.

The second use is as a test of the model. Whatever you cannot write without guessing is a
gap in the model, and the list of those gaps is as valuable as the document. Tables do
this work: a cell you cannot fill from a model element is a finding that prose would hide.

## Before writing

1. **Fix the scope.** One of:
   - a part with its interfaces and the connections that attach it;
   - one function of a part, or functions of one part that share elements;
   - an interface or protocol, with the part that hosts it;
   - a screen or a region of one, as a function of the part that presents it.

   Name the model elements it covers. A document about several parts becomes a tour of the
   model and helps no one.
2. **Read only the model**, at one revision, and say in the header what you read and what
   you did not. Do not read the code, the issues or an earlier FSD: a sentence taken from
   them would look like a model fact and would hide the gap it fills.
3. **Find the requirements by relationship,** in this order: a `subject` that is the part;
   a `satisfy` by the part or its behaviour; a dependency between the requirement and an
   element in scope. For a function of a part, keep of the part's requirements those
   declared with the function or linked to one of its elements. A parent requirement is
   named beside its children and not treated as in scope. Requirements of the owner or of
   the other end of a connection that speak about the scope only in their text are used
   and listed as weak links; finding them takes a text search of the model for the
   scope's terms, which is expected; where the search gives many, list their identities
   and use only those that state something the scope does not. The verification cases are those whose objective holds a
   `verify` of these requirements; cases that verify only a parent are listed apart, by
   identity only.
4. **Follow relationships, not names in comments.** What is connected only by a name in doc
   text may be used, and is listed as a weak link.
5. **When files disagree** (a slice under review against the rest of the model), the
   element named in the scope wins for the document and the disagreement is listed. An
   empty stub never wins over a full element.

## Structure

Use these sections, in this order. Sections 2 to 5, or their subsections where a section
covers several groups, start with a line naming the model elements they were written
from. Where every row of a table comes from a different element, add an element column
instead. A section with nothing to say keeps its heading and one sentence. A fact is
written in one section and referred to from the others.

1. **Terms.** Only the terms this document uses, in the domain's words, each with its
   element. Where one word has two meanings in the model, give each meaning its own term
   here. A term the model uses without an element is listed as such.
2. **Place in the system.**
   - *Position:* the path of part usages from the top part down. For a function or an
     interface, the position of the part that hosts it. Where another path leads to the
     same part (a `satisfy`, a reference through a selection), give both.
   - *Neighbours:* one row per connection and direction: neighbour, connection, item.
     Resolve conjugated ports before writing a direction. Include connections declared in
     a separate part that refers to this one; search for usages that reference the part.
   - *Not connected:* the parts this part has no connection to, taken at the level where
     its connections are made (climb past owners that are mere containers), grouped by
     kind, each group with the one consequence that follows from the absence alone. An
     absent connection is a guarantee: a part
     without a connection to a resource cannot use it. Bindings and subsetting that
     restrict what a reference may select are guarantees of the same weight.
   - *For an interface:* the neighbours are the far end of the interface and those
     connections of the hosting part that deliver what the interface uses. The host's
     other connections are left out.
   - *For a screen:* a table of each thing shown and each request sent against the item
     that carries it; an empty cell is a finding. Controls elsewhere on the screen that
     drive the scope are named in section 7.
   - *Limit:* where the model names a neighbour but not the items exchanged, or the items
     are empty, say that; and where what the scope shows or uses has no item that delivers
     it.
3. **Purpose and requirements.** One or two sentences that summarise the requirements
   listed below and nothing else; for a part outside the product, what the product must
   keep true about it. Then the requirements by identity, in a table. A status the model
   declares may be shown, labelled as the model's declaration and not a test result.
4. **Data and rules.** By content, see "Tables by kind".
5. **Behaviour.** By content, see "Tables by kind". State the default for unlisted
   combinations in one bold sentence. What the function must leave alone is already in
   sections 2 and 3; refer to it. The model's prose inside an action or a rule is
   rendered as it stands, in the domain's words; it is model content, not a gap.
6. **Implemented in and tested by.** The module the model binds the part or function to,
   further modules its requirements name, and the set of detail tests, as names only. The code itself is not read. Where
   the model has no such binding, say so.
7. **What it relies on from outside.** Two lists: elements the scope uses and does not
   define (other packages, stubs), one row each with what is needed from it; and things
   named in text with no element behind the name.
8. **Differences from a named reference,** as one table: topic, reference, this product,
   and whether the model records the difference as deliberate or as an unresolved
   conflict. A reader assesses them together, so both kinds stand here and section 10
   refers to them. Name the reference and its version once.
9. **Verification.** The cases of the requirements above: identity, which other
   requirements each also verifies, what it shows that bears on this scope in one or two
   lines, and what the case declares about its level, location, automation and bound
   test. Its steps are not copied. Then the requirements of section 3 that no case
   verifies. Never state or imply that a case ran or passed.
10. **Open points, gaps and disagreements.** Three lists, kept apart:
   - *Marked by the model:* its `NotStated`, `Conflict` and `LeftOpen` markers and what
     it declares outside the scope. Give each marker's substance in full, also where it
     speaks of the code or of a reference; leave out only file and function names.
   - *Gaps:* what you could not write about something observable. What the model leaves
     to the code (the inside of a part) is not a gap. For each: the element, what is
     missing, whether it is missing from the model or only from the files you read, and either what you
     assumed or that you repeated an undefined term. Mark in place every sentence that
     rests on an assumption.
   - *Disagreements and observations:* two elements that contradict each other, a
     description that disagrees with its body, a word used with two meanings, an element
     nothing refers to, a weak link, and the findings of the checks below.

## Tables by kind

Where the model leaves a format to an external reference, that is one row in section 7
and not a gap: write no empty table for what the reference defines, and use the
reference's own names for its fields and messages.

Use the ones the scope holds. They belong in section 4 unless marked for section 5.

**Structure and interfaces**
- Per interface: item, type, direction from this part's side, and bindings on the port.
- Per request and reply: which reply answers which request, what each carries, what is
  optional.
- The part's own data: feature, type, how many, and what absence and "many" mean.

**Data and external formats**
- Encodings: each primitive with width, sign, byte order, length prefix, null and empty.
- Per message or record: position, field, type, fixed value or source. Flatten inherited
  and redefined fields into wire order.
- Mappings: model value against external code, with the codes deliberately unused.
- Limits and sizes, with the behaviour at each limit.
- Per request: method or trigger, preconditions, content, success answer, and each
  refusal with its condition, order and content.
- Acceptance of input: a numbered list of conditions and the fate of everything else.
- For a protocol: which message is sent on which occasion, and the reaction to each
  kind of received message.

**Behaviour** (section 5)
- A sequence of actions: steps in order with inputs, outputs and failure outcomes.
- A state machine: states and what each does; events and when each is raised; reactions,
  one row per event and guard against one column per state, a family of like transitions
  as one row with its mapping; effects with their steps in order.
- A calculation: render its body as a table of cases and check that its description
  agrees. One that has only sentences is rendered from them; that is not a finding.
- Rules held as one sentence per member of a set become one table row per member.
  Turning the model's sentences into rows is rendering, not interpretation, as long as
  no row says more than its sentence. Do the same for a constraint and for enumeration values against their text.
- Timing that is neither a state nor a format: a table of what happens how often.

**User interface** (what is shown and its values in section 4, what the operator does
and what changes in section 5; a value stands in one of them only)
- What is shown in each state of the data: loading, empty, partial, stale, failed.
- Appearance rules as a decision table: condition, what it looks like, which wins.
- An input's effect by situation, where the same input does different things.
- Arrangement: region, position, content, and how it scrolls or resizes.
- Inputs: one row per pointer action, key and touch action with its effect.
- Controls against effects, both ways.
- Each operator-set value: default, where it is held, what resets it, what it survives.
- What is reported to assistive technology per control.
- Conditions (sizes, zoom) and what changes under them.

## Writing

- **Plain words for a reader who knows the domain and not the model.** Translate element
  names into the domain's words.
- **Tables for anything with two dimensions.** A state machine, a message layout or an
  input mapping written as paragraphs cannot be checked.
- **Present state only.** Dates, issue numbers and history found inside model text are
  left out. References to an external source are left out too, whether in text or in an
  attribute, apart from naming the reference and version in section 8.
- **Examples come from the model.** An example computed from the model's rules is allowed
  when it is labelled as computed and adds no value the model does not hold.
- **Do not repair the model in the document.** Where two elements disagree, show both and
  list the disagreement.
- **Size follows the content.** If the document is long because it covers more than one
  scope, the scope was too wide.

## Before handing it over

- Does the header name the files, the revision and what was not read?
- Can each sentence be traced to a relationship, a typed element or the text of the
  element that owns it?
- Does section 2 answer: where is it, who are its neighbours, what can it not reach? Has
  everything the scope shows or uses an item that delivers it?
- Does the document stay shorter than the scope's own model text? If not, it
  repeats itself or copies where it should summarise.
- Is any word used with two meanings across elements? Separate them in section 1 and do
  not list them again.
- Is each fact, gap and marker written in one section only, and referred to elsewhere?
- By kind:
  - *Structure:* does each connection join a port and its conjugate; has every reply a
    request; do the "how many" of a feature and of the item that carries it agree; is any
    status or enumeration value undefined?
  - *Data:* has every field a type and a source; every enumeration literal a use; every
    error a condition; every limit a behaviour at the limit; every optional an absent
    form?
  - *Behaviour:* can each event occur in the state that has a transition for it; has
    every event something that raises it and a transition that accepts it; has every
    calculation input a source; does a guard repeat what its event guarantees; does a
    calculation cover its boundary cases; does what each verification case expects agree
    with the behaviour tables?
  - *User interface:* has every control an effect and every effect a control; every
    pointer action a keyboard equivalent; is the degenerate size stated?
- Is every assumption marked in place and listed?
- The three lists of section 10 are the findings for the model; where the document is
  saved as a file, hand them over on their own as well. A finding that generalises goes to
  [sysml-authoring](../sysml-authoring/SKILL.md): the model is corrected there, never here.
- Where the document cannot be saved as a file, return its complete text.

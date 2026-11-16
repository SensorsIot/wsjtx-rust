---
name: issue-writing
description: Write a change request issue that says exactly where the change fits in the product model and in the code, and what must be added, changed, replaced or removed there. Use whenever an issue is to be created, drafted, completed or rewritten for a project with a SysML model (a new function, a changed behaviour, a removal, a restructuring, a code change that follows a model already written, a finding that becomes an issue), when the operator says "create an issue", "record this", "write this up as a CR", or asks where a new function belongs or what it replaces; also before Define, to bring a recorded issue to the fixed headings. Use it even when the request sounds small: an issue without its place in the model is defined twice.
---

# Issue writing

An issue is the brief for everyone after it: the definer, the checker, the coder, the
reviewer. It is good when someone who reads only the issue can say what will be built,
where it lives, what it replaces and how each case is proven. Most rework on an issue
comes from one gap: it says what is wanted and not where it fits, so the home is found
later, by someone else, differently.

This skill adds that part. The rest is the harness as it stands, and is linked, not
repeated:

- the fixed headings and what each holds: [CR process, The issue and Define](../../docs/CR-Process.md#the-issue);
- when an issue is created at all, duplicates, one change per issue: [Intake](../../docs/CR-Process.md#intake-and-authorization);
- the classes of change and the lifecycle labels: [Classes of change](../../docs/CR-Process.md#classes-of-change);
- the template: `core/templates/github/ISSUE_TEMPLATE/cr.md`;
- where a promise belongs in a model: [sysml-authoring, Before writing: find the home](../sysml-authoring/SKILL.md#before-writing-find-the-home);
- a pure move: [restructuring](../restructuring/SKILL.md).

The project's binding names: the model's root and the document that fixes its tree; the
reference implementation to compare with; the records of decisions already made (handover
lists, part reports, a ledger of identities, where the next free number is found); and how
its tools are run. Read those records before asking anything: a decision already made is
found there.

## The order of work

### 1. Say the change in one sentence

Who gains what, in the domain's words, without a file name. Then list the nouns, verbs
and values of that sentence: these are the search terms for everything below.

If the sentence needs "and also", it is usually two issues. Where the operator decided
the bundle as one thing, write it as one, and put the cut as an open question with a
recommendation (what can land apart, and in which order); do not split a decision on
your own.

The value may be a developer's: for a change of structure that the operator should not
notice, the value is who changes one place instead of several from now on.

### 2. Is an issue needed, and is it a new one?

Search before writing, and write down what you searched:

- the open and the closed issues, by each term (`gh issue list --state all --search "<term>"`);
- the main branch's commits, where a term names something recently changed.

An existing function, setting or content edit that already reaches the goal needs no
issue: say so, with its place. An open issue that asks for exactly this change gets a
comment, not a sibling. An open issue that contradicts the change (it builds what this
one removes) is named under Sequence with what must give way. The result is the
**Duplicate check**: the issues considered, by number, each with why it is not this change.

### 3. Find the home, in the model and in the code

This is the step the issue is for. Read [model-impact](references/model-impact.md) once;
it has the questions that decide a home, the four findings and a worked example.

1. **Search the model for every term and value** of the sentence:
   `python scripts/find_home.py <model root> <term> ... [--show] [--records <dir>] [--tests <dir>]`.
   It lists, for each file, the definitions, clauses and test cases that state a term;
   `--show` prints the lines, `--records` also searches the project's decision records,
   `--tests` lists the test files that carry the identities found. Search the code for
   the same terms.
2. **Sort what you found** into four findings: the promise exists already; a similar
   element exists and is extended; an element says something that the change contradicts
   and is replaced or removed; nothing exists and the element is new.
3. **Name the owning part by the rules, not by where the code is.** One promise belongs
   to one part; what two parts share belongs to their interface; a setting belongs to the
   part that uses it and is stored by the part that stores; a command enters where the
   architecture says commands enter. Where the code keeps the thing somewhere else, the
   issue says so: that difference is part of the work.
4. **Look for what lives in the wrong place.** A new home usually means an old one: the
   same value in a second element, a rule told in another part's text, a file one function
   keeps that now belongs to a store. Each goes into a table as "remove" or "move".
5. **Ask what happens to what is already there.** A change of where something is stored,
   named or keyed raises the question of the data, files and saved values of a system in
   use. If nothing says, it is a promise to add or an open question.
6. **Check the tree.** If the home needs a file, a part or a connection that the tree
   document does not name, that is a decision for the operator: put it under Open
   questions with a recommendation, and do not invent the file.

### 4. Write the impact: two tables

Under **Functionality**, after the `Already covered:` lines and before the promises.

**Model impact**: what the model must gain or lose. One row per element, named by file
and element; "Change" is one of add, change, replace, remove, move (with the target), or
none.

```markdown
| Element | Today | Change | Why |
|---|---|---|---|
| `interfaces/internal/TransmitControl.sysml` `TransmitConfig` | holds the level and the power limit | add: `txCalls`, `tuneSeconds` | a setting is defined with the part that uses it |
| `interfaces/internal/TransmitControl.sysml` `SetWatchdogs` | a set command of transmit | remove | one way for a change of a setting |
| `interfaces/internal/QsoControl.sysml` (not rebuilt) | tells the limits as the contact's | remove, when the contact is rebuilt | the same value in a second place |
```

- A row for a part that is not built or not yet rewritten says so in its element cell and
  says when the change is made. It is exempt from the check that the element exists.
- What a rule decides and the operator did not name is stated as a row, with the rule in
  "Why". It is not an open question.

**Model and code**: what the code must become. This table is the work when the model was
written first, and it is short when model and code change together.

```markdown
| Thing | In the code today (file, function) | Change | Model home |
|---|---|---|---|
| Tx watchdog calls, Tune limit | no file: `Core::new` in `server/src/transmit/service.rs` sets 6 and 90 | kept in the station config | `TransmitConfig::txCalls`, `::tuneSeconds` |
```

Say in one line above the tables which of the three cases holds: the model already states
the change (then "Model impact" lists only what the model still lacks); the model's rules
state it and the element is not written (then the element's rows say where it will be
written, and whether that happens in this issue or before it, under Sequence); or the
model changes with the code.

Then, as lines below the tables and only where they apply:

- **Tree:** a new file, part or connection, or "none".
- **Identities:** clauses and test cases that are new (from which series, and where the
  free number was looked up), reworded, retired or moved.
- **Other parts:** who must give or take something new over which interface.

A row you cannot fill is a finding: either read further or make it an open question. Do
not fill it with a plausible guess; a guessed home reads like a decided one.

### 5. Complete the issue under its headings

Use the template's headings exactly, and for each the rule of the CR process:

- **Problem**: what is wrong or missing, the goal, and the value in one sentence. No
  value, no issue: ask the operator whether it is still wanted.
- **Functionality**: the `Already covered:` lines, the two tables, then one promise per
  line with MUST, SHOULD or MAY, and "What stays as it is".
- **Test cases**: how each promise is proven, with the values that define the expected
  result. Where a value comes from the model and was not re-read in the code, say so.
- **Reading list**: the model files and elements, code files and tests the issue rests on,
  by path and name. The rows of the two tables are its core.
- **Open questions**: each with what the reference implementation does (or that it has no
  such thing) and a recommendation; empty when the issue is ready.
- **Sequence**: what must land first, the issues that contradict or touch it, and model
  work that happens outside this issue.
- **Acceptance**, **Decisions**, **Approval**, **Blast**: as the CR process says. A related
  issue that exists only as a draft is named by its title.
- **Class and labels**: propose the class in the first line of Technical details. An issue
  whose two tables hold only "move" rows is a restructuring; one "add" or "change" makes
  it a product CR, and a pure move inside it can be cut off as a restructuring of its own.
  Label it as the CR process says for a recorded issue.
- **What was not verified** closes Technical details: what was read in part, and which
  expected values rest on the model alone.

### 6. Before it is posted

Read the body alone, as the checker will, and answer two questions in a few lines: what
will be built, and how is each case proven? If either answer needs a file you did not
name, the issue is not ready.

Then check: is every element named in the tables a real element, or marked as not built
(run `find_home.py` on its name)? Does every "remove" name what replaces it, or say that
nothing does? Is each fact stated once? Does the body name no path of your own machine? Is it within the
size the CR process allows for a body (measure it; cut detail into Technical details'
places by name, not by copying)?

Posting sends the text to an outside service. Post when the operator has asked for the
issue; otherwise show the draft and ask.

## What this skill does not do

It writes no model file and no code. The tables say what will change; the model is
changed by [sysml-authoring](../sysml-authoring/SKILL.md) when the issue is built, or
before it where the project writes the contract first.

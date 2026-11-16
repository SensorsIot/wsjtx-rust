# Requirements and verification cases

For a change that adds or alters a requirement, a clause or a verification case. The
[writing example](../../../templates/sysml/authoring-example.sysml) shows the forms.

## Rules

1. **One promise per requirement:** one sentence with the project's MUST, SHOULD or MAY.
   A paragraph cannot be owned by one part, proven by one test or changed without
   touching its neighbours. Values, ranges and sequences stay out of the sentence: they
   live in a typed element, and the sentence names it. The sentence is the promise
   itself in the domain's words (who does what for whom, and when), complete without
   its values; the element it names adds the values and the detail. Never write "as
   element X states": the requirements must read as a specification on their own.
2. **Split where the split buys something.** A list inside a requirement is several
   promises when its members belong to different parts, are shown by different tests or
   change for different reasons. It is one promise when the sentence names an element (a
   state machine, a mapping, a message set) and the list only repeats that element's
   content: then drop the list and name the element. "A different reason" is another
   source of change: another parent requirement, another external reference, a safety
   rule. Every split costs an identity and its links, so do not split a promise that one
   part keeps, one test shows and one reason changes. A statement that is not split off
   becomes a sentence in the element the requirement names. This rule decides before
   rule 1 and rule 4.
3. **A condition that recurs is one element.** Where several requirements hold under the
   same conditions (an operating mode, a screen size), define the conditions once and let
   the requirements name them.
4. **A prohibition is a requirement** when it is a promise of its own ("never transmits
   without a request"). What simply does not happen in the unlisted cases of a behaviour
   is that behaviour's default, stated there once, and not a requirement.
5. **A verification case names what it shows.** Its skeleton is formal: `subject`,
   `verify`, the bound test, level, execution location and automation status. Its content
   is short prose: the setup, then one line per condition with the expected observation.
   Conditions carry stable letters, so that a test's tag can cite one. The expected
   observation is given with the values that define it, independent of the code under
   test, so that a wrong test can be told from the model: one set of values per
   condition, with further vectors in the bound test. A condition that no test shows
   yet is written and marked as planned in its line, so that the gap is visible and the
   case's own status stays true. Where no fitting case exists, a promise may carry
   the note that no test shows it yet; a new case is not created only to hold a gap.
   A case that crosses parts is kept for the interaction
   it proves.
6. **Model the contract tests, refer to the detail tests.** A verification case proves a
   promise at the part boundary. Tests of the inside of a part live with the code and are
   named as a set on the part.
7. **Declare status, never results.** Built, partly built or planned, as the binding
   names them. A bound implementation or test exists; a planned one says so. A statement
   split out of a requirement takes that requirement's status unless the code says
   otherwise.
8. **A requirement inherits from its part** the module that implements it, and names one
   only when it differs.
9. **Splitting needs identities.** When one requirement becomes several, keep the old
   identity, list the new ones the project must allocate, and move each `verify` to the
   requirement its case really shows.
10. **A case of the inside of a part retires into its detail tests.** An existing
    verification case that shows nothing at a part boundary (its failure would not be
    noticed outside the part) leaves the model with its `verify`. Its test stays, keeps
    running and loses the case tag; the part's `@DetailTests` (or the binding's form) names
    the test's file; the case's identity is listed as retired and is never reused. The
    report lists each case examined with its class (contract or detail) and the reason,
    and every requirement the retirement leaves without a case. A retirement is model
    authoring in its own commit, never in the same commit as a move; it may follow the move
    in the same issue.

## The usual mistake

A requirement whose text holds several promises of two parts, values that belong in a
typed element, a connection written as a name in prose, and its own history. Rewritten:
one sentence per promise, its part as subject, each value named and defined once.

## Checks

- Is each requirement one sentence with MUST, SHOULD or MAY?
- Does each have a subject and a satisfier, and at least one case that verifies it? List
  the requirements no case verifies.
- Does each case name its test, and does each of its conditions have a letter and an
  expected observation?
- Does each case show something at a part boundary? A case of the inside retires (rule 10).
- Did a split add an identity that one part keeps, one test shows and one reason
  changes together with another? Then merge it back.
- Can a wrong test be told from the case: does each expected observation carry the
  values that define it?

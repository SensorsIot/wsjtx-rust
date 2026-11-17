# User interface

For a change to what a screen shows and how an operator acts on it.

## Rules

What a screen region shows and accepts is a function of the part that presents it,
written like any other function of a part. What it shows are its inputs, typed by the
items that deliver them; a region is not a part of its own unless the architecture
names it one.

1. **Give an arrangement an ordered element.** Where position or sequence is the fact
   (regions top to bottom, columns left to right, sort keys by priority), list the
   members once: an `ordered` feature, or an enumeration that says once that its order
   of declaration is the order shown.
2. **State the inputs as a complete mapping.** For every key, pointer action, control or
   change of context: its effect, by an enumeration of the inputs and a mapping or a
   stated default. Name which of pointer, keyboard and touch perform each action, or mark
   the missing one.
3. **Every control has an effect and every effect a control.** A control whose effect is
   not stated, and an effect no control reaches, are both `@NotStated`.
4. **Say how long a local choice lives.** For a preference or an adjustment a part holds:
   its default, where it is kept, what resets it, what keeps it, and whether it survives a
   reload or a restart.
5. **Define a condition set once.** The sizes, zoom and text scale under which a rule must
   hold are one typed element, and it says whether they hold together or each alone.
6. **A limit comes with its boundary.** A minimum or maximum states what the bounded
   quantity is measured from, and what is shown when the limits cannot both be met.
7. **A presentation unit is a unit.** Screen pixels, relative sizes, zoom percent and
   device pixel ratio get types like physical units.
8. **What is announced is a promise** where the product decides it: a name, a reported
   value or a focus behaviour that differs from what the platform gives by default, tied
   to the same typed value the screen shows. What the platform does by itself is not
   modelled.
9. **Say where what is shown comes from:** which item on which connection delivers it.
10. **A displayed text is a promise when an operator acts on it or a test asserts it.**
    Such a text is stated once, as data. Every other wording is the coder's.
11. **Something shown that is also a control** (a row that can be selected) is listed
    in the input mapping like a control. A control that can have no effect in a given
    situation says so.

## The usual mistake

A typed definition whose doc block carries twenty promises, beside attributes fixed to
`true`. Rewritten: an ordered element, a mapping of inputs, one sentence per rule,
and one requirement per promise.

## Checks

- Has every control an effect, and every effect a control?
- Has every pointer action a keyboard equivalent, and is touch stated?
- Has every operator-set value its lifetime?
- Is the degenerate case stated (too small for both minimums, minimum above maximum)?
- Is what the function must leave alone written as requirements?
- Borders to walk for edge cases: nothing to show, more than fits, too narrow, the
  largest text scale, data that is stale or not yet there, a redraw during a gesture,
  no pointer or no keyboard, focus lost.

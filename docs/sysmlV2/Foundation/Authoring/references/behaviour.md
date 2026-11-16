# Behaviour

For a change to an action sequence, a state machine or a calculation.

## Rules

1. **Give behaviour that has order, state or a guard its skeleton:** an action with its
   inputs and outputs, a state machine with its states, events and transitions, a
   calculation with its parameters, or a mapping over an enumeration. What the action
   does and what the rule says is prose inside that element, one sentence per effect or
   rule. Nothing is said in both forms.
2. **Place it in the part that performs it:** a feature of that part's definition.
3. **Make a state machine complete.** For every state and event the reader can tell what
   happens: by a transition, or by one stated default for the unlisted combinations.
   Where the same event leads from many states to the same result, use a nested state or
   the default, not a line per state. A state with no way out stops the product there.
4. **Every event that changes the state is a transition,** an operator's action as much
   as a received message. An event described only in the text of the state machine is
   missing from every table built from it. Where one event leads from every state, or
   from every state of a named group, to a state that its content names, always write
   it the short way: the event is defined, and one sentence on it states the mapping
   and the states it does not apply in. A transition per target is not written, and no
   state is introduced only to group them.
5. **Write an effect where it happens:** as a sentence in the action definition that
   performs it, or on the transition that causes it. A condition on an effect is part of
   that sentence. An effect told in a general description of the function has no owner.
6. **Say when each event is raised and by what outside cause,** once, on the event: an
   operator's request, a received item, an outcome from a neighbour, a time. "Raised
   by the part itself" names no cause. A guard does not repeat what the event already
   guarantees.
7. **A calculation needs a body only where the formula is the promise** or a tool
   evaluates it. Otherwise its parameters and one sentence per rule are enough, and an
   internal computation is code and needs no model element. Say where each input comes
   from; where an input is not defined, mark it and do not write a rule around a guess.
8. **Name the external source apart from the rule,** with `@FollowsSource`, and record a
   deliberate difference from it with `@DiffersFromSource`. A rule that follows no source
   needs neither.

9. **Not everything that happens needs a state machine.** Where the content is "on
   this occasion, that result" with no memory between occasions, write a mapping: one
   enumeration of the occasions with one sentence each, and one default.

## The usual mistakes

- A state machine whose transitions are formal while the conditions for raising its
  events and the cases without a transition live in a long comment on the whole machine.
- The opposite: every effect turned into a constraint over optional outputs, which no
  reader follows and the code repeats anyway.

## What the language does not allow

- An enumeration definition cannot hold attributes; specialise an attribute definition.
- `state`, `action`, `item` and other keywords cannot be feature names.
- A transition from a nested state to an outer one is declared at the outer level.
- A guard can read the payload of the event its transition accepts.

## Checks

- Is the default for unlisted states and events stated once?
- Can each event occur in each state that has a transition for it?
- Is every state-changing event a transition, and has every event its raiser?
- Has every effect an owning action or transition?
- Has every calculation input a source?
- Is any word used with two meanings across an event, a guard and a rule?

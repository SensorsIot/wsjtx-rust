# Data and external formats

For a change to a message, a record, a file or wire format, or a mapping to external
codes.

## A format the product follows

A format the product does not own (a standard, a reference implementation) is referred
to, never copied.

1. **Name the source once,** with its version, on the element that stands for the format
   (`@FollowsSource`). The named source at that version is part of what a coder reads;
   the model does not repeat its layouts, numbers or encodings.
2. **Model the product's choices, and only those:** which messages or records it sends
   and accepts, what it puts into each field it has a choice about, what it ignores, and
   what it does with input the source allows and the product does not use.
3. **A field gets a typed feature only when something in the model needs to name it:** a
   rule, a requirement, a verification case or another part. The other fields are covered
   by one sentence ("all other fields as the source defines", or a short list of field
   and fill rule). A feature is typed by its meaning in the product, not by the source's
   wire type.
4. **A deliberate difference from the source is `@DiffersFromSource`,** and stays one
   until a decision revokes it. A difference nobody decided is a `@Conflict` naming what
   each side does. Compare before writing: the differences nobody recorded are the
   valuable finding.
5. **A value a test must assert may stand in the verification case** although the data
   element only refers to the source.

## A format the product defines

1. **A layout is one definition with one typed feature per field.** State once how the
   order of declaration maps to the external order, since the language does not order
   features.
2. **Each external encoding is a named type,** defined once: width, sign, byte order,
   length prefix, text encoding, and the forms of null and empty. A field is typed by it,
   not by a general `Integer` or `String`.
3. **Tell fixed, derived and free fields apart.** A constant field is bound to its value
   and says whether a sender may override it; a derived field names its source; a field
   with neither is marked `@NotStated`. Limits and file names do not belong in a
   definition whose features are the fields.
4. **A mapping is one enumeration carrying the external code,** referring to the owner of
   the vocabulary by type. Say which external values are deliberately not used.
5. **State external naming once.** If external names (keys, columns) follow from model
   names, give the rule and list only the exceptions, with the rules for absent, null and
   unknown names.
6. **State the versions:** which are spoken, the starting one, how it changes, and whether
   layouts differ by version.

## For both

7. **Say what is accepted and what happens to the rest.** For every input: the acceptance
   condition, and one default for everything else. For several checks, their order. For
   every error answer: when, in which order, with which content.
8. **Say how a reader tolerates** trailing data, unknown types, oversize input and old
   names, apart from what a writer emits.
9. **Say how a value is formed before it is encoded:** rounding, sign, range, the text
   form of a number. An encoding rule does not cover it.
10. **Say when each message is sent, as a mapping of occasions:** one enumeration of the
    occasions, or one short list on the sending action, with the message for each and one
    default. An action definition per message is heavier than the content.
11. **Say how long kept data lives:** for a setting or a file the product keeps, its
    default, where it is kept, what changes it, what a missing or unreadable one means,
    and what it survives.
12. **A rule that spans several definitions** (a naming rule, a common limit) is stated
    once on the element that contains them all; where there is none, in the text of their
    package.

## What the language does not allow

- An enumeration cannot hold attributes. For a literal with an external code, specialise
  an attribute definition, or give the code in one sentence per literal.
- A feature of a definition cannot be named in an expression. Declare a usage of the
  definition and use dot notation (`limits.fullPercent`).
- A large or hexadecimal literal the validator cannot hold is written as an expression of
  smaller values, said once; do not fall back to a string.

## The usual mistakes

- A message described as a sentence listing its fields "in this order", with types in
  brackets and the special values in a following paragraph.
- The opposite, for a format the product follows: every field of the source turned into a
  feature, most of them saying only "as the source".

## Checks

- For a followed format: is the source named once with its version; is every difference
  either deliberate or marked; has no layout of the source been copied?
- For a defined format: has every field a type, an encoding and a source or a fixed
  value?
- Is every enumeration literal used, and every external code accounted for?
- Has every error a condition and a content, and every limit a behaviour at the limit?
- Has every optional field a stated absent form?
- Borders to walk for edge cases: the ends of each range and length, the empty and the
  full list, the missing, unreadable, oversize or truncated input, an unknown key or
  type, an older and a newer version.

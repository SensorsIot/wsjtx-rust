# Structure and interfaces

For a change to parts, ports, the items they carry, and connections.

## Rules

1. **Type what crosses a connection.** A port names the items it carries and their
   direction. An item definition used on a connection has features, or is marked
   `@NotStated`; an empty definition defines nothing. A general "operations" item hides
   what is exchanged.
2. **Pair what answers with what it answers.** Where an interface carries requests and
   replies, the model states which reply belongs to which request, by a typed reference
   or a redefinition, and how a reply is matched to its request.
3. **Say from which side an interface is written,** and which side uses the conjugate.
   Otherwise a reader must find a usage to learn the direction.
4. **Give every "many" and every "optional" its rule.** For each `[*]` or `[0..1]`: what
   one element stands for, what absence means, and for a population of connections how
   members are chosen and whether they may share an end. A shared end names what
   arbitrates it, or is marked.
5. **An invariant of data lives on the data,** as a constraint or one sentence on the
   feature. It becomes a requirement only when a part must be held to it.
6. **Something that happens is behaviour.** A structural description that says "resolves",
   "reports", "reconciles" or "at connection" hides behaviour: model it on the part that
   does it, or mark it.
7. **A name must not claim what the model does not have.** A connection called a
   delegation delegates; a part called an authority arbitrates. Correct the element under
   the identity rule, or mark the mismatch.
8. **Declare status where the binding puts it** for an interface, an item or a
   connection that is defined and not built.

9. **An interface has two halves.** What crosses it (items, their direction, their
   content) belongs to the port definition. What the hosting part does with it (when
   it sends, what it does with what it receives) is behaviour of that part, written as
   a feature of the part's definition; the requirements name the part as subject. A
   port definition owns no behaviour and no binding to code.

## The usual mistake

A port with two general items and a paragraph beside it listing the operations and which
reply follows which request. Rewritten: one item per request and per reply, each reply
referring to its request, the paragraph gone.

## Checks

- Is every carried item defined with content, or marked?
- Is every reply paired with its request?
- Does every `[*]` and `[0..1]` have its rule?
- Does each connection join a port and its conjugate, with the same items on both ends?
- Can a reader tell, from the part alone, who its neighbours are and what it cannot reach?

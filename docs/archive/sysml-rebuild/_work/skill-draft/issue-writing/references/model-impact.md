# Finding the home, and what the change does to the model

For step 3 of the skill. It holds the questions that decide where something belongs, the
four findings a search can have, the traps, and one worked example.

## The questions that decide a home

Ask them in this order; the first that answers, decides.

1. **Is it a promise at all?** Could two correct implementations differ on it without
   anyone outside the part noticing? Then it is the coder's and needs no home in the
   model; the issue may still need it under Technical details.
2. **Who uses it?** A value, a rule or a behaviour belongs to the part that acts on it,
   not to the part that stores it, shows it or passes it on. A screen that shows a value
   does not own it.
3. **Do two parts use it?** Then it belongs to what they share: their interface, or the
   part that holds both. A part does not reach into another part.
4. **Is it a setting?** Then three things are told apart, because they have three homes:
   where it is defined (with the part that uses it), where it is stored (with the part
   that stores), and where it is shown (the screen). A value the software manages for
   itself is stored and never shown.
5. **Is it a command from outside?** It enters where the architecture says commands
   enter, and reaches the function from there. A function with a side door of its own is
   a finding.
6. **Is something already there?** A change of where a thing is stored, named or keyed
   meets the data of a system in use. Say what becomes of it: taken over once, read both
   ways for a time, or left; if nothing decides, it is an open question.
7. **Is it a format someone else defines?** Refer to the source and state only the
   product's own choices and deliberate differences.

Where the code keeps the thing somewhere else than the answer, the code is not the
authority on the home. Say what the code does and where; the difference is work.

## The four findings

| What the search shows | What the issue says |
|---|---|
| The promise exists: an element states it, a test shows it | No issue, or only the part that is missing. `Already covered: <what>, by <file and element>`. |
| A similar element exists | Extend it. A second element for a near-identical thing is a defect: two wordings drift apart. Row "change". |
| An element states something the change contradicts | Row "replace" or "remove", with what takes its place. Its clause is reworded or retired, its test conditions go or change. Look for copies of the same statement in other parts' text. |
| Nothing exists | Row "add", with the owning part from the questions above. Check the tree: does the file exist? |

Most real changes have rows of several kinds. An issue with only "add" rows deserves a
second search: something usually has to give way.

## What to search, beyond the obvious term

- **The value, not only the name.** A limit of 6 may stand as `6`, as "six calls", or as a
  default in another element.
- **The synonyms of the domain.** The model may say "capture" where the request says
  "audio input".
- **The other end.** If the change sends something, find who receives it; if it stores,
  who reads; if it refuses, who shows the refusal.
- **The tests.** Search the test tree by the clause's number, across the whole tree: a
  test of one part can stand in another part's folder.
- **The files not yet rebuilt or converted.** An old copy of a part can still state the
  thing; say so, so that it is not carried forward when that part is next written. It
  gets a row of its own, marked as not rebuilt, with the change to make when it is.
- **The open issues that build the opposite.** An issue that adds what this one removes,
  or stores what this one moves, is named under Sequence.
- **The handover and decision records** the project keeps: a decision already made is
  found there, not asked again.

## Traps

- **Placing by the code's module.** The code may hold five parts in one file. The home
  follows the thing.
- **A negative as a promise.** "Never does X" is a promise only where something exists
  that could do X. Otherwise state the positive rule or nothing.
- **A value without a kind.** A value of a protocol belongs to its source; a value of a
  test (a sample size, a tolerance) to its test case; only a value someone outside relies
  on belongs to the promise.
- **A removal that removes too little.** When a mechanism goes, its literals in
  enumerations, its fields in items, its refusals, its test conditions and its mentions
  in other parts' text go with it. Search for each.
- **A removal that removes too much.** A neighbouring safeguard with a similar name may
  be a different thing. List what you kept and why.
- **Two homes after the change.** After writing the table, search once more for the
  term: every remaining hit must be the one home, a reference to it, or a row.

## Worked example

Request: "The Tx watchdog limits should be kept across a restart."

1. Sentence: the operator sets the number of calls and the Tune limit once, and they hold
   after a restart. Terms: watchdog, calls, tune, limit, 6, 90, restart, saved.
2. Duplicates: one closed issue saved two other operating switches in a file of their
   own; not this change.
3. Search. The model: `TxWatchdog` in transmit's state file states the limits and their
   start values; `SetWatchdogs` is a command on transmit's control interface;
   `WatchdogView` reports them. The code: the limits start at 6 and 90 at every start and
   no file holds them.
4. Findings: similar element exists (`TxWatchdog`: change); a side door exists
   (`SetWatchdogs`: remove, a setting changes one way); nothing stores them (add to the
   configuration of the part that uses them: transmit). The reference implementation
   saves both.
5. The table has three rows (as in the skill's example), "Tree: none", "Identities: the
   clause of the watchdog is reworded; one test condition is new: the limits after a
   restart", "Other parts: the part that stores keeps transmit's configuration; the
   station service gives it at start", "Model and code: the code does not save them:
   `Core::new` in the transmit service".

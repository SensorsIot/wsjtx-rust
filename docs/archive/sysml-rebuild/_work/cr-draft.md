# Draft: the product CR (not opened)

**Title:** The rebuilt SysML model is the product contract; the model tool checks the finished model

---

**Duplicate check**
Open issues considered: #232 (its product facts of Project-Specifics are taken up here; its
harness half is #233), #231 (user documentation, held until this lands), the model conversions
and rewrites of the former model (#147, #164, #168, #187, #194, #199, #208, #221, #222, #224)
and the code splits (#151 to #169), which this issue does not do; #201 and #198 (model tool),
which stay separate.

**Problem**
The product contract in `docs/sysml/` does not meet the project's rules
(`harness/project/docs/Finished-Model.md`): facts stand twice, clauses carry prose test
conditions, links run through `dependency`, structure rules are switched off by a pending
list, and model and code disagree in places nobody can see. The rebuilt model on the branch
`sysmlv2-rebuild` meets the rules, but the model tool (`tools/sysml.py`) and its tests encode the
former structure and refuse it. Goal: one model that the definer, the coder and the reviewer
can trust, checked whole by the gate, with every gap to the code visible in the model itself.
The operator gains a contract that says what holds now and what the code does not yet do.

**Functionality**

Already covered:
- The rebuilt model: `docs/sysml/` on `sysmlv2-rebuild` (116 files, M2.1); valid for the pinned
  Pilot; the rebuild's text checks find nothing (`docs/archive/sysml-rebuild/_work/check.py`).
- The rules it is checked against: `harness/project/docs/Finished-Model.md` (#233, #234).
- The model tool's general machinery: the authority marker, identity patterns, derivation
  ownership, test levels and locations, markers, Proves-tag agreement, model values, the
  Pilot pin, `equivalence`, `identities`, `paths`, the oracle file
  (`tools/sysml/README.md`).

To do:

*Model (`docs/sysml/`)*
1. `TC-009-002` carries a method value of `AutomationState`'s set.
2. `TC-022-011` is bound to a test that names it.
3. `ProfileDocument.sysml` names no other part's package (M3.3); `interfaces/external/Udp.sysml`
   imports no control interface (M3.4).
4. `CL-003-01`, `CL-008-11`, `CL-037-06` and `CL-039-25` (implemented) each have a case, or their
   status is what the code shows (M6.5).
5. Code links (M6.6): `CL-009-01`, `CL-011-01`, `CL-007-09` and `CL-024-01` resolve to one
   module list; the interface clauses of PskReporter (`CL-039-27`) and Udp (`CL-040-01`, `-03`,
   `-04`, `-06`, `-07`, `CL-112-02` to `-06`) carry their own `@ImplementedIn`.
6. `shared/ModelBindings.sysml` defines no `RetiredCase` (M1.5, M6.12).
7. `shared/ModelNotes.sysml` defines `CodeDiffers` (a doc of what the code does today). Every
   difference of a constant, enumeration value, wire name or environment variable that no
   target or partial clause carries stands as `@CodeDiffers` on its element; the differences
   are listed in `docs/archive/sysml-rebuild/_work/parts.json` (verdicts "difference in the
   code"). Every part definition whose modules stand outside its folder (M2.3) carries
   `@CodeDiffers` naming them.
8. A path or a test name inside a joined value is not split (M7.6).
9. `docs/sysml/` holds nothing but the model files and `data/` (M2.1): `reference/` and
   `.sysml-viewer/` leave it.
10. The product facts of Project-Specifics' sections "Communication verification model",
    "Recording fixture acquisition" and "Native Windows FFI boundary" stand in the model where
    they are promises, each named at its place in the CR's report; the rest is code.
11. Every clause that prevents something (a refusal, a disabled control, a MUST NOT) has a case
    bound to a negative test (M6.5); the CR's report lists them.

*Model tool (`tools/sysml.py`, `tools/sysml/`)*
12. Structure, by the finished model:
    - required packages `WstxRequirements` and `WstxShack`; the composition file `Shack.sysml`;
    - the layer rule M3.1 to M3.4 for every file, with UseCases taking its actors from Context;
    - the roles: `shack`, `shack.stations[*]` typed `Station`, the station's parts under
      `backend`, `backend.supervisor`, `backend.web`, `frontend.browsers`, the chain ranking,
      auto and qso under `backend.operating`;
    - the part folder `backend/operating/` for its own files;
    - rule 10: every clause and case names a subject (M6.9), an FR names none (M6.1), a
      use-case step's `requirement :>` is a subsetting;
    - empty items (M5.8);
    - every clause carried by a use-case step or `@Debugging` (M6.11);
    - naming (M7.5) and the one comment (M7.6);
    - the context check: each outside thing of `ShackContext` is a black box of ports, each port
      joined once to a station function through a type of `interfaces/external`.
13. Catalog and bindings:
    - a value joined by `+` is one value; `paths` reads all its literals;
    - a clause's code link is its part's `@ImplementedIn` unless it carries its own (M6.6);
    - a clause without a case stands at target or partial; an implemented one has a case (M6.5);
    - the FR status is computed by M6.1 and no FR states one;
    - a `Proves:` tag names test cases only, each declared, whose binding holds the test (M6.7);
    - an identity any earlier commit of the main branch declared and the model no longer
      does is refused when declared again (M6.12, read from git);
    - model and code (M6.13): constants, enumeration values, wire names and environment
      variables are compared with the code; a difference stands only under a target or partial
      clause or with `@CodeDiffers`, and a `@CodeDiffers` where the code matches is refused;
    - code structure (M2.3): every code module belongs to exactly one part; a part's module
      outside its folder carries `@CodeDiffers`.
14. Gone: the attribute forms, the `verification def` takeover, `dependency` ownership and its
    reciprocity, `RadioAuthority`, the fixed baseline, `@RetiredCase` and `retired`, the
    pending-structure list and its gate, the proven removals and `cost-wordings.json`, the
    context list `OutsideThing`.
15. The architecture oracle is regenerated from the rebuilt model by `oracle`.
16. `tools/sysml/README.md` states the tool's contract as built; its own clauses and tests take
    a series of the tool's own (not CL or TC, which are a clause and a case of an FR).
17. The writing rules of `docs/archive/sysml-rebuild/_work/check.py` are part of `check`.

*Tests and code*
18. `tools/sysml/tests/test_radio_properties.py` and its two `.tsv` files go (the property
    catalogue is not part of the model); `test_stated_once` T10 goes; `test_architecture_context`
    checks `ShackContext` against an owner table of its own; the real-model tests name
    `Shack.sysml` and `WstxShack`.
19. Every `// Proves:` tag in `server/`, `client/` and `tests/` names only the test cases its
    test belongs to: no FR, no clause, no shorthand, no issue number. A tag naming no declared
    case, or a case whose binding lacks the test, is resolved by binding or untagging.
20. The test readers name the rebuilt model's elements (`WstxStartup`, `WstxDecode`,
    `WstxModeProcessing`, and those that replace `WstxOperatingReceive`, `WstxHttpContentCoding`,
    `WstxStrategy`, `WstxContest`).

Not in this issue: the suites' select lists, the harness documents' links to the new files and
the removal of the moved sections from Project-Specifics (the harness change that follows); the
code restructuring M2.3 asks for (one issue per part, after this); the user documentation
(#231).

**Test cases**
- Each rule of items 12 to 14 has a unit test of its accepted case and one negative test per way
  the rule can be broken, on a fixture model that breaks it once and is refused with the rule's
  message, file and line (Finished-Model M8.2). Each new test is red on the parent.
- On the candidate: `python tools/sysml.py check`, `traces`, `status`, `markers` and
  `fingerprints` exit 0; the suites `sysml-documentation`, `sysml-tools`, `sysml-architecture`,
  `sysml-architecture-context` and every suite that reads model values pass; the full gate passes.
- `status` prints each FR's status as M6.1 computes it (FR-016 and FR-017 partial).
- A difference planted between a model value and a code constant fails `check`; the same with
  `@CodeDiffers` passes; `@CodeDiffers` on a matching value fails.
- A tag `// Proves: CL-…` or `// Proves: FR-…` in a test fails `traces`.

**Reading list**
- `harness/project/docs/Finished-Model.md` (the rules).
- `docs/sysml/` on `sysmlv2-rebuild`, in particular `Shack.sysml`, `Context.sysml`,
  `UseCases.sysml`, `shared/ModelBindings.sysml`, `shared/ModelNotes.sysml`,
  `interfaces/internal/StationLink.sysml` (`WireNames`).
- `docs/archive/sysml-rebuild/_work/harness-adaptation.md` (the inventory of the tool and its
  tests, with file and line) and `parts.json` (the code differences).
- `tools/sysml.py`, `tools/sysml/README.md`, `tools/sysml/architecture-oracle.json`,
  `tools/sysml/pending-structure.json`, `tools/sysml/tests/`.
- `harness/project/suites.yaml` (read only: the model suites and their commands).

**Open questions**
1. Does `docs/archive/sysml-rebuild/` land on the main branch with this issue (the rebuild's
   reports, ledger and decisions), or stay on its branch only?

**Sequence**
After #233 and #234 (landed). Before the harness change for the paths, #232's closing, #231 and
the code restructuring per part.

**Acceptance** (checked after the deploy)
- [ ] 1. On the main branch, `python tools/sysml.py check` and `status` exit 0; `status` shows
      FR-016 partial.
- [ ] 2. The station built from the landed commit starts its profile and decodes FT8 on the
      operating screen as before; observed on the live page.

**Decisions:** the decision comments (to be posted from
`docs/archive/sysml-rebuild/_work/harness-adaptation.md`, section "Decided").

**Approval**
<the operator's go>

**Blast:** high, because it replaces the whole product contract, rewrites the model tool and its
tests, and changes tags and test readers in about 80 code and test files; product behaviour
does not change.

<details><summary>Technical details</summary>

The rebuilt model was written part by part against the former model, the code and its tests;
each part's report, the identity ledger and the decisions are in `docs/archive/sysml-rebuild/`.
The model is already in place on `sysmlv2-rebuild`; the coordinator writes model text, the coder
the tool, the tests and the tags.

</details>

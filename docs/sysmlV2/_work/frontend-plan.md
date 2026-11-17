# Plan: the frontend (main session, from 2026-11-17)

Decided by the operator (START-HERE "Decided on 2026-11-17"): the frontend states what the
operator relies on (option A, no shortcuts); the frontend is an app without browser
elements (#103, #118 Q6/Q7, #149; the full-screen button goes); the browser client speaks
the derived wire; no login, token or authorization screens.

Inputs: the old `docs/sysml/frontend/*.sysml` (3,490 lines), 93 identities of the old
`OperatingScreen`, 40 identities handed over to the frontend, 30 handover rows (lines of
`handover.md`: 15, 45, 58, 68, 89, 92, 104, 114, 126, 127, 129, 131, 132, 139, 161, 178, 186,
194, 203, 208, 210, 212, 215, 219, 221, 226, 228, 277, 283, 285). Summaries of the old
identities: scratchpad `fe_ids.txt` (regenerate with the script in the plan's history if
lost: every requirement and verification of the old frontend with doc, objective, tests).

## Target files and what each takes (first assignment; refined while reading)

| File | Takes |
|---|---|
| `frontend/BrowserClient.sysml` | the part `BrowserClient`, ports `station : BrowserExchange`, `operator : OperatorInteractionPort`; the frontend config (display choices per browser, M5.2) |
| `frontend/OperatingScreen.sysml` | the screen as a whole: CL-010-16 (regions, top bar), CL-010-05, CL-010-08, CL-010-07, CL-003-04 (link, stale, retry), CL-074-01 (new boot), CL-051-02, CL-051-03, CL-037-03 (one HALT, Alt+H, Esc), CL-111-04 (Tx state shown), the app window (new CL-103-01 for #103/#149), the clock in the top bar (CL-010-14 part); CL-022-05 (health shown apart); keyboard shortcuts; themes. TCs TC-021-007, TC-007-002, TC-007-009, TC-051-002, TC-074-001..004, TC-111-005, TC-021-006, TC-051-003, TC-022-005, TC-043-003, TC-092-005 |
| `frontend/BandActivityPane.sysml` | CL-010-06 (Band Activity half), CL-010-09, CL-057-03, CL-057-01 (browser half), CL-055-04, CL-055-05, CL-050-02, CL-050-08, CL-039-04, CL-037-05, CL-061-01, CL-061-03, CL-007-02, CL-063-08, CL-039-25, CL-042-05..07 (screens); TCs TC-057-004, TC-055-006, -007, TC-050-002, TC-050-008, TC-039-046, TC-037-004, TC-061-001, -002, -004, TC-007-006, TC-057-001, -003, TC-024-004, TC-055-004, TC-039-006, TC-063-008, TC-063-012, TC-125-002, TC-042-003, -007 |
| `frontend/SignalArea.sysml` | CL-050-01, CL-050-07, CL-054-01 (browser half), CL-054-02, CL-061-05, CL-065-02, CL-068-01, the display half of CL-006-03 (new identity); TCs TC-050-001, -007, TC-054-001..003, TC-061-008, -009, TC-065-003, TC-082-004, TC-068-001, -002, TC-010-003, -006, -007, TC-061-006 |
| `frontend/QsoPane.sysml` | CL-010-06 (QSO pane half), CL-060-01, CL-050-03, CL-050-05, CL-037-04, CL-061-02, CL-111-09, the period bar of CL-010-14; TCs TC-060-001, TC-050-003, -005, TC-037-003, TC-061-003, TC-111-014, TC-010-008, TC-010-009, TC-007-003, TC-024-006, -009, -013, TC-099-003, TC-081-006, TC-097-014, TC-085-005, TC-039-021 |
| `frontend/LowerPanel.sysml` | CL-037-01 (Control panel), CL-037-02 (error field); TC-037-001, -002 |
| `frontend/Settings.sysml` | CL-073-01 (save outcome), CL-044-06 (detect radio), CL-044-08 (audio), the two levels of settings, the station's name, the rig, the Tx level, the clock view, logging, PSK Reporter, UDP, the strategy editor, the ignore list, the wanted list, Most Wanted, alerts, the recordings, Expert; TCs TC-073-001..003, TC-044-005, -007, -010, -015, -018, -022, TC-110-005 |
| `interfaces/external/OperatorInteraction.sysml` | the operator and the screen (taken over; rebuilt with the frontend) |

Retire: CL-022-01, TC-022-006, TC-022-010 (the authorization, #226); CL-096-01, TC-096-001,
TC-096-002 (the full-screen button goes, #103).

## Order

1. BrowserClient and OperatingScreen. 2. SignalArea. 3. BandActivityPane. 4. QsoPane and
LowerPanel. 5. Settings. 6. OperatorInteraction. 7. parts.json (part `frontend`), ledger,
handover, report. 8. **Compare with the WSJT-X UI** (operator 2026-11-17, "check what we
miss"): the main window, the Wide Graph, the Settings tabs and the menus of WSJT-X at the
behaviour baseline against the built frontend; each gap to the operator, one at a time,
with a recommendation. 9. **Use cases** (operator 2026-11-17): propose the list of
end-to-end use cases to the operator first; then the rule rows (M2.1, M3.1, M4) and
`UseCases.sysml`. Each file: read its old elements whole, sort by the method (level A), write,
check, validate.

## Done

- `BrowserClient.sysml` written: part, ports, `FrontendConfig` with theme, switch and
  display profile. **Open:** the display choices of SignalArea (levels, speed, flatten,
  spectrum line, split), Band Activity (highlight slots, sort) and the alert (sound,
  notification) become attributes of `FrontendConfig` when those files are written.
- `OperatingScreen.sysml` written: CL-010-16 (ScreenLayout), CL-103-01 new (AppWindow,
  target), CL-037-03 (HaltRule), CL-010-08 (KeyRule), CL-010-14 (TimeRule), CL-003-04
  (LinkRule), CL-074-01 (BootRule), CL-051-02 (PageUpdate), CL-051-03 (DataNotUnderstood),
  CL-010-07 (HealthRule), CL-111-04 (TxStateLine, target), CL-017-01 new (HelpRule, FR-017
  had no clause), LogbookPage; TCs TC-021-007, TC-007-002, -009, TC-051-002, TC-074-001,
  -003. web's ClientFiles serves the manifest; LaunchRule takes --app-window.
  **Names other files must define:** WstxSignalArea (the area), WstxQsoPane::PaneButtons,
  PeriodBar; WstxLowerPanel (control panel, error field); WstxSettings::SettingsDrawer,
  LogbookUpdate, AlertDisplay; WstxBandActivityPane::Highlight, Ordering.
  **Ledger at the end:** CL-010-05 retired, merged into CL-010-16; CL-022-05 retired, merged
  into CL-010-07; CL-096-01, TC-096-001, -002 retired (#103); CL-022-01, TC-022-006, -010
  retired (#226); TC-021-006 not carried (asserts the old status's radio text; the layout
  is TC-007-002's); TC-074-002 not carried (the old automation run); TC-074-004, TC-051-003,
  TC-111-005 not carried (planned, no test); TC-022-005 not carried (grant fixture);
  TC-043-003 to Settings (the clock view); TC-092-005 to be read.
- `SignalArea.sysml` written: CL-006-08 new (SignalLayout, the display half of CL-006-03),
  CL-054-02 (DisplayLevels), CL-054-01 (RowOrder), CL-061-05 (TxBand), CL-050-01
  (PointerRule, RxTxStrip), CL-050-07 (FrequencyMapping), CL-068-01 (SwrValue), CL-065-02
  (OpenSlotMarks); TCs TC-010-003, -006, -007, TC-054-001, -002, TC-061-006, -008, TC-050-001,
  -007, TC-068-001, TC-082-004. `FrontendConfig` holds sensitivityDb, rangeDb, speed,
  flatten, spectrumLine, signalHeight. **Ledger at the end:** TC-054-003, TC-061-009,
  TC-068-002 not carried (planned, live, no test); TC-065-003 not carried (asserts the
  Settings checkbox #82 removed; TC-082-004 shows the marks). The double-click on a Band
  Activity row (old CL-050-01) is Band Activity's.
- `BandActivityPane.sysml` written: CL-010-09 (RowFields), CL-057-03 (Periods), CL-057-01
  (Promptness), CL-061-03 (TxPeriod), CL-061-01 (LossEpoch), CL-055-04 (Ordering), CL-050-02
  (Highlight), CL-050-08 (RowMark, RowMarks), CL-055-05 (Density), CL-037-05 (RowActions,
  with Ignore and Wanted in the row menu), CL-039-04 (StrategyElement), CL-063-08
  (ContestFilter), CL-039-31 new (AutoControls, FR-025), CL-042-06 (IgnoreField: the one
  list on the screen, target); TCs TC-007-006, TC-024-004, TC-055-004, TC-057-004,
  TC-057-001, TC-061-004, TC-061-001, TC-055-006, TC-050-002, TC-050-008, TC-055-007,
  TC-037-004, TC-039-006, TC-063-008, TC-081-006. `FrontendConfig` holds highlight,
  sortField, sortDescending; `HighlightSlot` (13, no CQ, no LotW) and `SortField` in the part
  file. **Ledger at the end:** CL-007-02 retired, merged into CL-010-09; CL-010-06 to
  QsoPane; TC-039-046 not carried (asserts the whole-configuration save); TC-063-012 not
  carried (asserts the old automation run's view); TC-042-003, TC-125-002 not carried
  (assert the two Settings lists; the one list is CL-042-06's); TC-061-002, TC-057-003 not
  carried (planned, no test); to Settings: CL-039-25, CL-042-05, CL-042-07, TC-097-014,
  TC-042-007, TC-039-021. Auto's toggles moved to the QSO pane (the client has them among the
  direct buttons); CL-039-31 stands in `QsoPane.sysml`.
- `QsoPane.sysml` written: CL-037-04 (PaneLayout, CallingMe), CL-060-01 (DialogueTable),
  CL-050-05 (MessageLines), CL-050-03 (PeriodBar), CL-037-06 new (PaneButtons), CL-039-31
  (AutoControls), CL-111-09 (MessagesFoldOut, target); TCs TC-037-003, TC-007-003,
  TC-060-001, TC-050-005, TC-085-005, TC-050-003, TC-081-006, TC-024-006, -009, -013,
  TC-099-003.
- `LowerPanel.sysml` written: CL-037-01 (ControlPanel), CL-037-02 (ErrorField with every
  entry, its text and severity, from the client); TCs TC-037-001, -002, TC-044-018,
  TC-092-005. **Ledger at the end:** CL-010-06 retired, merged into CL-037-04; CL-061-02 and
  TC-061-003 retired (the commands carry no contact revision); TC-111-014 not carried
  (planned, no test); TC-010-008 to be placed (the frequency inputs: SignalArea, CL-050-01);
  TC-010-009 (the displays of CL-010-14) to OperatingScreen; TC-097-014 to Settings.

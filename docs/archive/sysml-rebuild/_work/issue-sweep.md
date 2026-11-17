# Issue sweep, 2026-11-18 (read only; nothing posted)

107 open issues (#235 excluded): DONE 26, OVERTAKEN 6, REWRITE 33, CODE-SPLIT 12, KEEP 17,
HARNESS 3 (#172 close in 1.3, #188 keep without cr label, #152 close), QUESTION 10.
alex.first today [136, 221, 138, 141, 139, 140, 143] is all DONE (#143 closed).

Questions for the operator: #107 strategy at start; #216 editable built-ins; #122 MCP equals
browser; #189 contact after device_lost; #213 menu-item hold; #215 split and VOX hold; #13 Flex
phase 2; #108/#130 where the timing class lives; #191 simulator profile. Inside REWRITE issues:
#98 contest upload, #129 L4/L5/L14, #132 swrFault latch, #80 close into #118, #225 Q1, #227 Q9,
#226 Q4.

For #235: about 120 code comments cite old model names; modules owned by several parts
(main.rs, recording.rs, radio_setup.rs, radio_control/setup.rs, strategy.rs, contest.rs,
dxcc.rs, contact_http.rs, most_wanted.rs) and by none (authorization*.rs, flex_http.rs,
logbook_http.rs, radio_http.rs, receive_http.rs, transmit/clock_http.rs, model_values.rs,
test_ports.rs, lib.rs); model defects: "Settings > Expert" vs AdvancedSection; "Abort QSO (Esc)"
for HaltQso; BehaviorBaseline beta4 with SequenceRule citing beta6; RowMarks tip "(worked on …)";
implemented status of CL-112-01, CL-003-01, CL-008-08, CL-009-06 to verify.

Missing issues: code splits clock, log, spots, udp; qso decisions 2, 5, 9; CL-044-18 power per
band; #112 follow-up; #221's startup code; drift tracking out of recording.rs; the derived wire;
the WSJT-X UI targets.

Work order proposed for alex.first after #235: #198, #201; #192; #226; #229; the code splits
(#161 → #157 → #153; #151 → #135 → #162 → #159 → #160 → #156; #163; #154; #169 last); #225,
#227, #195, #228; the Auto/QSO line; the radio line; remote and app; Band Activity; tests and
timing; #231; contests; Flex (parked).

Closed 2026-11-18 (operator's OK), each with its pointer: 136, 221, 222, 138, 139, 224, 140, 141,
142, 144, 145, 146, 187, 194, 168, 208, 125, 99, 104, 111, 75, 174, 175, 176, 196 (done), 147,
199, 164, 209, 112, 155 (overtaken). #232 stays open until #235 and harness change 2 have landed
(operator 2026-11-17).

## Per issue (merged results)

## A
136 blocked DONE (receive in backend/receive/; tags #235 i20; worktree harness-issue/136 discard)
221 recorded DONE (supervisor/Startup.sysml CL-045-01..03, TC-045-001; startup code work: memory.json, drop receive-startup.json, POST /receive/startup, Monitor off -> no exact home; #227 keeps Monitor off against 2026-11-17)
222 none DONE (LiveReceive.sysml)
138 ready DONE (mcp/; token/policy retired; code work belongs #122/#226) -> off alex.first
223 none REWRITE (TC-044-006 cap tests EndpointNaming 64/256 deviceLimit; drop /audio/devices + 16384 cap)
224 none DONE (SoundDevice.sysml typed)
139 ready DONE (audio/; CL-044-17 name migration overtaken #229) -> off alex.first; drift tracking out of recording.rs no issue (fits #159/#151)

## B (code comments citing old model names not covered by #235 -> add to #235 item 20 or per-part splits)
140 blocked DONE (radioControl/, Cat.sysml, RadioControl iface); comments WstxRadioIO 5 files. In-flight: don't answer return-to-define; close.
141 recorded DONE (web/, StationLink, WebControl; CL-003-xx Listener; authorization retired); readers -> #235 i21 must become test-local oracles.
142 defining DONE (supervisor/; CL-008-07, CL-044-16, TC-044-023 OperatingSelection); stop define.
144 recorded DONE (operating/, qso/, auto/, ranking/, log/); TC-097-019 test remove; ~100 comments.
145 defining DONE (udp/, UdpControl, Udp.sysml; #235 i3, i5); stop define; T/R period product change no issue.
146 recorded DONE (frontend/ 7 files).
147 recorded OVERTAKEN (#235 later sweep; FR-013..015 retired; catalogue out; Station->Shack; tool part #235 i9,12,15,19).

## H
79 paused REWRITE (test paths modes/decoder/*_test.rs; tags not bound to TC-004-003; suites.yaml harness half split; tools/windows_resource_job.py --case busy)
80 paused REWRITE (installed b67136fa0; only live row; LinkTrafficLog -> WstxListener; ThinLinkBudget StationLink statusShownMs; drop CL-022-05 TC-022-008 CL-010-15) or merge row into #118 (rec)
177 recorded KEEP
178 recorded KEEP
181 recorded KEEP
191 recorded QUESTION: (1) close done (Project-Specifics "Simulator live tests", station-switch.ps1) rec; (2) keep for Flex endpoint
192 decided REWRITE (paths .harness->harness/project; Strategy.sysml StrategyWatchdog -> AutoMode CL-119-05 AutoStops; wire today vs derived; split CR tools/live + harness change). Holds Alex keying restriction.
196 accepted DONE (accepted live TC-196-08/09; close)
197 recorded KEEP (CL-074-01 BootRule at Define)
198 recorded KEEP (validate() timeout)
201 recorded KEEP
172 harness HARNESS close in Phase 1.3 (config alex/meter); open points 2,3 + flaky tests -> single issues
188 harness+cr:recorded HARNESS keep (remove cr: label); tools/deploy residue (test_references.py UNCHANGED, station_drill.py) small companion
230 landed KEEP (finish T18 install + accept)
231 defining KEEP (held until #235; label defining contradicts hold -> paused; HANDOFF -> MEMORY.md)
232 recorded DONE-partial: close when #235 and harness change 3 land (#233 did rules; #235 item 10)
113 recorded REWRITE (BandActivityPane.sysml; settled rows drop; CL-037-06 collision; pilot branch delete). After #107.

## C (no timing vocabulary in new model / M6.5 closed skeleton)
187 accepted DONE (ranking/ 7 files; landed 217cbf9d2 accepted)
194 accepted DONE (Shack/Context/backend; landed 2fb40abdb)
199 recorded OVERTAKEN (M6.1 FR no subject, M6.2 no satisfy of clause; Shack.sysml:230-232)
164 recorded OVERTAKEN (no transition tables; StandardQso::SequenceRule CL-010-02)
168 recorded DONE (flexAdapter/ CL-013-01..08, TC-023-001..003)
208 recorded DONE (TransmitState CL-111-01 TransmitArming; CL-009-04 only Halt/failures/releases)
108 ready QUESTION: (A) timing class in model -> harness change amends M6.5/M8, rewrite #108; (B) label only (timing_class.py), close #108 overtaken, #207 shrinks, #130 close REC. In-flight: off alex.first, back to deciding.
207 none REWRITE (17 of 87 identities retired/not carried; homes; paths; drop @Timing under B)
126 deciding REWRITE ("Already covered (#108)" absent; paths; TC refs TC-008-005/TC-009-007; @TestedBy; suites.yaml harness half split out). In-flight: coder stopped.
130 recorded QUESTION -> follows #108 (B: close).

## F1
129 deciding REWRITE (hold not modelled; as-built opposite sentences: CatControl::ReadCompareWriteVerify, RadioSetup::RecommendedSettings, ManagedAgc, OperatingSelection::StationBandRule CL-008-11 to reverse; L4/L5/L14 open operator Qs; list per rig (Hamlib); map names; drop RF power (#209)). Before #132 #213 #215 #152.
132 ready REWRITE (no availability/ExternalPort in model; swrFault vs SwrBarrier CL-044-17 supervisor conflict -> operator; LoseRadio regain; drop grant; Keying names; RadioStatus name taken; satisfy vs M6.2). In-flight: Ready PASS vs old model -> back to defining. After #211 #129.
152 recorded HARNESS (preflight under harness/project/deploy/; premise overtaken CL-044-18 per band) -> close.
209 none OVERTAKEN (per band CL-044-18 ManagedPower, RadioConfig::powers; CL-044-13 retired). Needs code issue for CL-044-18.
211 none REWRITE (merge into #132 suggested; RadioAuthority gone; Keying names; satisfy M6.2; oracle/pending #235).
213 none QUESTION (Undo gone, RecommendedSettings "sets nothing back"): (a) hold from completed Apply, one record REC; (b) no menu hold, SettingsCheck reports; (c) always hold contradicts CL-044-04.
215 none QUESTION (split SplitOperation CL-008-13; VOX not modelled): (a) hold VOX off + split per SplitOperation REC; (b) VOX only; (c) close.
155 (me) recorded OVERTAKEN: profile files not an outside thing (Context.sysml has none; M4.1 file service described with function); storage = storageUnavailable refusal in ProfileDocument; ExternalPort not in model.

## E2
98 paused REWRITE (none in model; ContestTable 9 hardcoded; ContestValueOrder not projected; serial ContestSerialRule CL-085-03 done) + operator Q first: upload vs "contest table read only" (2026-11-16) -> rec bundled read-only data file. Branch cr98-contest void (keep af5a6b762 ref). After #235, #228.
99 paused DONE (landed ee08e0ac9, installed in 0e4b4c73a; CL-099-02 EuVhfRule; TC-099-004 not carried).
104 recorded DONE (HoldTx::HoldTxRule CL-039-08; code with #119; coordinator 2026-11-12 closes with #119).
105 paused REWRITE (OpenSlotRule CL-065-01 qso; add growth build; 500 Hz; drop TC-105-002 live/Enable Tx; branch harness-issue/105 drop). Before #106.
106 deciding REWRITE (QuietSpace CL-039-09 qso, MoveRule CL-097-05; qso decision 4 contradicts CL-106-01 removal of his end; Alex Q answered by rebuild). After #119, #105.
111 paused DONE (station half landed 4e5910a52 installed; TransmitState/QsoTransmit; browser half #120, enable_tx #121).
75 paused DONE (RowMarks callsMe CL-050-08 implemented incl worked-before).
189 recorded QUESTION: (a) keep contact w/ cause, state explicitly in QsoTransmit/StandardQso REC; (b) cancel; (c) cancel after time.

## E1
107 defining QUESTION: "always a strategy/Default restore" (decisions 6805594842, 6853485728) vs #228 dec 2 2026-11-15 "nothing active after start" (StrategySelection::SelectionRule) + 2026-11-17 filter (BandActivityPane::StrategyElement CL-039-04). (a) keep None, restate rest (strategy order changes CL-055-04 Ordering; tip order RowMarks; 3 ValueCriterion on-band values; drop restore/Default/PUT/evaluate) REC; (b) Default at start; (c) close overtaken. In-flight: pause definer (body limit loop). #216 depends.
109 deciding REWRITE: model mostly done (StandardQso::SequenceRule CL-010-02 partial, CL-109-01 ReopenRule, HandOverRule CL-085-02, ContestSerialRule CL-085-03); promise 5 overtaken by qso decisions 2,5,9 (TooCloseRule CL-039-29, BusyPause CL-097-06); D3 overtaken by Log QSO resends; promise 9 baseline beta6 still open (Requirements BehaviorBaseline @Conflict) -> #235 model finding?; map list. In-flight: stop decide; open Q moot; #192 adjust exemption.
85 landed KEEP: carry to install/accept after #192; Logbook CL-085-01.
Gap: no issue for qso decisions 2,5,9 code (TooCloseRule, BusyPause).

## F2 (flexAdapter parked)
166 ready REWRITE: model half done (Shack flexAdapter, FlexAdapter ports control ~NativeControlPort, samples CaptureSamples w/ InputStatus); code: Recording.flex still read in 7 files. Drop model/oracle/test_architecture parts; backend->native ports; ~RadioCommand->~NativeControlPort; NativeFlexWireSubset->WstxFlexSession; drop L4/L5/grant (#226); udp name -> CL-112-01 UdpSender; paths flex/->flexAdapter/; NotStated gaps (NativeIntent/SessionStatus on NativeControlPort; StreamDiagnosis). In-flight: back to defining, off ready.
13 paused QUESTION: (a) close delivered (FlexSession CL-013-01..07, TC-023-001..003; TC-023-004..006 not carried) rec; (b) keep paused for live TC-023-004.
165 recorded REWRITE: ProductScope l309 -> FlexApi::StreamPacket + FlexSession::StreamIntake; Command literal under CL-013-05 ReceiveOnly; paths; after #166; NativeIntent setting.
167 recorded REWRITE: NativeFlexWireSubset Transmit -> CL-013-05 ReceiveOnly widen; via audio playback port; keying items on NativeControlPort; TC-023-006 not carried -> new case; TransmitProfile::configured; after #166/#132/#129/#210.
210 none REWRITE: NativeControlPort new items; flex/session.rs path; NativeIntent::rxAntenna; issue-only CL-129-xx; after #129/#132/#166.
212 none REWRITE: subject receive -> supervisor (StationAuthority 47-50, Startup 140, OperatingSelection 62) + audio InputStatus; CL-132-07 not in model; CL-166-02/TC-166-004 new identities; after #166/#132.

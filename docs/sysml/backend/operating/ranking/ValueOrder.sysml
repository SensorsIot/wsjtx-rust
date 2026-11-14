package WstxValueOrder {
    private import ScalarValues::*;
    private import WstxRequirements::AutomationState;
    private import WstxRankingControl::CountryList;
    private import WstxRankingControl::CqTargetList;
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::'FR-011';
    private import WstxRequirements::ImplementationState;
    private import WstxRankingControl::Needed;
    private import WstxRankingControl::NewPer;
    private import WstxRankingControl::NewWhat;
    private import WstxStrategies::Strategy;
    private import WstxRankingControl::StrategyBands;
    private import WstxContact::'TC-039-002';
    private import WstxContact::'TC-039-003';
    private import WstxContact::'TC-039-004';
    private import WstxContact::'TC-039-007';
    private import WstxContact::'TC-039-030';
    private import WstxContact::'TC-039-047';
    private import WstxContact::'TC-042-001';
    private import WstxContact::'TC-097-006';
    private import WstxContact::'TC-097-016';
    private import WstxContact::'TC-097-019';
    private import WstxRankingControl::UsStateFilter;
    private import WstxRankingControl::Verdict;

    attribute def Candidate {
        doc /* The filter, yes or no (Q2, Q10; #97 decision 2, the filter questions): every line
             must hold. A decoded standard message with a resolved sender, not mine, passing
             SaneCall, not ignored (IgnoreLists), the station band one of the strategy's
             (StrategyBands), not greyed (DirectedCqRule, except a word of the include list of
             CqTargetList), a CQ, or with treat_73_as_cq an RR73/73 addressed to someone else;
             region holds (all; dx: my continent and the sender's are known and differ; selected:
             the sender's continent is listed); min_snr_db null or the SNR known and >= it;
             NewNeeded true for at least one NewWhat of filters.new, with the strategy's new_per,
             new_means and worked_since (any chosen what counts); CountryList, UsStateFilter and
             CqTargetList hold. Each failing line names itself as why ("band not in the strategy",
             "region", "below min SNR", "not new", "country list", "state list", "CQ target").
             A contest strategy: ContestVerdict decides its callable records (the contest's rules
             first) and CountryList, UsStateFilter and CqTargetList apply on top; none of the
             other lines. The filter and the order may use the same field. */
    }
    calc def NewNeeded {
        in strategy : Strategy;
        in what : NewWhat;
        in per : NewPer;
        in needed : Needed;
        in sender : String;
        return isNew : Boolean;
        doc /* Whether one NewWhat is new for a
             decoded sender, per NewPer, against WorkedWindow of the strategy (worked_since):
             not_worked: no logged QSO with the same key; not_confirmed: none, or none confirmed
             (dxcc::Standing). The key: dxcc the sender's entity (WstxCountryFile::EntityOfCall, WAE
             entities by their own full name); call the call; grid the 4-character grid square in
             the decoded message, with the rule of D13 (no grid in the message is not new; a sender
             with a logged QSO without a grid in the window has an unknown grid status and is not
             new); cq_zone and itu_zone the zones of the sender's entity with the cty.dat entry's
             overrides; continent ContinentOfCall; prefix WpxPrefix of the call. per: ever any
             logged QSO; band one on the station band, any mode; band_mode one on the station band
             in the operating mode (ADIF MODE, an MFSK record by its SUBMODE). False without an
             entity (dxcc, cq_zone, itu_zone, continent; /MM, /AM, unknown prefix), without a
             known station band (band, band_mode) and when the log is unreadable (no claim of new).
             A logged call without an entity counts for nothing for those keys; a logged contact
             without a band counts only for ever. The schema 3 goals are exactly: dxcc ever,
             dxcc band, dxcc band_mode, cq_zone ever (waz), prefix ever (wpx), grid ever, call ever,
             call band. */
    }
    attribute def CallerOfMyCall {
        doc /* A decoded standard message with a resolved sender, addressed to my call, other
             than the sender's RR73/73, whose sender is not ignored (IgnoreLists). Decision 2
             (operator 2026-11-09): a caller of my call has a rank only when it passes the filters
             too: every line of Candidate except "a CQ" (and the CQ target line, which judges only
             CQs); for a contest strategy the contest's verdict (a dupe never has a rank,
             WstxRankingControl::ContestVerdict) and the country and US state lists. A caller that fails
             gets rank null with the failing line as why ("calls my call · not new", "calls my
             call · region"). Decision 4, Calling stations are answered (callers_first): on, the
             callers that pass come first (ValueOrder); off, a caller that passes has rank null
             too, why "calls my call · not answered" (CL-097-03). Off follows WSJT-X, where the
             CQ response None (widgets/mainwindow.cpp 1564-1568, default None in
             mainwindow_settings.cpp 313) answers no caller of my CQ automatically (mainwindow.cpp
             7481-7496) and "Calling CQ forces Call 1st" is off by default (Configuration.cpp
             3884). A started QSO is always finished (StartedQso, #81): a target that answers our
             call is progress, never a caller judged again. */
    }
    attribute def ValueOrder {
        doc /* The ranking (Q2, Q3, Q8, Q9; #97 decision 3). The strategy's order is a list of
             ValueCriterion, shown as dropdown rows: the first decides and the next breaks a tie.
             Each criterion, better first:
             most_wanted: on the Most Wanted list by its rank ascending, then the stations without
             a rank (MostWantedList).
             new_dxcc, new_dxcc_band, new_dxcc_band_mode: NewNeeded dxcc per ever, band,
             band_mode; new_call, new_call_band: NewNeeded call per ever, band; new_grid,
             new_grid_band: NewNeeded grid per ever, band (D13: no grid, an unknown grid status or
             an unknown band is not new); new_cq_zone, new_itu_zone, new_continent, new_prefix:
             NewNeeded cq_zone, itu_zone, continent, prefix per ever; each with the strategy's
             new_means and worked_since; new before not new.
             snr_bucket: the SNR in three buckets, above 0 dB (snr > 0) first, -10..0 dB (-10 <=
             snr <= 0) next, below -10 dB (snr < -10) last, unknown after them; equal inside a
             bucket.
             snr: stronger first, unknown last.
             distance: StationDistance, farther first, unknown last.
             hears_us: the stations that hear us (PskrUse on and HearingFeed has a spot of my call
             at that station at most 600 s old on the station band and mode) first, then the rest;
             equal with PskrUse off or no feed.
             Then always, hidden (Q3, Q9): SNR stronger first (unknown last); then, for an
             exact tie only, the lower audio frequency, then the call in character order.
             Decode order is never a ranking.
             Order of a strategy's list: with Calling stations are answered on (callers_first,
             decision 4) the callers of my call that pass the filters (CallerOfMyCall) come first,
             ranked among themselves by the same criteria, then the candidates; with it off a
             caller has no rank (CallerOfMyCall) and the list holds the candidates only. Band
             Activity: the partner (#50, on top by the browser's partner rows), then that list,
             then the rest. A contest strategy has no order (order []): it ranks by the contest's
             own rules (WstxContestRanking::ContestValueOrder), under the same rule for callers. */
    }
    calc def StationDistance {
        in sender : String;
        in grid : String[0..1];
        return km : Integer[0..1];
        doc /* The distance for the value criterion distance: the great-circle distance from
             the centre of the profile locator to the centre of the 4-character grid in the
             message; otherwise to the sender's entity centre from cty.dat (the approximate
             entity distance of WstxLogControl::DecodedEntity). Unknown without a profile locator
             or without grid and entity (/MM, /AM, unknown prefix). Whole km, truncated. */
    }
    calc def WpxPrefix {
        in call : String;
        return prefix : String;
        doc /* The CQ WPX prefix of a call, from the CQ WPX Contest rules: the letters and
             digits up to and including the last digit (N8BJQ N8, HG19ABC HG19, LY1000X LY1000,
             3DA0RU 3DA0, 9A1A 9A1). A call without a digit: its first two letters and a zero
             (XEFTJW XE0). Portable: /P /M /MM /AM /A /E /J /QRP /B and /R do not count
             (N8BJQ/P N8); a single digit replaces the call's last digit (N8BJQ/3 N3); another
             designator is the prefix: with a digit up to its last digit (N8BJQ/KH9 KH9,
             KH9/N8BJQ KH9), without one its first two letters and a zero (PA/N8BJQ PA0).
             The designator is the shorter part, the left one when both are equally long.
             Upper case. */
    }
    calc def ContinentOfCall {
        in call : String;
        return continent : String[0..1];
        doc /* #55: the continent of WstxCountryFile::EntityOfCall for the call (with a {cont}
             override of the matching cty.dat entry applied); none when the call has no
             entity (/MM, /AM, unknown prefix). It replaces the earlier locator-rectangle
             approximation: the message grid no longer decides a station's continent.
             The snapshot's derived_continent is ContinentOfCall of my callsign. */
    }
    calc def MyContinent {
        in configured : String[0..1];
        in callsign : String[0..1];
        in locator : String[0..1];
        return continent : String[0..1];
        doc /* The configured continent (StrategyConfiguration continent) when set; else
             ContinentOfCall of the profile callsign; else, when the call has no entity
             (/MM, /AM, unknown prefix), the continent of the cty.dat entity whose centre
             is nearest to the centre of the profile locator; else none. */
    }
    calc def UsStateOf {
        in sender : String;
        return stateCode : String[0..1];
        doc /* The state of a sender of the entities 291, 6 or 110 (WstxCountryFile::EntityOfCall),
             the first source that knows it: (1) the decoded message, when its exchange carries a
             US state (the RTTY Roundup family; an ARRL or RAC section once #98's section table maps
             it to a state); (2) the log: the ADIF STATE of the newest record of that call that has
             one, a confirmed record (dxcc::Standing) before an unconfirmed one. The FCC/ISED
             licence data and the grid, the further sources of the operator's decision, are a
             separate issue, #101 (operator 2026-11-09, #97 Q6 "separate issue"); until it is
             delivered they give nothing.
             None: unknown. */
    }
    calc def SaneCall {
        in call : String;
        return sane : Boolean;
        doc /* At least 3 characters with a digit and a letter, not ending /R (rover). */
    }
    calc def DirectedCqRule {
        in target : String[0..1];
        in myContinent : String[0..1];
        in senderContinent : String[0..1];
        return answerable : Boolean;
        doc /* The one directive rule of strategies and the operator (operator decision #39,
             2026-11-04), applied before any strategy and one function in the station. A CQ
             is answerable when its directive does not exclude me: a plain CQ (no target);
             "CQ x" with x my continent; "CQ DX" when both continents are known and differ.
             Contest activity (#63, WstxContestRanking::ContestDirective): the word of the station's
             special activity (WstxSpecialActivities::SpecialActivity: na_vhf, eu_vhf and arrl_digi TEST, ww_digi WW,
             field_day FD, rtty RU) is answerable too, whatever the continents.
             Every other directive is not answerable: another continent or region (NA, JA,
             SA, ...), any other word (TEST, POTA, a number; a contest word outside its activity),
             CQ DX from my own or an unknown
             continent, and with my continent unknown every directive. A record that is no
             CQ has no directive and is answerable. Its text is "CQ x — not for <my continent>"
             ("not for this station" when unknown).
             My continent: MyContinent.
             A strategy skips a CQ that is not answerable: it is greyed in Band Activity,
             is never a Candidate and is never answered by a run or a pounce. An operator's
             selection of such a row (double-click, Reply, Select, the other-calls list) is
             refused directive_not_answerable (409 with error.reason = this text); the
             browser shows it as a warning the operator can confirm, and only then sends
             select_row again with the optional directive_confirmed true. The directive is checked
             before contact_active, so during a contact a plain click (select_row without replace) on
             such a row is refused this way too and offers nothing (CL-037-05); a double-click warns. A command that is
             not the browser's (automation, MCP, UDP) can never confirm it: its select_row is
             refused directive_not_answerable also with directive_confirmed. The one exception
             (#97, CqTargetList): a strategy run's own select_row of a CQ whose directive word is on
             its active strategy's CQ target include list passes, and that strategy's verdict of it
             is not grey. */
    }

    dependency evaluateClause from Verdict to WstxValueOrder::'CL-039-02';
    dependency goalClause from NewNeeded to WstxValueOrder::'CL-039-02';
    dependency bandsClause from StrategyBands to WstxValueOrder::'CL-097-02';
    dependency filterClause from Candidate to WstxValueOrder::'CL-097-02';
    dependency newNeededClause from NewNeeded to WstxValueOrder::'CL-097-02';
    dependency callerFilterClause from CallerOfMyCall to WstxValueOrder::'CL-097-02';
    dependency countryClause from CountryList to WstxValueOrder::'CL-097-02';
    dependency stateClause from UsStateFilter to WstxValueOrder::'CL-097-02';
    dependency stateOfClause from UsStateOf to WstxValueOrder::'CL-097-02';
    dependency cqTargetClause from CqTargetList to WstxValueOrder::'CL-097-02';
    dependency orderClause from ValueOrder to WstxValueOrder::'CL-097-03';
    dependency valueClause from ValueOrder to WstxValueOrder::'CL-039-02';
    dependency directedClause from DirectedCqRule to WstxValueOrder::'CL-039-03';
    dependency myContinentClause from MyContinent to WstxValueOrder::'CL-039-03';
    dependency distanceClause from StationDistance to WstxValueOrder::'CL-039-02';

    requirement 'CL-039-02' {
        doc /* One station evaluator gives each decoded standard message a verdict: its filters are CL-097-02 and its order CL-097-03, callers of my call included. SNR is always the hidden last tie-breaker, then for an exact tie the lower audio frequency and the call; decode order is never a ranking. Distance is from the profile locator to the message grid, else to the cty.dat entity centre. POST /strategy/evaluate returns the verdicts of retained live records for the saved strategy or a draft, with the reason when asked; the browser never evaluates a strategy itself. Details: WstxValueOrder::NewNeeded, WpxPrefix, WorkedWindow, CallerOfMyCall, Candidate, ValueOrder, StationDistance, Verdict, StrategyHttp. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/logbook.rs; server/src/recording.rs; server/src/dxcc.rs";
    }
    requirement 'CL-039-03' {
        doc /* One directive rule before every strategy and for the operator: a CQ is answerable when it is a plain CQ, CQ <my continent> (derived from the profile call via cty.dat, locator fallback) or CQ DX from another continent. Every other directive is not answerable: a strategy skips it (greyed, never matches, never answered by a run or pounce) and an operator's selection shows a warning the operator can confirm ("CQ NA — not for EU"); automation, MCP and UDP cannot confirm it. In a contest activity its own word (CQ TEST, WW, FD, RU) is answerable too (CL-063-02). Details: WstxValueOrder::DirectedCqRule, MyContinent, StrategyRun. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; server/src/contact_http.rs; server/src/dxcc.rs; client/contact.js";
    }
    requirement 'CL-042-01' {
        doc /* What must be new reads the sender's cty.dat entity (#55) against the internal log: new [dxcc] per ever, band and band_mode, and new [cq_zone] per ever (WstxValueOrder::NewNeeded); a sender without an entity, an unknown station band (for band and band_mode) or an unreadable log never counts as new. The editor offers them in decision 2; the live preview names why. Details: WstxValueOrder::NewNeeded. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/dxcc.rs; server/src/logbook.rs; client/contact.js";
    }
    requirement 'CL-097-02' {
        doc /* (#97 decisions 1 and 2, ranking only) Band: off the strategy's bands (all by default) every verdict has rank null, why "band not in the strategy" or "band unknown"; it never switches bands. Filters, every line must hold: what must be new (DXCC entity, call, grid, CQ zone, ITU zone, continent, prefix; any chosen one counts) per ever, band or band and mode, new meaning not worked or not confirmed (QSL/LoTW); region; minimum SNR; worked since (any time, today, from-to); Treat 73 as CQ; prefix/country include and exclude lists (an entry optionally per band; country names from the country table); US state include and exclude (the state from the message exchange where it carries one, else the log's STATE, a confirmed record first; unknown fails an include list; FCC/ISED and grid are #101); CQ target include and exclude (POTA, SOTA, EU, DX ...; a word on the include list makes that CQ's verdict not grey for this strategy: Band Activity marks it without strike-through, and Alert records it; the operator's own selection keeps its warning). Callers of my call must pass the filters too; a started QSO is always finished (#81). A contest strategy applies its contest's verdict first, then the country, US state and CQ target lists. Each failing line is named in the verdict's reason. Details: WstxRankingControl::StrategyBands, Candidate, NewNeeded, CallerOfMyCall, CountryList, UsStateFilter, UsStateOf, CqTargetList, Verdict. */
        attribute implementation : String = "server/src/strategy.rs; server/src/dxcc.rs; server/src/automation.rs";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    requirement 'CL-097-03' {
        doc /* (#97 decision 3) Order: dropdown rows of criteria, the first decides and the next breaks a tie: Most wanted (Club Log rank); New DXCC, on band, on band and mode; New call, on band; New grid, on band; New CQ zone; New ITU zone; New continent; New prefix; SNR bucket (above 0 dB, -10..0 dB, below -10 dB); SNR (stronger first); Distance (farthest first); Hears us first (a PSK Reporter spot of my call at that station at most 600 s old). Then always SNR, then for an exact tie the lower audio frequency and the call; decode order is never a ranking. With "Calling stations are answered" on, the callers that pass the filters come first, ranked among themselves; with it off a caller of my call has rank null, why "calls my call · not answered" (decided as WSJT-X, whose CQ response None answers no caller automatically and whose "Calling CQ forces Call 1st" is off by default). A contest strategy has no order: it ranks by ContestValueOrder, under the same rule for callers. Details: WstxValueOrder::ValueOrder, ValueCriterion, CallerOfMyCall, Verdict; WstxContestRanking::ContestValueOrder. */
        attribute implementation : String = "server/src/strategy.rs; server/src/contest.rs";
        attribute coverage : ImplementationState = ImplementationState::partial;
    }
    dependency CL_097_02_to_FR_007 from 'CL-097-02' to 'FR-007';
    dependency CL_097_02_to_FR_011 from 'CL-097-02' to 'FR-011';
    dependency CL_097_03_to_FR_007 from 'CL-097-03' to 'FR-007';
    dependency CL_097_02_verified_by_TC_097_004 from 'CL-097-02' to 'TC-097-004';
    dependency CL_097_02_verified_by_TC_097_005 from 'CL-097-02' to 'TC-097-005';
    dependency CL_097_02_verified_by_TC_097_006 from 'CL-097-02' to 'TC-097-006';
    dependency CL_097_02_verified_by_TC_097_007 from 'CL-097-02' to 'TC-097-007';
    dependency CL_097_03_verified_by_TC_097_007 from 'CL-097-03' to 'TC-097-007';
    dependency CL_097_03_verified_by_TC_097_008 from 'CL-097-03' to 'TC-097-008';
    dependency CL_097_02_verified_by_TC_097_016 from 'CL-097-02' to 'TC-097-016';
    dependency CL_097_03_verified_by_TC_097_016 from 'CL-097-03' to 'TC-097-016';
    dependency CL_097_02_verified_by_TC_097_019 from 'CL-097-02' to 'TC-097-019';
    dependency CL_097_03_verified_by_TC_097_019 from 'CL-097-03' to 'TC-097-019';
    dependency CL_039_02_to_FR_007 from 'CL-039-02' to 'FR-007';
    dependency CL_039_02_to_FR_011 from 'CL-039-02' to 'FR-011';
    dependency CL_039_03_to_FR_007 from 'CL-039-03' to 'FR-007';
    dependency CL_039_02_verified_by_TC_039_030 from 'CL-039-02' to 'TC-039-030';
    dependency CL_039_02_verified_by_TC_039_040 from 'CL-039-02' to 'TC-039-040';
    dependency CL_039_02_verified_by_TC_039_047 from 'CL-039-02' to 'TC-039-047';
    dependency CL_042_01_to_FR_007 from 'CL-042-01' to 'FR-007';
    dependency CL_042_01_to_FR_011 from 'CL-042-01' to 'FR-011';
    dependency CL_042_01_verified_by_TC_042_001 from 'CL-042-01' to 'TC-042-001';
    dependency CL_039_02_verified_by_TC_039_002 from 'CL-039-02' to 'TC-039-002';
    dependency CL_039_03_verified_by_TC_039_002 from 'CL-039-03' to 'TC-039-002';
    dependency CL_039_02_verified_by_TC_039_003 from 'CL-039-02' to 'TC-039-003';
    dependency CL_039_03_verified_by_TC_039_003 from 'CL-039-03' to 'TC-039-003';
    dependency CL_039_03_verified_by_TC_039_004 from 'CL-039-03' to 'TC-039-004';
    dependency CL_039_03_verified_by_TC_039_007 from 'CL-039-03' to 'TC-039-007';

    verification 'TC-039-040' {
        doc /* TC-039-040 — The filter and the value order
             CL-039-02
             Setup: the evaluator as a function with the pinned cty.dat fixture, a hand log and hand-authored codec-packed rows for HB9BLA JN47AA (EU) on 20 m FT8: CQ K1ABC FN42 -12 at 1200 Hz, CQ JA1XYZ PM95 -15 at 900 Hz, CQ DL1XYZ JO62 -3 at 1500 Hz, CQ VK2ABC QF56 -20 at 600 Hz, CQ ZS6AA -8 at 2000 Hz (no grid), CQ OH1AA KP20 -3 at 1400 Hz, HB9BLA W1AW FN31 -25 (a caller); the log has K1ABC and W1AW on 20 m, DL1XYZ on 40 m only, OH1AA on 20 m today; a Most Wanted list with JA (rank 40) and VK (rank 90). Distances are computed in the test by the haversine formula written there from the locator and grid centres and the cty.dat centres.
             Steps: new [call] per band with order [snr], [distance], [most_wanted], [most_wanted, distance], [new_dxcc, snr]; new [call, grid, dxcc] (every station of the rows a candidate) with Calling stations are answered off and each needed-first criterion alone before [snr]: [new_dxcc] (log: a DL QSO on 40 m), [new_dxcc_band] (on 20 m: DL worked on 40 m only), [new_dxcc_band_mode] (an FT4 QSO with JA on 20 m), [new_call] (K1ABC logged), [new_call_band], [new_grid] (FN42 logged on 40 m), [new_grid_band] (FN42 logged on 40 m; a row without grid; a call with a logged 20 m QSO without grid); the same with the station band unknown; new [call] per ever; worked since today with Calling stations are answered on; DL1XYZ and OH1AA at the same SNR (an exact tie except frequency); two verdicts at the same SNR and frequency; Calling stations are answered on and off with order [snr]; an empty order list; the caller W1AW failing every filter line (worked, region, minimum SNR -10).
             Expected (hand-worked): each needed-first criterion puts the needed stations before the others and leaves SNR order inside each group, the caller W1AW without a rank (callers off): [new_dxcc] DL1XYZ after the rest; [new_dxcc_band] DL1XYZ needed on 20 m; [new_dxcc_band_mode] JA1XYZ needed (FT4 is another mode); [new_call] K1ABC after; [new_call_band] K1ABC and OH1AA after; [new_grid] K1ABC (FN42) after; [new_grid_band] K1ABC (FN42 not on 20 m) needed, the row without grid and the call with an unknown grid status not needed, a band unknown nothing needed; new_call_band excludes K1ABC and W1AW as candidates (worked on 20 m) and keeps DL1XYZ; [snr]: DL1XYZ, OH1AA (frequency 1400 before 1500 when tied: OH1AA first), ZS6AA, JA1XYZ, VK2ABC; [distance]: VK2ABC, JA1XYZ, ZS6AA (entity centre), OH1AA, DL1XYZ; [most_wanted]: JA1XYZ, VK2ABC, then the rest by SNR; [most_wanted, distance] the same for the listed, then by distance; band unknown: no candidate for new [call] per band; worked since today: OH1AA not needed by new [call] per band, W1AW (not in that log) a caller that passes, first; the exact tie of SNR and frequency ordered by call; Calling stations are answered on: W1AW first; off: W1AW has no rank (CL-097-03); the empty list: SNR order; W1AW ranks only where it passes the filters and fails them in the step failing every filter line (TC-097-007); the reasons name the needed whats; sequence (decode order) never changes an order. Red on the parent: the criteria do not exist.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-02';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
    verification 'TC-097-004' {
        doc /* TC-097-004 — The strategy's bands
             CL-097-02
             Setup: the evaluator with the pinned cty.dat fixture and hand-authored codec-packed rows; a strategy with bands ["20m", "40m"]. The run's steps off the bands are TC-097-018's.
             Steps: evaluate with the station band 20m, 15m and unknown; the same strategy with bands null on 15m.
             Expected: on 20m the candidates ranked; on 15m every verdict rank null with why "band not in the strategy", unknown "band unknown"; bands null ranks on 15m. Red on the parent: bands is refused.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-02';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    verification 'TC-097-005' {
        doc /* TC-097-005 — What must be new, new per, new means and worked since
             CL-097-02
             Setup: the evaluator with the pinned cty.dat fixture and a hand log (worked and confirmed QSOs per band, mode and date, with and without grid) for HB9BLA JN37VL on 20m FT8; the expected verdicts hand-worked in the test from the log and the cty.dat entries.
             Steps: each NewWhat alone with each new_per and each new_means: dxcc; call; grid (no grid in the message, a logged QSO without grid); cq_zone; itu_zone (an entity whose cty.dat entry overrides the ITU zone); continent; prefix (the WpxPrefix table cases); two whats (either counts); worked_since today and from_to with an undated record; region dx and selected; min_snr_db; treat_73_as_cq on and off; the station band unknown with new_per band.
             Expected: the hand-worked tables: each what new exactly where the log lacks its key per the chosen per and means; D13 grid rules; the override zone used; an undated record counts only for any time; band unknown: nothing new per band or band_mode; RR73 to another counted as calling only with treat_73_as_cq. Red on the parent: the keys are refused.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-02';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    verification 'TC-097-007' {
        doc /* TC-097-007 — Callers of my call pass the filters and are answered only when Calling stations are answered is on
             CL-097-02, CL-097-03
             Setup: the evaluator with the pinned cty.dat fixture, HB9BLA on 20m; the built-in Casual (call, per band, not worked; Calling stations are answered on); a log with W1AW worked on 20m; rows HB9BLA W1AW FN31 (+5), HB9BLA N1NEW FN31 (-9), CQ K1ABC FN42 (-1). The run's steps with callers are TC-097-018's.
             Steps: evaluate Casual; the same with Calling stations are answered off and order [snr]; a caller failing region dx, min SNR -5, a country exclude, a state include.
             Expected (oracle: the operator's decision 2 on #97, CL-097-03, WstxRankingControl::Verdict; WSJT-X with the CQ response None answers no caller automatically, widgets/mainwindow.cpp 7481-7496): W1AW rank null, why "calls my call · not new"; N1NEW first with callers on, then K1ABC; with callers off N1NEW has rank null, kind none, why "calls my call · not answered", and K1ABC alone is ranked; each failing caller names its line ("calls my call · region", "· below min SNR", "· country list", "· state list"). Red on the parent: with callers off N1NEW is ranked by SNR after K1ABC.
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-097-02';
            verify 'CL-097-03';
        }
        attribute executable : String = "server/src/strategy97_tests.rs";
    }
    verification 'TC-097-008' {
        doc /* TC-097-008 — The order criteria
             CL-097-03
             Setup: the evaluator with the TC-039-040 rows extended by stations at SNR +1, 0, -10, -11 and unknown; a feed without a connection fed hand-authored spots of my call at JA1XYZ and VK2ABC; the expected orders hand-worked in the test (distances by the haversine formula written there).
             Steps: order [snr_bucket]; [snr_bucket, distance]; [hears_us] with PskrUse on and off; [new_cq_zone], [new_itu_zone], [new_continent], [new_prefix], [new_dxcc_band_mode] each before [snr]; [most_wanted, snr]; a contest strategy evaluated; the WW Digi built-in (contest_tests: WW Digi in force on 20m, K1OLD logged in the period) with CQ WW JA1XYZ PM95, the non-dupe caller HB9BLA VK2ABC QF56 and the dupe caller HB9BLA K1OLD FN20, with Calling stations are answered on and off.
             Expected: +1 first; 0 and -10 in the middle bucket; -11 last; unknown after them; inside a bucket SNR, frequency, call (alone) or farthest first (with distance); JA1XYZ and VK2ABC first with PskrUse on, the plain SNR order with it off; each new criterion puts the new stations first with SNR order inside; the contest strategy ranks by ContestValueOrder; decode order never changes an order. WW Digi: on, VK2ABC rank 0 and JA1XYZ rank 1; off, VK2ABC rank null with why "calls my call · not answered" and JA1XYZ rank 0; K1OLD rank null either way. Red on the parent: with callers off the non-dupe caller VK2ABC keeps a rank (ranked among the others).
             2 — Isolated automated tests; Windows development PC. */
        attribute automation : AutomationState = AutomationState::partial;
        objective {
            verify 'CL-097-03';
        }
        attribute executable : String = "server/src/strategy97_tests.rs; server/src/contest_tests.rs";
    }
}

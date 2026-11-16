package WstxValueOrder {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-026';
    private import WstxRankingPart::RankingService;
    private import WstxRankingControl::*;
    private import WstxDecodes::ResultRecord;
    private import WstxDecodes::PeriodView;
    private import WstxLogControl::EntityRequest;
    private import WstxLogControl::EntityAnswer;
    private import WstxLogControl::CallEntity;
    private import WstxOperatingChain::WorkedSet;
    private import WstxOperatingChain::WorkedCategory;
    private import WstxLogControl::WorkedStatus;
    private import WstxOperatingChain::Standing;
    private import WstxOperatingChain::DateWindow;
    private import WstxHearing::HeardByReport;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import ModelNotes::NotStated;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    // ---- One verdict for each decoded message ---------------------------------------------

    requirement 'CL-039-02' {
        subject ranking : RankingService;
        doc /* Ranking MUST give each decoded standard message of a sender with a call one
             verdict under the strategy it evaluates, for the decodes of each period and
             for the records the station service asks for (VerdictRule, Evaluation). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-039-02'; }

    attribute def VerdictRule {
        doc /* How the Verdict of a record is found under a strategy of class strategy.
             A ResultRecord has a verdict when it is decoded, its message is a standard
             message and its sender is a call. A sender that is a hashed call has none,
             also when the hash is filled in.
             The tests are made in this order, and the first that holds decides:
             the sender is ignored (WstxIgnoreLists::IgnoreListsRule);
             the record is a CQ that DirectedCqRule leaves to others: no rank, grey, why
             "CQ <directive> — not for <continent>", or "not for this station" while the
             station's continent is unknown;
             the sender is the profile's call: no rank, why "my own message";
             the station is off the strategy's bands (StrategyBandsRule): no rank;
             the sender is wanted and can be called (WstxWantedList::WantedRule): a
             rank, whatever the filter says;
             the record is a caller (CallerOfMyCall) or a Candidate: a rank, when every
             line of the filter holds; otherwise no rank, with the line that fails
             first as why.
             Every record that has a rank is ranked by ValueOrder; its rank is its place
             among the ranked records of the evaluation, from 0.
             A RankedList holds the verdicts of the ranked records by their rank and
             then those of the others in the order of the records.
             Under a strategy of class contest
             WstxContestRanking::ContestVerdictRule finds the verdict. */
    }

    attribute def Evaluation {
        doc /* When ranking evaluates.
             For each PeriodView, while a strategy is active, the records of the view
             are evaluated under it and given as one RankedList, also when the view is
             published again for its period; ranking gives it without being asked, to
             Auto and to the station service.
             An EvaluateRequest is answered with the verdicts of the records it names,
             under its draft, and without one under the active strategy. Without either
             it is refused (RankingRefusal::notConfigured), and for another job than
             the current one with RankingRefusal::staleRequest.
             A draft of class contest is counted over the period of the contest in
             force when that is its contest, and otherwise over every QSO of the
             logbook.
             For an EvaluateRequest ranking waits for the WorkedSet that holds the
             latest change of the logbook. For a PeriodView it takes the set it has. */
    }

    // ---- CQs that leave the station out ---------------------------------------------------

    requirement 'CL-039-03' {
        subject ranking : RankingService;
        doc /* Ranking MUST mark as grey, and leave without a rank, each CQ whose
             directive leaves the station out (DirectedCqRule, MyContinent). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-039-03'; }

    attribute def DirectedCqRule {
        doc /* Which CQ is for the station.
             The directive of a CQ is what stands between CQ and the sender's call:
             "CQ DX K1ABC FN42" has DX. A CQ without one, and a record that is no CQ,
             are for the station.
             A CQ with a directive is for the station in three cases, and leaves it out
             in every other:
             the directive is DX, and the station's continent (MyContinent) and the
             sender's are both known and differ;
             the directive is one of the station's CQ words (RankingContext::cqWords);
             the directive is one of the CQ words of the strategy ranking evaluates,
             of either class (its CqTargetList::included), or of the contest that
             strategy ranks by (WstxContestRanking::ContestDirective).
             The sender's continent is that of its entity (EntityAnswer); a sender
             without an entity has none. */
    }

    attribute def MyContinent {
        doc /* The station's continent.
             It is RankingContext::continent when the operator has set one; otherwise
             the continent of the entity of the profile's call; otherwise the continent
             of the entity whose position is nearest to the centre of the profile's
             locator; otherwise it is unknown.
             RankingState::derivedContinent is the second of these alone. */
        @NotStated {
            what = "how ranking learns the entity nearest to a locator: an "
                + "EntityRequest asks by a call";
        }
    }

    verification 'TC-039-002' {
        doc /* Directed CQs, the station's continent and the verdicts.
             Setup: the evaluator alone with the bundled country file, for HB9BLA in EU
             on 40m in FT8 with the CQ word EU and an empty logbook; decodes written by
             hand.
             (a) For a station in EU with the CQ word EU: CQ EU is for it; CQ NA from NA
             is not; CQ DX from EU is not, from AS it is, from a sender without a
             continent it is not; CQ TEST, CQ POTA and CQ JA are not. Without EU among
             its CQ words CQ EU is not. For a station in NA with the CQ word NA: CQ NA
             is, CQ EU is not, CQ DX from AS is and from NA is not.
             (b) New call, Treat 73 as CQ off; CQ K1ABC FN42 at -12 dB, CQ DL1XYZ JO62
             at -3, CQ NA W1AW FN31, CQ EU G4ABC IO91 at -8, CQ DX OH1AA KP20, CQ DX
             JA1XYZ PM95 at -15, W1AW K1ABC RR73, HB9BLA VK2ABC QF56 at -20 and CQ
             TEST N1MM FN31: the list is VK2ABC with rank 0 and "calls my call", DL1XYZ
             1, G4ABC 2, K1ABC 3 with "new: call", JA1XYZ 4; then W1AW grey with "CQ NA
             — not for EU", OH1AA grey, the RR73 not grey with "not a CQ", N1MM grey.
             (c) Treat 73 as CQ on: K1ABC's RR73 to W1AW has a rank; an RR73 to HB9BLA
             has none.
             (d) The station's continent unknown and no CQ words: the five CQs with a
             directive are grey.
             (e) CQ HB9BLA JN47: "my own message". CQ W1AW/R FN31: "callsign guard";
             W1AW passes that guard, K1, ABCDE and W1AW/R do not.
             (f) The continent OC set by the operator, for HB9BLA: OC. Not set: HB9BLA
             with the locator FN42 is EU; K1ABC without a locator is NA; K1ABC/MM in
             JN37 is EU, in FN42 NA, in PM95 AS, in QF56 OC, in GG87 SA; without a call
             and a locator it is unknown.
             (g) Planned, no test yet: with the CQ words EU and CH, CQ CH is for the
             station whatever its continent; under a strategy of class contest whose
             included CQ targets hold POTA, CQ POTA is for it. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-03'; verify 'CL-039-02'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_002_continent_and_directed_cq_rule; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_002_verdicts_grey_reasons_and_treat_73; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_002_my_continent_from_config_call_and_locator";
        }
    }

    // ---- What is new ----------------------------------------------------------------------

    requirement 'CL-042-01' {
        subject ranking : RankingService;
        doc /* Ranking MUST judge what is new about a sender from what the log says has
             been worked and confirmed, and claim nothing as new that it cannot check
             (NewNeeded). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-042-01'; }

    attribute def NewNeeded {
        doc /* Whether one NewWhat is new for a sender, in one NewPer, by one Needed.
             Ranking asks the log for the WorkedSet of the strategy's WorkedSince: a
             DateWindow without dates for 'all', the current UTC date twice for today,
             the two dates for from_to.
             The key is looked up in the WorkedSet by its WorkedCategory. dxcc,
             cq_zone, itu_zone and continent take the key from the sender's entity
             (EntityAnswer); grid takes the first four characters of a locator in the
             message.
             The scope ever is every QSO of the set; band is the station's band in any
             mode; band_mode is that band in the operating mode.
             not_worked holds when the Standing of the key in the scope is not worked;
             not_confirmed when it is not worked or not confirmed.
             Nothing is new: for the entity keys while the sender has no entity; in
             the scopes band and band_mode while the station's band is unknown; for
             grid when the message has no locator, and when the set says that a QSO
             with the sender has no grid; and for every key while ranking has no
             WorkedSet. */
        attribute what : NewWhat;
        attribute per : NewPer;
        attribute means : Needed;
        attribute category : WorkedCategory;
        attribute window : DateWindow;
        attribute standing : Standing;
    }

    verification 'TC-042-001' {
        doc /* A new entity and a new zone against a logbook written by hand.
             Setup: the evaluator alone with the bundled country file, for HB9BLA on
             40m in FT8. The logbook: DL1ABC on 40m in FT8, not confirmed; F1ABC on 40m
             in FT4, confirmed; JA1XYZ on 20m in FT8, confirmed; K2ABC without a band;
             Q1ABC, which has no entity, on 40m. CQs of DL2XYZ, F5ABC, JA2ABC, VK2ABC,
             K1ABC, XX1ABC, which has no entity, and DL1ABC.
             (a) not_worked: a new dxcc ever is VK2ABC alone; per band JA2ABC, VK2ABC
             and K1ABC; per band_mode also F5ABC. A new cq_zone ever is VK2ABC alone.
             (b) not_confirmed: a new dxcc ever is DL2XYZ, VK2ABC, K1ABC and DL1ABC; per
             band also JA2ABC; per band_mode also F5ABC. A new cq_zone ever is VK2ABC
             and K1ABC.
             (c) not_worked: a new call and a new prefix are all but DL1ABC; a new grid
             all but XX1ABC and DL1ABC.
             (d) The station's band unknown: nothing is new per band or band_mode; a
             new dxcc ever is VK2ABC still.
             (e) No WorkedSet: nothing is new for any NewWhat. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-042-01'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_030_each_goal_in_both_needed_settings";
        }
    }

    verification 'TC-097-005' {
        doc /* Each thing that can be new, in each scope and meaning.
             Setup: as for a new entity against a logbook written by hand; the logbook
             holds DL1ABC on 40m in FT8, not confirmed, F1ABC on 40m in FT4, confirmed,
             and JA1XYZ on 20m in FT8, confirmed. CQs of DL2XYZ, F5ABC, JA2ABC, DL1ABC
             and F1ABC.
             (a) not_worked. dxcc: ever none, per band JA2ABC, per band_mode F5ABC,
             JA2ABC and F1ABC. call: ever and per band DL2XYZ, F5ABC and JA2ABC; per
             band_mode also F1ABC. cq_zone and continent: ever none, per band JA2ABC.
             itu_zone per band: JA2ABC. prefix ever, grid ever and grid per band:
             DL2XYZ, F5ABC and JA2ABC.
             (b) not_confirmed: a new dxcc ever is DL2XYZ and DL1ABC; a new continent
             ever is none.
             (c) New dxcc and call per band_mode: F5ABC has "new: dxcc, call on 40m
             FT8"; DL2XYZ has a rank as a new call.
             (d) The station's band unknown: no new call per band and no new dxcc per
             band_mode.
             (e) "W1AW K2NEW RR73" with Treat 73 as CQ on: K2NEW has a rank; off:
             "not a CQ". */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-042-01'; verify 'CL-097-02'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_005_what_must_be_new_per_and_means_by_hand";
        }
    }

    // ---- The band and the filter ----------------------------------------------------------

    requirement 'CL-097-02' {
        subject ranking : RankingService;
        doc /* Ranking MUST rank only on the strategy's bands, and there only a record
             that passes every line of the strategy's filter, and name in the verdict
             the line that fails (StrategyBandsRule, Candidate, CallerOfMyCall,
             CountryListRule, UsStateFilterRule, CqTargetListRule). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-097-02'; }

    attribute def StrategyBandsRule {
        doc /* A strategy without bands ranks on every band. A strategy with bands ranks
             only while the station's band is one of them. On another band every
             verdict has no rank and the why "band not in the strategy", and while the
             station's band is unknown "band unknown". */
    }

    attribute def Candidate {
        doc /* The filter of a strategy of class strategy. A record is a candidate when
             every line holds; the first line that fails is the why.
             The sender's call has at least three characters, with a digit and a
             letter, and does not end in /R: "callsign guard".
             The record is a CQ, or with treat73AsCq an RR73 or a 73 to another call
             than the profile's: "not a CQ".
             The region holds, by RegionKind: for dx the station's continent
             (MyContinent) and the sender's are both known and differ; for selected the
             sender's continent is known and listed: "region".
             The SNR is known and not below minSnrDb, when the strategy has one:
             "below min SNR".
             At least one NewWhat of the strategy is new (NewNeeded, with the
             strategy's newPer, newMeans and workedSince): "not new".
             CountryListRule holds: "country list". UsStateFilterRule holds: "state
             list". CqTargetListRule holds: "CQ target".
             The why of a candidate is "new: " with the names of the NewWhat that are
             new, and " on <band>" for the scope band or " on <band> <MODE>" for
             band_mode. */
    }

    attribute def CallerOfMyCall {
        doc /* A caller is a record whose message goes to the profile's call and is no
             RR73 and no 73.
             A caller has a rank when RankingKeys::callersFirst is on and every line of
             Candidate holds for it but three: the callsign guard, the CQ line and
             CqTargetListRule are not asked of it. Its why is "calls my call".
             A caller that fails a line has no rank and the why "calls my call · " with
             that line.
             With callersFirst off a caller that passes has no rank and the why "calls
             my call · not answered". */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: with the CQ response None it "
                + "answers no caller of its CQ by itself, which callersFirst off "
                + "follows";
        }
    }

    attribute def CountryListRule {
        doc /* A prefix entry matches a sender whose call begins with it. A country
             entry matches a sender whose entity has that name, without regard to
             letter case; it matches no sender without an entity.
             An entry with bands matches only while the station's band is one of them.
             The line holds when no excluded entry matches and, when the list of
             included entries is not empty, one of them matches. */
    }

    attribute def UsStateFilterRule {
        doc /* The state of a sender is known only for a sender whose entity is the
             United States, Alaska or Hawaii. It is the state in the exchange of an
             RTTY Roundup message of that sender among the records evaluated; without
             one, the state the WorkedSet gives for its call.
             The line holds when the state is not on the excluded list and, when the
             included list is not empty, is known and on it. */
    }

    attribute def CqTargetListRule {
        doc /* The line is asked of a record that is no caller.
             It fails for a CQ whose directive is on the excluded list. When the
             included list is not empty it holds only for a CQ whose directive is on
             it: a CQ without a directive, and an RR73 or 73 that counts as a CQ, fail.
             The included words are also the strategy's CQ words of DirectedCqRule. */
    }

    verification 'TC-097-004' {
        doc /* The strategy's bands.
             Setup: the evaluator alone, for HB9BLA in EU with an empty logbook; a
             strategy for 20m and 40m; CQ K1ABC FN42 and HB9BLA W1AW FN31.
             (a) On 20m: W1AW, then K1ABC.
             (b) On 15m: no verdict has a rank, each with "band not in the strategy".
             (c) The band unknown: each with "band unknown".
             (d) The same strategy without bands, on 15m: both have a rank. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-02'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_004_off_the_strategy_bands_nothing_is_ranked";
        }
    }

    verification 'TC-039-030' {
        doc /* The grid, the region, the minimum SNR and the window of the filter.
             Setup: the evaluator alone with the bundled country file, for HB9BLA in EU
             on 40m in FT8, new call unless said; for (g) the station on a throw-away
             profile with a scripted clock and decodes written by hand.
             (a) New grid, with K2ABC logged without a grid, K3ABC with an empty one and
             K4ABC in FN42: "W1AW DL9ZZ RR73", CQ K2ABC FN55, CQ K3ABC FN55 and CQ K6ABC
             FN42 are "not new"; CQ K4ABC FN55 and CQ K5ABC FN66 are "new: grid".
             (b) CQs of K1ABC at -10 dB, DL2XYZ at -5, JA2ABC at -1 and XX1ABC, which has
             no entity, at 0. Region all: XX1ABC, JA2ABC, DL2XYZ, K1ABC. dx for a
             station in EU: JA2ABC, K1ABC; in NA: JA2ABC, DL2XYZ; with an unknown
             continent: none. selected AS and NA: JA2ABC, K1ABC; selected SA: none.
             (c) A minimum of -10 dB: a CQ at -10 has a rank, at -11 and without an SNR
             it has none. No minimum: a CQ without an SNR has a rank.
             (d) Region OC, a minimum of 20 dB and a list that ranks Australia first:
             CQ VK2ABC at +25 has rank 0 and a why that ends with the list and its
             rank; the caller DL1ABC at -20 has no rank and "calls my call · region".
             Callers K1ABC at -9 and K2ABC at -2 that pass: K2ABC, then K1ABC.
             (e) Order most_wanted; CQs of G4XYZ at +5, F5ABC at 0, DL2XYZ at -2, VK2ABC
             at -20 and JA2ABC at -5. Without a list: by SNR. With a list that ranks
             Germany 1 and Australia 2: DL2XYZ, VK2ABC, G4XYZ, F5ABC, JA2ABC. Three
             stations of Germany at -9, -1 and -1 dB: the two at -1 by their
             frequency, then the third.
             (f) A WorkedSet of one date that holds F1ABC and not DL1ABC: CQ DL1ABC has
             a rank, CQ F1ABC has none.
             (g) After a QSO with K1ABC completed now, CQ K1ABC under a draft with
             worked since all and today: no rank; from_to within 2020: rank 0; from_to
             today to today: no rank. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-02'; verify 'CL-042-01'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_030_a_missing_grid_is_unknown_never_new; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_030_region_min_snr_for_an_eu_and_a_non_eu_profile; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_030_a_caller_beats_a_most_wanted_station_"
                + "and_ignores_goal_region_and_snr; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_030_value_order_with_and_without_a_list; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_030_worked_window_from_dated_records; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_030_today_and_from_to_read_the_log_of_the_window";
        }
    }

    verification 'TC-097-006' {
        doc /* The country, US state and CQ target lists.
             Setup: the evaluator alone with the bundled country file, for HB9BLA in EU
             on 20m; W6ABC is logged on 40m with the state CA, confirmed, and later
             with NV, not confirmed. New call per band, Treat 73 as CQ on. CQ POTA
             K1ABC FN42, CQ SOTA W7XYZ DN31, CQ DX JA1XYZ PM95, CQ EU DL1XYZ JO62 and
             CQs of W6ABC, VE3ABC, K9NOR and VK9LA.
             (a) Included, the prefix VK9: VK9LA alone. Included, the country "lord
             howe island": VK9LA alone.
             (b) Included, the prefix DL for 40m: on 20m none; on 40m DL1XYZ.
             (c) Included, the prefix W: W6ABC alone. With the prefix W6 excluded:
             none. Excluded, the country United States: none of K1ABC, W6ABC, W7XYZ
             and K9NOR.
             (d) Included, the state CA: W6ABC alone; NV: none. Excluded, CA: not
             W6ABC; K9NOR and VE3ABC stay. An RTTY Roundup message of K1RU with the
             state MA and CQ K1RU FN42, with MA included: K1RU has a rank.
             (e) Included, the CQ target POTA: K1ABC alone has a rank, 0, and is not
             grey; W6ABC has "CQ target". Without the list K1ABC is grey. Excluded,
             DX: not JA1XYZ; W6ABC stays.
             (f) The built-in POTA/SOTA with K1ABC logged on 20m the day before and
             W7XYZ on this date: K1ABC alone has a rank; W7XYZ is "not new". */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-02'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_006_country_state_and_cq_target_lists";
        }
    }

    verification 'TC-097-007' {
        doc /* Callers of the profile's call pass the filter, and are answered only
             when the strategy says so.
             Setup: the evaluator alone, for HB9BLA on 20m with W1AW logged on 20m in
             FT8; the built-in Casual; HB9BLA W1AW FN31 at +5 dB, HB9BLA N1NEW FN31
             at -9 and CQ K1ABC FN42 at -1.
             (a) W1AW has no rank and "calls my call · not new"; then N1NEW, K1ABC.
             (b) callersFirst off, order snr: K1ABC alone has a rank; N1NEW has
             "calls my call · not answered".
             (c) For a station in NA, N1NEW has no rank: with region dx "calls my
             call · region"; with a minimum of -5 dB "calls my call · below min SNR";
             with the prefix N1 excluded "calls my call · country list"; with the
             state CA included "calls my call · state list". */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-02'; verify 'CL-097-03'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_007_callers_of_my_call_pass_the_filters";
        }
    }

    // ---- The order ------------------------------------------------------------------------

    requirement 'CL-097-03' {
        subject ranking : RankingService;
        doc /* Ranking MUST order the records that have a rank by the criteria of the
             strategy, the first deciding and each next one breaking a tie, and never
             by the order in which they were decoded (ValueOrder, StationDistance). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-097-03'; }

    attribute def ValueOrder {
        doc /* The order of the ranked records under a strategy of class strategy.
             The wanted records come first (WstxWantedList::WantedRule). Then, with
             callersFirst on, the callers, and then the candidates. Within each of these
             groups the records are ordered as follows.
             Then the criteria of RankingKeys::order, each as its ValueCriterion says:
             most_wanted: a sender whose entity is on the Most Wanted list before one
             that is not, the lower rank of the list first
             (WstxMostWanted::MostWantedListRule);
             new_dxcc, new_dxcc_band, new_dxcc_band_mode, new_call, new_call_band,
             new_grid, new_grid_band, new_cq_zone, new_itu_zone, new_continent,
             new_prefix: a sender for which that NewWhat is new before one for which
             it is not, by NewNeeded in the scope the name ends with, ever without an
             ending, and with the strategy's newMeans and workedSince;
             snr_bucket: an SNR above snrBucketUpperDb, then one from snrBucketLowerDb
             up to it, then one below, then an unknown one; equal within a group;
             snr: the stronger first, an unknown SNR last;
             distance: the farther first by StationDistance, an unknown one last;
             hears_us: a sender whose call is in HeardByReport::heardBy before one
             that is not; equal while HeardByReport::inUse is false.
             After the criteria always the SNR, the stronger first and an unknown one
             last; then the lower audio frequency, an unknown one last; then the call
             in the order of its characters.
             A record ranked while most_wanted is a criterion and its entity is on
             the list has " · Most Wanted #" and the rank of the list at the end of
             its why. */
        attribute snrBucketUpperDb : Integer = 0;
        attribute snrBucketLowerDb : Integer = -10;
    }

    attribute def StationDistance {
        doc /* The distance of a sender: the great circle on a sphere of 6371 km radius
             from the centre of the profile's locator to the centre of the first four
             characters of the locator in the message, and without one to the position
             of the sender's entity (CallEntity), in whole kilometres, cut off.
             It is unknown while the profile has no locator, and for a sender without
             a locator in the message and without an entity. */
    }

    verification 'TC-039-040' {
        doc /* The filter and the order together.
             Setup: the evaluator alone with the bundled country file, for HB9BLA in
             JN47AA in EU on 20m in FT8; K1ABC and W1AW logged on 20m, DL1XYZ on 40m; a
             list that ranks Japan 40 and Australia 90. CQ K1ABC FN42 at -12 dB and
             1200 Hz, CQ JA1XYZ PM95 at -15 and 900, CQ DL1XYZ JO62 at -3 and 1500, CQ
             VK2ABC QF56 at -20 and 600, CQ ZS6AA at -8 and 2000, CQ OH1AA KP20 at -3
             and 1400, HB9BLA W1AW FN31 at -25. New call per band.
             (a) Order snr: OH1AA, DL1XYZ, ZS6AA, JA1XYZ, VK2ABC. OH1AA has "new: call
             on 20m", K1ABC "not new", W1AW "calls my call · not new".
             (b) Order distance: VK2ABC, JA1XYZ, ZS6AA, OH1AA, DL1XYZ; each distance is
             that from the centre of JN47AA to the centre of the grid, for ZS6AA to
             the position of South Africa.
             (c) Order most_wanted: JA1XYZ, VK2ABC, OH1AA, DL1XYZ, ZS6AA; the why of
             JA1XYZ ends with the list and 40. Order most_wanted, distance: JA1XYZ,
             VK2ABC, ZS6AA, OH1AA, DL1XYZ.
             (d) Order new_dxcc, snr: OH1AA, ZS6AA, JA1XYZ, VK2ABC, DL1XYZ.
             (e) CQ OH1AA, CQ ZS6AA and the caller N1NEW, order snr: with callersFirst
             on N1NEW, OH1AA, ZS6AA; off OH1AA, ZS6AA.
             (f) An empty order gives the order of snr.
             (g) Region AS and a minimum of -10 dB: nothing has a rank; W1AW has "calls
             my call · region".
             (h) The station's band unknown: nothing has a rank.
             (i) The same records numbered backwards: the same order. CQ AB1AA and CQ
             AA1AA, both at -10 dB and 700 Hz: AA1AA first.
             (j) A WorkedSet of the current date, with OH1AA logged on 20m on it and
             DL1XYZ in 2025: W1AW, DL1XYZ, ZS6AA, K1ABC, JA1XYZ, VK2ABC. The set of
             every QSO: W1AW, ZS6AA, K1ABC, JA1XYZ, VK2ABC.
             (k) New call, grid and dxcc per band_mode, callersFirst off, one
             criterion and its own logbook each. new_dxcc with Germany worked on 40m:
             DL1XYZ last. new_dxcc_band with Germany worked on 40m and the USA on 20m:
             K1ABC last, DL1XYZ needed. new_dxcc_band_mode with Japan worked on 20m in
             FT4 and Australia in FT8: VK2ABC last. new_call with K1ABC and W1AW
             worked: K1ABC last. new_call_band with K1ABC, W1AW and OH1AA worked on
             20m: OH1AA and K1ABC last. new_grid with FN42 worked on 40m: ZS6AA, which
             sends no grid, and K1ABC last. new_grid_band with FN42 worked on 40m and
             JA1XYZ on 20m without a grid: K1ABC new, ZS6AA and JA1XYZ last; with the
             band unknown the order of the SNR alone, JA1XYZ without a rank. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-03'; verify 'CL-039-02'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::"
                + "tc_039_040_the_filter_and_the_value_order; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_040_each_needed_first_criterion_with_its_own_log";
        }
    }

    verification 'TC-097-008' {
        doc /* The criteria of the order.
             Setup: the evaluator alone, for HB9BLA in EU on 40m with an empty logbook,
             new call; for (e) the built-in of WW Digi on 20m with K1OLD logged in the
             period.
             (a) Order snr_bucket; CQs at -11 dB, 0, an unknown SNR, +1 and -10: +1,
             then 0 and -10, then -11, then the unknown one.
             (b) Order hears_us; CQ DL1XYZ at +5 dB, CQ JA1XYZ at -15, CQ VK2ABC at
             -20. With JA1XYZ and VK2ABC in heardBy: JA1XYZ, VK2ABC, DL1XYZ. Without a
             report in use: DL1XYZ, JA1XYZ, VK2ABC.
             (c) Order new_continent, with a QSO in EU logged: JA1XYZ, VK2ABC,
             DL1XYZ.
             (d) The records of (a) numbered backwards: the same order.
             (e) CQ WW JA1XYZ PM95 at -18 dB, HB9BLA VK2ABC QF56 at -20 and HB9BLA
             K1OLD FN20 at +9. callersFirst on: VK2ABC 0, JA1XYZ 1, K1OLD no rank.
             Off: JA1XYZ 0; VK2ABC no rank with "calls my call · not answered"; K1OLD
             no rank.
             (f) Planned, no test yet: the criteria new_cq_zone, new_itu_zone and
             new_prefix each put a sender for which it is new first; two records equal
             in every criterion and in the SNR are ordered by the lower audio
             frequency; a wanted record stands before a caller and a candidate. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-03'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_008_snr_bucket_hears_us_and_the_new_criteria; "
                + "server/src/contest_tests.rs::"
                + "tc_097_008_a_contest_strategy_with_callers_off_ranks_no_caller";
        }
    }

    // ---- The entity and what is new, on each decoded record -------------------------------

    requirement 'CL-055-02' {
        subject ranking : RankingService;
        doc /* Ranking MUST tell, for each decoded record whose sender it can name, the
             sender's entity, what is new about the sender against the logbook, and
             whether the sender has been worked (DecodedEntity). */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/dxcc.rs"; }
    }
    #derivation connection { end #original ::> 'FR-026'; end #derive ::> 'CL-055-02'; }

    attribute def DecodedEntity {
        doc /* What ranking adds to a ResultRecord, as one DecodedFacts.
             The sender of a decoded record is: for a standard message its sender; for
             a message with a nonstandard call the call that sends it; for a
             DXpedition message the call of the DXpedition. The sender may be a hashed
             call that is filled in. A hashed call that is not filled in, a free text
             and telemetry name no sender, and such a record gets nothing.
             entity: from the EntityAnswer for the sender. Its km is the great circle
             from the centre of the profile's locator to the position of the entity,
             rounded to a whole kilometre.
             flags: from the WorkedSet of every QSO; ranking waits for the set that
             holds the latest change of the logbook. A flag holds when its key is not
             worked: for a flag without the ending Band in any QSO, for one with it on
             the station's band in any mode. The flags
             with the ending Band are given only while the station's band is known,
             the grid flags only for a message with a locator, the flags of the
             entity only for a sender with one. A DXpedition message and a station
             without a WorkedSet get no flag.
             worked: the WorkedStatus of the sender for the station's band and the
             mode of the job. It is given only for a standard message whose sender is
             a call, and only while the station's band is known.
             Ranking gives the DecodedFacts of a record once, when the record is
             decoded, and again for every record of the current PeriodView whenever the
             logbook (also by another station of the operator), the country file or the
             station's band changes. The facts of an older period stay as they were
             given. */
        attribute entity : CallEntity[0..1];
        attribute worked : WorkedStatus[0..1];
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: LogBook::match with "
                + "highlighting by mode off, the six categories each for the logbook "
                + "and for the band";
        }
        @DiffersFromSource {
            what = "WSJT-X looks a decode up when it prints it and colours it at "
                + "once, never again; ranking gives the facts, again for the current "
                + "period after a change, and the browser colours.";
        }
    }

    verification 'TC-055-002' {
        doc /* The entity, the flags and the worked status of decoded records.
             Setup: the station on a throw-away profile HB9BLA with a logbook taken
             from a file and decodes written by hand, read as the station gives them.
             (a) The logbook holds DL1ABC in JO62 on 20m in FT8, K1ABC in FN42 on 40m
             and W1AW on 20m in FT4. Without a band: CQ K1ABC FN42 has the entity
             U.S.A., NA, CQ zone 5, ITU zone 8, 7706 km and no flag; CQ DL2XYZ JO62
             has newCall alone; a free text has nothing.
             (b) On 20m: K1ABC has newCallBand and newGridBand; CQ W1AW FN31 has no
             flag; DL2XYZ has Germany, EU, 14, 28, 465 km, newCall and newCallBand; CQ
             JA1XYZ PM95 has all twelve; HB9BLA G4ABC IO91 has the flags of the call,
             the grid, the entity and the ITU zone, and none of the continent and the
             CQ zone.
             (c) After DL2XYZ is logged on 20m: no flag.
             (d) DL1ABC logged on 20m in FT8. "K9XX G4XYZ -10" has England and the
             flags of the call, the entity and the ITU zone; "K9XX YO3ABC R-07" has
             Romania and newDxcc; "K9XX DL1ABC RR73" has Germany and no flag.
             (e) CQ HF6FIRAC, a nonstandard call: Poland, newDxcc, no flag of the grid.
             "OH2DKQ <CT9/DL7VXX> -02" and "HF6FIRAC <CT9/DL7VXX> 73": Madeira Is.
             "<K1ABC> HF6FIRAC": Poland. A sender "<...>" and a free text: no entity.
             "K1ABC RR73; W9XYZ <KH1/KH7Z> -12": Baker & Howland Is. and no flag.
             (f) The logbook holds K1ABC on 20m in FT8, W1XYZ on 40m in FT8 and DL1ABC
             on 20m in FT4. Without a band no record has a status. On 20m in FT8: CQ
             K1ABC is workedThisBandAndMode; W1XYZ and DL1ABC are
             workedOtherBandOrMode; N0NEW is notWorked; a free text and a hashed
             sender have none. After N0NEW is logged on 20m in FT8:
             workedThisBandAndMode. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-055-02'; }
        @TestedBy {
            test = "server/src/dxcc_tests.rs::"
                + "tc_055_002_receive_results_carry_entity_and_new_flags; "
                + "server/src/dxcc_tests.rs::"
                + "tc_055_006_non_cq_senders_carry_entity_and_flags; "
                + "server/src/dxcc_tests.rs::"
                + "tc_055_002_every_decoded_sender_call_resolves; "
                + "server/src/dxcc_tests.rs::"
                + "tc_011_003_receive_results_carry_the_worked_status";
        }
    }
}

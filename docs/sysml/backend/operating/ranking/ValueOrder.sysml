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
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelNotes::NotStated;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-039-02' {
        subject ranking : RankingService;
        doc /* Ranking MUST give each decoded standard message of a sender with a call one
             verdict under the strategy it evaluates, for the decodes of each period and
             for the records the supervisor asks for (VerdictRule, Evaluation). */
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
             For each PeriodView, while a strategy other than Default is active, the records of the
             view are evaluated under it and given as one RankedList, also when the view is
             published again for its period; ranking gives it without being asked, to Auto and to
             the supervisor.
             An EvaluateRequest is answered with the verdicts of the records it names,
             under its draft, and without one under the active strategy. Without a draft while
             Default is active it is refused (RankingRefusal::notConfigured), and for another job
             than the current one with RankingRefusal::staleRequest.
             A draft of class contest is counted over the period of the contest in
             force when that is its contest, and otherwise over every QSO of the
             logbook.
             For an EvaluateRequest ranking waits for the WorkedSet that holds the
             latest change of the logbook. For a PeriodView it takes the set it has. */
    }

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
        doc /* Directed CQs, the station's continent and the verdicts. */
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
             the two dates for fromTo.
             The key is looked up in the WorkedSet by its WorkedCategory. dxcc,
             cqZone, ituZone and continent take the key from the sender's entity
             (EntityAnswer); grid takes the first four characters of a locator in the
             message.
             The scope ever is every QSO of the set; band is the station's band in any
             mode; bandMode is that band in the operating mode.
             notWorked holds when the Standing of the key in the scope is not worked;
             notConfirmed when it is not worked or not confirmed.
             Nothing is new: for the entity keys while the sender has no entity; in
             the scopes band and bandMode while the station's band is unknown; for
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
        doc /* A new entity and a new zone against a logbook written by hand. */
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
        doc /* Each thing that can be new, in each scope and meaning. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-042-01'; verify 'CL-097-02'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_005_what_must_be_new_per_and_means_by_hand";
        }
    }

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
             bandMode. */
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
        doc /* The strategy's bands. */
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
        doc /* The grid, the region, the minimum SNR and the window of the filter. */
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
            + "tc_039_030_a_caller_beats_a_most_wanted_station_and_ignores_goal_region_and_snr; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_030_value_order_with_and_without_a_list; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_030_worked_window_from_dated_records; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_030_today_and_from_to_read_the_log_of_the_window";
        }
    }

    verification 'TC-097-006' {
        doc /* The country, US state and CQ target lists. */
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
        doc /* Callers of the profile's call pass the filter; the strategy decides the answer. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-02'; verify 'CL-097-03'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_007_callers_of_my_call_pass_the_filters";
        }
    }

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
             mostWanted: a sender whose entity is on the Most Wanted list before one
             that is not, the lower rank of the list first
             (WstxMostWanted::MostWantedListRule);
             newDxcc, newDxccBand, newDxccBandMode, newCall, newCallBand,
             newGrid, newGridBand, newCqZone, newItuZone, newContinent,
             newPrefix: a sender for which that NewWhat is new before one for which
             it is not, by NewNeeded in the scope the name ends with, ever without an
             ending, and with the strategy's newMeans and workedSince;
             snrBucket: an SNR above snrBucketUpperDb, then one from snrBucketLowerDb
             up to it, then one below, then an unknown one; equal within a group;
             snr: the stronger first, an unknown SNR last;
             distance: the farther first by StationDistance, an unknown one last;
             hearsUs: a sender whose call is in HeardByReport::heardBy before one
             that is not; equal while HeardByReport::inUse is false.
             After the criteria always the SNR, the stronger first and an unknown one
             last; then the lower audio frequency, an unknown one last; then the call
             in the order of its characters.
             A record ranked while mostWanted is a criterion and its entity is on
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
        doc /* The filter and the order together. */
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
        doc /* The criteria of the order. */
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

    requirement 'CL-055-02' {
        subject ranking : RankingService;
        doc /* Ranking MUST tell, for each decoded record whose sender it can name, the
             sender's entity, what is new about the sender against the logbook, and
             whether the sender has been worked (DecodedEntity). */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/log/dxcc.rs"; }
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
             logbook (also by another station of the shack), the country file or the
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
        doc /* The entity, the flags and the worked status of decoded records. */
        subject ranking : RankingService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-055-02'; }
        @TestedBy {
            test = "server/src/log/dxcc_tests.rs::"
                + "tc_055_002_receive_results_carry_entity_and_new_flags; "
                + "server/src/log/dxcc_tests.rs::"
                + "tc_055_006_non_cq_senders_carry_entity_and_flags; "
                + "server/src/log/dxcc_tests.rs::"
                + "tc_055_002_every_decoded_sender_call_resolves; "
                + "server/src/log/dxcc_tests.rs::"
                + "tc_011_003_receive_results_carry_the_worked_status; "
                + "server/src/log/dxcc_tests.rs::"
                + "tc_055_002_new_dxcc_band_continent_and_zone_against_the_log";
        }
    }
}

package WstxValueOrder {
    private import ScalarValues::*;
    private import ModelBindings::Automation;
    private import WstxRequirements::'FR-026';
    private import ModelNotes::FollowsSource;
    private import ModelBindings::ImplementedIn;
    private import WstxRankingControl::Needed;
    private import WstxRankingControl::NewPer;
    private import WstxRankingControl::NewWhat;
    private import ModelNotes::NotStated;
    private import WstxRankingPart::RankingService;
    private import ModelBindings::Status;
    private import WstxStrategies::Strategy;
    private import ModelBindings::TestedBy;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::ImplementationState;
    private import RequirementDerivation::*;
    private import ModelNotes::Conflict;

    attribute def Candidate {
        doc /* The filter, yes or no: every line must hold. A decoded standard message with a
             resolved sender, not mine, passing
             SaneCall, not ignored (IgnoreLists), the station band one of the strategy's
             (StrategyBands), not greyed (DirectedCqRule, except a word of the include list of
             CqTargetList), a CQ, or with treat_73_as_cq an RR73/73 addressed to someone else;
             region holds (all; dx: my continent and the sender's are known and differ;
             selected:
             the sender's continent is listed); min_snr_db null or the SNR known and >= it;
             NewNeeded true for at least one NewWhat of filters.new, with the strategy's
             new_per,
             new_means and worked_since (any chosen what counts); CountryList, UsStateFilter and
             CqTargetList hold. Each failing line names itself as why ("band not in the
             strategy",
             "region", "below min SNR", "not new", "country list", "state list", "CQ target").
             A contest strategy: ContestVerdict decides its callable records (the contest's
             rules first) and CountryList, UsStateFilter and CqTargetList apply on top; none of
             the
             other lines. The filter and the order may use the same field. */
    }
    calc def NewNeeded {
        in strategy : Strategy;
        in what : NewWhat;
        in per : NewPer;
        in needed : Needed;
        in sender : String;
        return isNew : Boolean;
        @NotStated {
            what = "how ranking obtains the country table, the log and the continent of a "
                + "call: its only connection from the log is WorkedBefore";
        }
        doc /* Whether one NewWhat is new for a
             decoded sender, per NewPer, against WorkedWindow of the strategy (worked_since):
             not_worked: no logged QSO with the same key; not_confirmed: none, or none confirmed
             (dxcc::Standing). The key: dxcc the sender's entity (WstxCountryFile::EntityOfCall, WAE
             entities by their own full name); call the call; grid the 4-character grid square in
             the decoded message, with the grid rule (no grid in the message is not new; a sender
             with a logged QSO without a grid in the window has an unknown grid status and is not
             new); cq_zone and itu_zone the zones of the sender's entity with the cty.dat entry's
             overrides; continent ContinentOfCall; prefix WpxPrefix of the call. per: ever any
             logged QSO; band one on the station band, any mode; band_mode one on the station band
             in the operating mode (ADIF MODE, an MFSK record by its SUBMODE). False without an
             entity (dxcc, cq_zone, itu_zone, continent; /MM, /AM, unknown prefix), without a
             known station band (band, band_mode) and when the log is unreadable (no claim of new).
             A logged call without an entity counts for nothing for those keys; a logged contact
             without a band counts only for ever.  */
    }
    attribute def CallerOfMyCall {
        @FollowsSource {
            reference = "WSJT-X widgets/mainwindow.cpp 1564-1568 (the CQ response None), "
                + "mainwindow_settings.cpp 313 (default None), mainwindow.cpp 7481-7496 (it "
                + "answers no "
                + "caller of my CQ automatically), Configuration.cpp 3884 (Calling CQ forces "
                + "Call 1st, off "
                + "by default)";
        }
        doc /* A decoded standard message with a resolved sender, addressed to my call, other
             than the sender's RR73/73, whose sender is not ignored (IgnoreLists). A caller of
             my call has a rank only when it passes the filters
             too: every line of Candidate except "a CQ" (and the CQ target line, which judges
             only CQs); for a contest strategy the contest's verdict (a dupe never has a rank,
             WstxContestRanking::ContestVerdictRule) and the country and US state lists. A caller
             that fails
             gets rank null with the failing line as why ("calls my call · not new", "calls my
             call · region"). Decision 4, Calling stations are answered (callers_first): on, the
             callers that pass come first (ValueOrder); off, a caller that passes has rank null
             too, why "calls my call · not answered" (CL-097-03). Off follows WSJT-X, where the
             CQ response None answers no caller of my CQ automatically and "Calling CQ forces
             Call 1st" is off by default. */
    }
    attribute def ValueOrder {
        attribute snrBucketUpperDb : Integer = 0;
        attribute snrBucketLowerDb : Integer = -10;
        doc /* The ranking. The strategy's order is a list of ValueCriterion: the first decides
             and the next breaks a tie.
             Each criterion, better first:
             most_wanted: on the Most Wanted list by its rank ascending, then the stations
             without a rank (MostWantedList).
             new_dxcc, new_dxcc_band, new_dxcc_band_mode: NewNeeded dxcc per ever, band,
             band_mode; new_call, new_call_band: NewNeeded call per ever, band; new_grid,
             new_grid_band: NewNeeded grid per ever, band (no grid, an unknown grid status or an
             unknown band is not new); new_cq_zone, new_itu_zone, new_continent, new_prefix:
             NewNeeded cq_zone, itu_zone, continent, prefix per ever; each with the strategy's
             new_means and worked_since; new before not new.
             snr_bucket: the SNR in three buckets, above snrBucketUpperDb first, from
             snrBucketLowerDb to snrBucketUpperDb (inclusive) next, below snrBucketLowerDb last,
             unknown after them; equal inside a bucket.
             snr: stronger first, unknown last.
             distance: StationDistance, farther first, unknown last.
             hears_us: the stations that hear us (PskrUse on and HearingFeed has a spot of my
             call at that station within its heardWindowSeconds on the station band and mode)
             first, then the rest;
             equal with PskrUse off or no feed.
             Then always, hidden: SNR stronger first (unknown last); then, for an
             exact tie only, the lower audio frequency, then the call in character order.
             Decode order is never a ranking.
             Order of a strategy's list: with Calling stations are answered on (callers_first,
             decision 4) the callers of my call that pass the filters (CallerOfMyCall) come
             first,
             ranked among themselves by the same criteria, then the candidates; with it off a
             caller has no rank (CallerOfMyCall) and the list holds the candidates only. Band
             Activity: the partner (on top by the browser's partner rows), then that list,
             then the rest. A contest strategy has no order (order []): it ranks by the
             contest's own rules (WstxContestRanking::ContestValueOrder), under the same rule
             for callers. */
    }
    calc def StationDistance {
        in sender : String;
        in grid : String[0..1];
        return km : Integer[0..1];
        @NotStated {
            what = "how ranking obtains the country table, the log and the continent of a "
                + "call: its only connection from the log is WorkedBefore";
        }
        doc /* The distance for the value criterion distance: the great-circle distance from
             the centre of the profile locator to the centre of the 4-character grid in the
             message; otherwise to the sender's entity centre from cty.dat (the approximate
             entity distance of WstxLogControl::DecodedEntity). Unknown without a profile locator
             or without grid and entity (/MM, /AM, unknown prefix). Whole km, truncated. */
    }
    calc def WpxPrefix {
        in call : String;
        return prefix : String;
        @FollowsSource { reference = "CQ WPX Contest rules"; }
        doc /* The CQ WPX prefix of a call: the letters and
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
        @NotStated {
            what = "how ranking obtains the country table, the log and the continent of a "
                + "call: its only connection from the log is WorkedBefore";
        }
        doc /* The continent of WstxCountryFile::EntityOfCall for the call (with a {cont}
             override of the matching cty.dat entry applied); none when the call has no
             entity (/MM, /AM, unknown prefix). The message grid does not decide a station's
             continent.
             The snapshot's derived_continent is ContinentOfCall of my callsign. */
    }
    calc def MyContinent {
        in configured : String[0..1];
        in callsign : String[0..1];
        in locator : String[0..1];
        return continent : String[0..1];
        @NotStated {
            what = "how ranking obtains the country table, the log and the continent of a "
                + "call: its only connection from the log is WorkedBefore";
        }
        doc /* The configured continent (StrategyConfiguration continent) when set; else
             ContinentOfCall of the profile callsign; else, when the call has no entity
             (/MM, /AM, unknown prefix), the continent of the cty.dat entity whose centre
             is nearest to the centre of the profile locator; else none. */
    }
    calc def UsStateOf {
        in sender : String;
        return stateCode : String[0..1];
        @NotStated {
            what = "how ranking obtains the country table, the log and the continent of a "
                + "call: its only connection from the log is WorkedBefore";
        }
        doc /* The state of a sender of the entities 291, 6 or 110
             (WstxCountryFile::EntityOfCall), the first source that knows it: (1) the decoded
             message, when its exchange carries a
             US state (the RTTY Roundup family; an ARRL or RAC section is not mapped to a
             state); (2) the log: the ADIF STATE of the newest record of that call that has
             one, a confirmed record (dxcc::Standing) before an unconfirmed one. The licence
             data and the grid are not used.
             None: unknown. */
    }
    calc def SaneCall {
        in call : String;
        return sane : Boolean;
        doc /* At least 3 characters with a digit and a letter, not ending /R (rover). */
    }
    enum def ActivityWord {
        doc /* The word of a contest activity in a CQ (WstxSpecialActivities::SpecialActivity): TEST
             for na_vhf, eu_vhf and arrl_digi, WW for ww_digi, FD for field_day, RU for rtty. */
        enum TEST; enum WW; enum FD; enum RU;
    }
    calc def DirectedCqRule {
        in target : String[0..1];
        in activityWord : ActivityWord[0..1];
        in myContinent : String[0..1];
        in senderContinent : String[0..1];
        return answerable : Boolean;
        doc /* The one directive rule of strategies and the operator, applied before any
             strategy and one function in the station. A CQ
             is answerable when its directive does not exclude me: a plain CQ (no target);
             "CQ x" with x my continent; "CQ DX" when both continents are known and differ.
             Contest activity (WstxContestRanking::ContestDirective): the word of the station's
             special activity (ActivityWord) is answerable too, whatever the continents.
             Every other directive is not answerable: another continent or region (NA, JA,
             SA, ...), any other word (TEST, POTA, a number; a contest word outside its
             activity), CQ DX from my own or an unknown
             continent, and with my continent unknown every directive. A record that is no
             CQ has no directive and is answerable. Its text is "CQ x — not for <my continent>"
             ("not for this station" when unknown).
             My continent: MyContinent.
             A strategy skips a CQ that is not answerable: it is greyed in Band Activity and is
             never a Candidate. */
    }

    attribute def StrategyBandsRule {
        doc /* A strategy with bands null works on every band; with a list it works only while
             the station band (CAT dial band, else the operating selection band) is one of them,
             and an unknown station band is none of them. It never switches bands. Off its
             bands: every verdict has rank null with why "band not in the strategy" ("band
             unknown" when unknown), so nothing is marked, alerted or called. A contest strategy
             works only on the bands both of its list and of the contest (ContestVerdict "band
             not in the contest"). */
    }

    attribute def CountryListRule {
        @Conflict {
            what = "WstxSettings::StrategyEditor says a prefix or country entry is typed as "
                + "free text "
                + "with no picker; this text says the editor has a country picker.";
        }
        @NotStated {
            what = "how ranking obtains the country table: its only connection from the log "
                + "is WorkedBefore";
        }
        doc /* An entry of kind "prefix" matches when the decoded call begins with it; an entry
             of kind "country" with a full entity name of the country table
             (WstxCountryFile::EntityOfCall, a WAE entity by its own name), matching the
             sender's entity, compared ignoring case; a name the current table does not hold is
             refused at the PUT (an entry read from the file whose name a replaced cty.dat no
             longer holds matches nothing); an entry with bands counts only while the station
             band is one of them. The line holds when no exclude entry matches and, with a
             non-empty include list, at least one include entry matches; a sender without an
             entity matches no country entry. Editor: one line per entry, with a country picker
             that lists the table's names. */
    }

    attribute def UsStateFilterRule {
        doc /* The sender's state (UsStateOf): with a non-empty include list the line holds only
             when the state is known and listed (an unknown state, also every station outside
             those entities, fails it); with an exclude list it fails only when the state is
             known and listed. */
    }

    attribute def CqTargetListRule {
        doc /* The directive of a CQ is the word after CQ ("CQ POTA K1ABC FN42" has POTA, "CQ DX
             ..." DX; a plain CQ and an RR73/73 counted as calling have none). Exclude: a CQ
             whose directive is listed fails. Include (non-empty): only a CQ whose directive is
             listed passes; a plain CQ and an RR73/73 counted as calling fail. A caller of my
             call is no CQ and is not judged by this line. A word on the include list that
             DirectedCqRule does not answer (POTA, SOTA, a number) is answerable for this
             strategy. Verdict: such a CQ is not grey for that strategy (grey false, ranked by
             its filters and order), so Band Activity marks it and does not strike it through,
             and Alert records it like any candidate. A continent directive and DX keep
             DirectedCqRule. */
    }

    attribute def VerdictRule {
        doc /* One per decoded standard record with a resolved sender (others have none): an
             ignored sender (IgnoreLists) has rank null, grey false; else grey per
             DirectedCqRule (not grey when its directive word is on the strategy's CQ target
             include list, CqTargetList); a Candidate, and a caller (CallerOfMyCall) while
             Calling stations are answered is on, have rank = the position (0-based) in
             ValueOrder among the evaluated records; with it off a caller has rank null, why
             "calls my call · not answered" (CL-097-03); every other record rank null. why
             (explain only): "calls my call", "new: dxcc, grid" (the new whats, with " on
             <band>" or " on <band> <MODE>" per new_per), with " · Most Wanted #n" when ranked
             by the list, "not new", "not a CQ", "region", "below min SNR", "band not in the
             strategy", "band unknown", "country list", "state list", "CQ target", "calls my
             call · <failing line>" (CallerOfMyCall), "my own message", "callsign guard", the
             DirectedCqRule text "CQ x — not for c" or "<call> is ignored (session list)" /
             "(permanent list)". Display order: rank ascending; records without a rank follow in
             sequence order. */
    }

    attribute def WorkedWindowRule {
        doc /* window all: the log's cached worked set (rebuilt after a log or country table
             change). today (the current UTC date) and from_to: a worked set built only from the
             records whose QSO_DATE lies in the window, inclusive. A record without a date
             counts only for all. The station step uses the last built set of the window at
             once. A selection and POST /strategy/evaluate wait for the current set. With no set
             yet nothing is needed in that step (no claim of needed). */
    }


    calc newNeeded : NewNeeded;
    calc wpxPrefix : WpxPrefix;
    calc stationDistance : StationDistance;
    calc usStateOf : UsStateOf;
    calc directedCqRule : DirectedCqRule;
    calc myContinent : MyContinent;
    attribute candidate : Candidate;
    attribute callerOfMyCall : CallerOfMyCall;
    attribute valueOrder : ValueOrder;
    attribute strategyBandsRule : StrategyBandsRule;
    attribute countryListRule : CountryListRule;
    attribute usStateFilterRule : UsStateFilterRule;
    attribute cqTargetListRule : CqTargetListRule;
    attribute verdictRule : VerdictRule;
    attribute workedWindowRule : WorkedWindowRule;

    satisfy 'CL-039-02' by newNeeded;
    satisfy 'CL-039-02' by wpxPrefix;
    satisfy 'CL-039-02' by workedWindowRule;
    satisfy 'CL-039-02' by callerOfMyCall;
    satisfy 'CL-039-02' by candidate;
    satisfy 'CL-039-02' by valueOrder;
    satisfy 'CL-039-02' by stationDistance;
    satisfy 'CL-039-02' by verdictRule;
    satisfy 'CL-039-03' by directedCqRule;
    satisfy 'CL-039-03' by myContinent;
    satisfy 'CL-042-01' by newNeeded;
    satisfy 'CL-097-02' by strategyBandsRule;
    satisfy 'CL-097-02' by candidate;
    satisfy 'CL-097-02' by newNeeded;
    satisfy 'CL-097-02' by callerOfMyCall;
    satisfy 'CL-097-02' by countryListRule;
    satisfy 'CL-097-02' by usStateFilterRule;
    satisfy 'CL-097-02' by usStateOf;
    satisfy 'CL-097-02' by cqTargetListRule;
    satisfy 'CL-097-02' by verdictRule;
    satisfy 'CL-097-03' by valueOrder;
    satisfy 'CL-097-03' by callerOfMyCall;
    satisfy 'CL-097-03' by verdictRule;

    requirement 'CL-039-02' {
        subject ranking : RankingService;
        doc /* One station evaluator gives each decoded standard message a verdict: its filters
             are CL-097-02 and its order CL-097-03, callers of my call included. SNR is always
             the hidden last tie-breaker, then for an exact tie the lower audio frequency and
             the call; decode order is never a ranking. Distance is from the profile locator to
             the message grid, else to the cty.dat entity centre. POST /strategy/evaluate
             returns the verdicts of retained live records for the saved strategy or a draft,
             with the reason when asked; the browser never evaluates a strategy itself. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/strategy.rs; server/src/logbook.rs; server/src/recording.rs; server/src/dxcc.rs";
        }
    }
    requirement 'CL-039-03' {
        subject ranking : RankingService;
        doc /* One directive rule before every strategy and for the operator: a CQ is answerable
             when it is a plain CQ, CQ <my continent> (derived from the profile call via
             cty.dat, locator fallback) or CQ DX from another continent. Every other directive
             is not answerable: a strategy skips it (greyed, never matches). In a contest
             activity its own word (CQ TEST, WW, FD, RU) is answerable too (CL-063-02). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/strategy.rs; server/src/automation.rs; server/src/contact_http.rs; server/src/dxcc.rs; client/contact.js";
        }
    }
    requirement 'CL-042-01' {
        subject ranking : RankingService;
        doc /* What must be new reads the sender's cty.dat entity against the internal log: new
             [dxcc] per ever, band and band_mode, and new [cq_zone] per ever (NewNeeded); a
             sender without an entity, an unknown station band (for band and band_mode) or an
             unreadable log never counts as new. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/strategy.rs; server/src/dxcc.rs; server/src/logbook.rs; client/contact.js";
        }
    }
    requirement 'CL-097-02' {
        subject ranking : RankingService;
        doc /* Band: off the strategy's bands (all by default) every verdict has rank null, why
             "band not in the strategy" or "band unknown"; it never switches bands. Filters,
             every line must hold: what must be new (DXCC entity, call, grid, CQ zone, ITU zone,
             continent, prefix; any chosen one counts) per ever, band or band and mode, new
             meaning not worked or not confirmed (QSL/LoTW); region; minimum SNR; worked since
             (any time, today, from-to); Treat 73 as CQ; prefix/country include and exclude
             lists (an entry optionally per band; country names from the country table); US
             state include and exclude (the state from the message exchange where it carries
             one, else the log's STATE, a confirmed record first; unknown fails an include list;
             the licence data and the grid are not used); CQ target include and exclude (POTA,
             SOTA, EU, DX ...; a word on the include list makes that CQ's verdict not grey for
             this strategy, and Alert records it). Callers of my call must pass the filters too.
             A contest strategy applies its contest's verdict first, then the country, US state
             and CQ target lists. Each failing line is named in the verdict's reason. */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn {
            module = "server/src/strategy.rs; server/src/dxcc.rs; server/src/automation.rs";
        }
    }
    requirement 'CL-097-03' {
        subject ranking : RankingService;
        doc /* Order: criteria, the first decides and the next breaks a tie: Most wanted (Club
             Log rank); New DXCC, on band, on band and mode; New call, on band; New grid, on
             band; New CQ zone; New ITU zone; New continent; New prefix; SNR bucket (above 0 dB,
             -10..0 dB, below -10 dB); SNR (stronger first); Distance (farthest first); Hears us
             first (a PSK Reporter spot of my call at that station at most 600 s old). Then
             always SNR, then for an exact tie the lower audio frequency and the call; decode
             order is never a ranking. With "Calling stations are answered" on, the callers that
             pass the filters come first, ranked among themselves; with it off a caller of my
             call has rank null, why "calls my call · not answered". A contest strategy has no
             order: it ranks by ContestValueOrder, under the same rule for callers. */
        @FollowsSource {
            reference = "WstxRequirements::BehaviorBaseline (WSJT-X): the CQ response None "
                + "answers no caller automatically and 'Calling CQ forces Call 1st' is off by "
                + "default";
        }
        @Status { build = ImplementationState::partial; }
        @ImplementedIn {
            module = "server/src/strategy.rs; server/src/contest.rs";
        }
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-039-02';
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-039-03';
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-042-01';
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-097-02';
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-097-03';
    }

    verification 'TC-097-004' {
        doc /* TC-097-004 — The strategy's bands
             CL-097-02
             Setup: the evaluator with the pinned cty.dat fixture and hand-authored codec-packed
             rows; a strategy with bands ["20m", "40m"]. The run's steps off the bands are
             TC-097-018's.
             (a) Station band 20m: the candidates are ranked.
             (b) Station band 15m: every verdict has rank null with why "band not in the
             strategy".
             (c) Station band unknown: every verdict has rank null with why "band unknown".
             (d) The same strategy with bands null on 15m: the candidates are ranked.
             2 — Isolated automated tests; Windows development PC. */
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-097-02';
        }
        @TestedBy {
            test = "server/src/strategy97_tests.rs";
        }
    }
    verification 'TC-097-005' {
        doc /* TC-097-005 — What must be new, new per, new means and worked since
             CL-097-02
             Setup: the evaluator with the pinned cty.dat fixture and a hand log (worked and
             confirmed QSOs per band, mode and date, with and without grid) for HB9BLA JN37VL on
             20m FT8; the expected verdicts hand-worked in the test from the log and the cty.dat
             entries.
             (a) Each NewWhat alone with each new_per and each new_means: a station is new
             exactly where the log lacks its key per the chosen per and means; an entity whose
             cty.dat entry overrides the ITU zone is judged by the override; prefix by the
             WpxPrefix table cases.
             (b) Grid: no grid in the message is not new; a logged QSO without grid gives an
             unknown grid status, not new.
             (c) Two whats: either counts.
             (d) worked_since today and from_to with an undated record: an undated record counts
             only for any time.
             (e) region dx and selected, and min_snr_db: a station outside the region or below
             the minimum is no candidate.
             (f) treat_73_as_cq on and off: an RR73 to another station counts as calling only
             with it on.
             (g) The station band unknown with new_per band: nothing is new per band or
             band_mode.
             2 — Isolated automated tests; Windows development PC. */
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-097-02';
        }
        @TestedBy {
            test = "server/src/strategy97_tests.rs";
        }
    }
    verification 'TC-097-007' {
        doc /* TC-097-007 — Callers of my call pass the filters and are answered only when
             Calling stations are answered is on
             CL-097-02, CL-097-03
             Setup: the evaluator with the pinned cty.dat fixture, HB9BLA on 20m; the built-in
             Casual (call, per band, not worked; Calling stations are answered on); a log with
             W1AW worked on 20m; rows HB9BLA W1AW FN31 (+5), HB9BLA N1NEW FN31 (-9), CQ K1ABC
             FN42 (-1). The run's steps with callers are TC-097-018's. Oracle: the operator's
             decision on callers; WSJT-X with the CQ response None answers no caller
             automatically (widgets/mainwindow.cpp 7481-7496).
             (a) Casual: W1AW rank null, why "calls my call · not new"; N1NEW ranked first, then
             K1ABC.
             (b) Calling stations are answered off with order [snr]: N1NEW rank null, why "calls
             my call · not answered"; K1ABC alone is ranked.
             (c) A caller failing region dx, min SNR -5, a country exclude or a state include:
             rank null, why "calls my call · region", "· below min SNR", "· country list" or "·
             state list".
             2 — Isolated automated tests; Windows development PC. */
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-097-02';
            verify 'CL-097-03';
        }
        @TestedBy {
            test = "server/src/strategy97_tests.rs";
        }
    }
    verification 'TC-097-008' {
        doc /* TC-097-008 — The order criteria
             CL-097-03
             Setup: the evaluator with the TC-039-040 rows extended by stations at SNR +1, 0,
             -10, -11 and unknown; a feed without a connection fed hand-authored spots of my
             call at JA1XYZ and VK2ABC; the expected orders hand-worked in the test (distances
             by the haversine formula written there).
             (a) order [snr_bucket]: +1 first; 0 and -10 in the middle bucket; -11 last; unknown
             after them; inside a bucket SNR, frequency, then call.
             (b) order [snr_bucket, distance]: inside a bucket the farthest first.
             (c) order [hears_us]: with PskrUse on JA1XYZ and VK2ABC first, with PskrUse off the
             plain SNR order.
             (d) order [new_cq_zone], [new_itu_zone], [new_continent], [new_prefix] and
             [new_dxcc_band_mode], each before [snr]: the new stations first, SNR order inside.
             (e) order [most_wanted, snr]: the listed stations first by rank, then by SNR.
             (f) A contest strategy is ranked by ContestValueOrder: with the WW Digi built-in,
             CQ WW JA1XYZ PM95, the non-dupe caller HB9BLA VK2ABC QF56 and the dupe caller
             HB9BLA K1OLD FN20, Calling stations are answered on: VK2ABC rank 0, JA1XYZ rank 1;
             off: VK2ABC rank null with why "calls my call · not answered", JA1XYZ rank 0; K1OLD
             rank null either way.
             (g) Decode order never changes an order.
             2 — Isolated automated tests; Windows development PC. */
        @Automation { run = AutomationState::partial; }
        objective {
            verify 'CL-097-03';
        }
        @TestedBy {
            test = "server/src/strategy97_tests.rs; server/src/contest_tests.rs";
        }
    }
    verification 'TC-039-040' {
        doc /* TC-039-040 — The filter and the value order
             CL-039-02
             Setup: the evaluator as a function with the pinned cty.dat fixture, a hand log and
             hand-authored codec-packed rows for HB9BLA JN47AA (EU) on 20 m FT8: CQ K1ABC FN42
             -12 at 1200 Hz, CQ JA1XYZ PM95 -15 at 900 Hz, CQ DL1XYZ JO62 -3 at 1500 Hz, CQ
             VK2ABC QF56 -20 at 600 Hz, CQ ZS6AA -8 at 2000 Hz (no grid), CQ OH1AA KP20 -3 at
             1400 Hz, HB9BLA W1AW FN31 -25 (a caller); the log has K1ABC and W1AW on 20 m,
             DL1XYZ on 40 m only, OH1AA on 20 m today; a Most Wanted list with JA (rank 40) and
             VK (rank 90). Distances are computed in the test by the haversine formula written
             there.
             (a) new [call] per band, order [snr]: DL1XYZ, OH1AA (1400 Hz before 1500 Hz when
             tied), ZS6AA, JA1XYZ, VK2ABC; K1ABC and W1AW are no candidates (worked on 20 m).
             (b) order [distance]: VK2ABC, JA1XYZ, ZS6AA (entity centre), OH1AA, DL1XYZ.
             (c) order [most_wanted]: JA1XYZ, VK2ABC, then the rest by SNR; [most_wanted,
             distance]: the same for the listed, then by distance.
             (d) new [call, grid, dxcc], Calling stations are answered off, each needed-first
             criterion alone before [snr]: the needed stations before the others, SNR order
             inside each group, W1AW without a rank: [new_dxcc] DL1XYZ after the rest;
             [new_dxcc_band] DL1XYZ needed on 20 m; [new_dxcc_band_mode] JA1XYZ needed (FT4 is
             another mode); [new_call] K1ABC after; [new_call_band] K1ABC and OH1AA after;
             [new_grid] K1ABC (FN42) after; [new_grid_band] K1ABC needed, the row without grid
             and the call with an unknown grid status not needed.
             (e) The station band unknown: no candidate for new [call] per band, nothing needed
             by new_grid_band.
             (f) Worked since today: OH1AA not needed by new [call] per band; W1AW (not in that
             log) a caller that passes, first with Calling stations are answered on.
             (g) Two verdicts of the same SNR and frequency are ordered by call; Calling
             stations are answered off: W1AW has no rank; an empty order list gives SNR order;
             W1AW ranks only where it passes the filters (TC-097-007).
             (h) The reasons name the needed whats; the decode sequence never changes an order.
             2 — Isolated automated tests; Windows development PC. */
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-039-02';
        }
        @TestedBy {
            test = "server/src/strategy_tests.rs";
        }
    }
}

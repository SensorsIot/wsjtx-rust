package WstxContest {
    private import ScalarValues::*;
    doc /* Canonical contract of the contest strategies (issue #63, CL-063-01..06 in
         WstxRequirements; verification TC-063-001..012; contest data issue #98, CL-098-01..06,
         TC-098-001..014): the second strategy class beside WstxStrategy's award strategies.
         Nothing here is an execution result.

         Decisions (operator on #63 and #39, 2026-11-04 and 2026-11-06, and on #98, 2026-11-09,
         newest wins):
         D1 One profile per contest from the official rules; S&P and Run; contest strategies do
            call CQ. Two levels: fully automatic and colouring only; colouring only is the
            default and is always available in contest mode. A contest can be operated by hand.
            (#98 D11: the profiles are records of the contest file, no longer compiled.)
         D2 Choosing an activity never sets a strategy.
         D3 Automation clause: warn and confirm where the rules forbid it, a short note where they
            are silent or permit it (never a block).
         D4 RTTY Roundup is dropped (FT8 and FT4 no longer qualify). Usable everywhere in the
            world: a limit that depends on the location or the entry is a note (DX may only work
            W/VE; check-log only). National contests come later as data. (#98: national
            contests are data now; a record's workable rule is acted on, D15 and open Q3 on #98;
            its eligible rule stays a note, EntryRule.)
         D5 January VHF is not computed, the period prompt asks; IARU MGM uses standard FT8
            messages with report and 4-character locator; a full weekend has Saturday and
            Sunday both in the month; an unconfirmed Cabrillo name stays marked. (#98: an
            operating-time limit a record states as a window is computed, ScoredWindow; any
            other stays a note.)
         D6 Contest strategies are not saved strategies: the profiles are data, and the choice with
            its period is the selection (ContestSelection), never written to the file. The award
            strategy class on the wire stays award (WstxStrategy::StrategyClass): a saved strategy
            of class contest stays refused.
         D7 The activity stays the operator's (D2 both ways): selecting a contest does not set
            it; the prompt says when it differs. Implementer's default on #63.
         D8 Band Activity lists only what can be called, by value, with a Show all toggle (off),
            and colours only what is interesting: the callable stations and most the new
            multipliers; a dupe or a directed CQ shown by Show all is dimmed, uncoloured.
         D9 Fully automatic stays with the station: the safety of WstxStrategy::StrategyRun
            applies unchanged (HALT, Esc, Tx watchdog, 60 s without a client, 8 hours). Implementer's
            defaults on #63: HALT leaves the contest in force as colouring only; S&P and Run are
            the two automatic operations, chosen at the prompt, not both at once (no band or
            frequency hopping); the Tx watchdog stops a Run on an unanswered CQ like any message.
         D10 Strategydef (#39, operator grill 2026-11-07, WstxStrategy D15): colouring only is
            Auto off (WstxStrategy::AutoToggle, one toggle for strategies and contests); the
            contest keeps its own value (ContestValueOrder); x and the quiet time are set per
            contest, defaults 2 and 10 minutes, more aggressive than strategies; in situation 1
            the run stays while the target hears us and is still the most valuable
            (WstxStrategy::LeaveRule). HALT turns Auto off and leaves the contest selected.
         D11 Contest data (#98, operator 2026-11-09): every contest is one record of one
            validated data file (ContestFile), bundled and replaceable by an upload like cty.dat
            (#55); a new contest is one more record, and new code is needed only for a new
            expression variable, multiplier kind, dupe dimension or message family. All 35
            FT8/FT4 contests of the research on #98 (its first comment, rules read 2026-11-09)
            are bundled (ProfileTable). The closed rule lists of #63 (DupeRule, PointsRule,
            MultiplierRule as enums) become data.
         D12 Contest state from the log of the period (ContestLog): each record's own fields
            (MY_GRIDSQUARE, the exchange fields, STX) instead of the station's present grid;
            the serial number sent comes from the log (ContestSerial), not the boot counter.
            No separate contest store.
         D13 The value of a station is the projected score gain (ContestValue); callers of my
            call first (ContestValueOrder). It replaces "a new multiplier, then points".
         D14 A per-contest CQ word (ExchangeRule cq; ContestDirective, ContestRun).
         D15 The operator's filters (WstxStrategy, #97) apply on top of the contest's rules
            and never widen them (ContestVerdict); a started QSO is always finished (#81).
         D16 Reference data: named entity sets, call areas and call lists in the contest file
            (ReferenceSets); one table of US states, VE provinces and ARRL/RAC sections
            bundled with the station (Subdivisions), also read by #97's state filter. CQ and
            ITU zones and the WPX prefix stay those of cty.dat and WstxStrategy::WpxPrefix.
            The definer's listed defaults and the open questions are on #98. */

    // ---------------------------------------------------------------- the contest file (#98)
    attribute def ContestFile {
        attribute bytesMax : Integer = 1048576;
        doc /* #98 (CL-098-01). All contests are one JSON file (UTF-8, at most bytesMax bytes):
             {format 1, contests [ContestProfile ...], sets, call_areas, call_lists}; sets,
             call_areas and call_lists may be absent (empty), every other key is required and
             no other key is accepted, at every level of the file. The bundled file is
             embedded in the station; its records are ProfileTable
             and it passes the same validation (its test fails otherwise). An uploaded file
             replaces it per station profile as contests.json beside contacts.adi (written to
             a temporary file, flushed, renamed under the publication gate, as
             WstxContact::CountryFile); a stored upload that cannot be read or does not
             validate leaves the bundled file in use, is reported (upload_unreadable) and is
             never overwritten. Nothing is downloaded automatically.
             Validation, complete before anything changes: valid JSON of that shape; exactly
             the keys of ContestProfile and its parts, an optional key taking its stated
             default; at least one contest; each id matching ^[a-z0-9_]{1,32}$ and unique;
             name 1..40 printable ASCII; source an http or https URL; checked a real date
             YYYY-MM-DD; bands ADIF band names (the station's band table); modes ADIF mode
             names the log accepts or one class (ModeRule); each expression parses
             (ContestExpression) and uses only the variables, functions, sets, call areas,
             call lists and entry parameters its context allows, numbers where numbers are
             needed and conditions where conditions are; every set member is the primary
             prefix of an entity of the cty.dat in use (WstxContact::CountryFile); a cq word
             is 1..4 letters A-Z or three digits (the standard CQ modifier that packs); every
             round's end lies after its start; a time zone is UTC or a known IANA zone. The
             first fault is refused with its JSON path (contests[3].points) and a reason;
             nothing changes. A set member that a later cty.dat no longer has matches no call
             (no refusal after the fact). */
    }
    attribute def ContestFileHttp {
        doc /* #98 (CL-098-01). GET /strategy/contests (ContestHttp) carries file {source
             "bundled"|"uploaded", contests (the number of records), upload_unreadable}.
             PUT /strategy/contests {v, profile_id, boot_id, text} with exactly these keys,
             body at most 2 MiB: text null removes the upload (bundled again); a string of at
             most ContestFile::bytesMax bytes replaces the file when it validates, else 400
             {error:{code invalid_contests, field text, path, reason}}; any other text 400
             invalid_request text. While a contest is selected (ContestSelection) the PUT is
             refused 409 state_conflict field contest and changes nothing, so a clause the
             operator confirmed never runs under rules replaced after it. Profile, boot,
             Origin and authorization checks as PUT /dxcc (WstxContact::CountryFileHttp); an
             MCP principal is refused as on PUT /strategy. 200 is the new GET view.
             Settings > General shows "Contest rules: bundled|uploaded, N contests" with
             Upload and Use bundled beside the cty.dat control; a refusal shows its path and
             reason and changes nothing. */
    }
    attribute def ContestProfile {
        doc /* One record of ContestFile: rule facts of one contest, no behaviour of its own.
             Keys (#98; optional keys with their default):
             id; name; organiser; source (the official rules page or file); checked (the date
             the rules were last read); log {format cabrillo|edi|adif|email|none, contest
             (the Cabrillo or log name, or null), confirmed (default false: an unconfirmed
             name stays marked)}; schedule (ScheduleRule); bands (ADIF band names); modes
             (ModeRule; default FT8 and FT4 counted as one mode); exchange (ExchangeRule);
             dupe (DupeRule); points (PointsRule); points_cap (optional, PointsRule);
             multipliers (MultiplierRule; default none); score (ScoreRule); extras (score
             parts the station does not compute, words; default none); automation
             (AutomationClause with text; default silent); restrictions (default none);
             entry (EntryRule; default none); members (optional: the name of a call list of
             ReferenceSets that holds the club members); notes (words); unconfirmed (what
             the rules do not state, as field paths with words; default none).
             restrictions, each shown as a note and none enforced by the station, which sends
             one signal, never spots and never changes band by itself: single_signal,
             no_multistream, no_alternating_cq, standard_messages_only (encoded as the
             activity none), self_spot_forbidden, self_spot_limited, self_spot_allowed,
             min_band_stay (minutes). */
    }
    attribute def ScheduleRule {
        doc /* schedule {tz (default UTC; else an IANA zone: the day rules and times are that
             zone's local calendar and clock, so a period follows its daylight saving),
             rounds [Round ...], text (the schedule in words for the prompt), series
             (optional, SeriesRule), window (optional, ScoredWindow)}.
             Round {day (a day rule), time [start, end] ("Nd HH:MM", N a whole number of
             days, also negative, from the anchor day; end exclusive and after start), bands
             (optional: the round's own bands, else the record's), label (optional)}.
             Day rules, the anchor day of a round in a month: {full_weekend 1..5 or "last",
             month 1..12}: the n-th or last Saturday whose Sunday is in the same month;
             {weekday MON..SUN, n 1..5, "last" or "every", months "all" or a list of 1..12}:
             that weekday of each listed month (every: each of them); {date "MM-DD"} each
             year; {dates ["YYYY-MM-DD" ...]}: only those days; {asked true}: not computable,
             the prompt asks. #63's forms map to these: FullWeekend, LastFullWeekend,
             Saturday {month, n} = weekday SAT n months [month], EveryMonth = months all.
             A seasonal time is two rounds with disjoint month lists.
             The current or next occurrence is the earliest occurrence of any round that has
             not ended at that instant; none when every round is asked or every listed date
             has passed (the prompt then asks, as for asked). The period of a selection is
             one occurrence; a round's bands narrow the record's bands for it. */
    }
    attribute def ScoredWindow {
        doc /* window {limit (a number, or the name of an entry parameter that holds it),
             unit "hour" (default) or "utc_day", scored "first" or "best", min_off_minutes
             (default 0)}: which QSOs of the period score (ContestLog).
             first: the operating time is accumulated over the QSOs in time order; a gap
             between two consecutive QSOs of at least min_off_minutes is off time, every
             other gap is operating time; a QSO scores while the operating time up to it is
             at most limit hours (ARRL Digi: 24 hours, off at least 60 minutes).
             best: the limit units (whole UTC hours or UTC days) with the most points score,
             the rest do not; a tie goes to the earlier unit. best is valid only with a score
             that is a sum over QSOs (ScoreRule additive), else the file is refused.
             A QSO that does not score is still logged and still a dupe for later QSOs. */
    }
    attribute def SeriesRule {
        doc /* series {best n, of m, per "band" or "contest", normalise "none", "winner_1000"
             or "rank", annual "sum" or "sum_times_rounds" (optional)}: how the organiser
             aggregates rounds over a season. Shown by the prompt in words; not computed (the
             tally and the value are those of the selected period, and normalised scores
             need the other entrants' logs). */
    }
    attribute def ModeRule {
        doc /* modes {count, as_one (optional)}. count: a list of ADIF modes, or digital
             (every mode but phone and CW), digital_no_rtty, or any. Phone is SSB, USB, LSB,
             AM, FM, DIGITALVOICE; CW is CW; every other mode is digital (the mode class).
             as_one: lists of modes that are one mode for the dupe dimension mode_group, or
             "all" (one mode regardless). A QSO whose mode is not counted is not read. */
    }
    attribute def ExchangeRule {
        doc /* exchange {activity, cq (optional), sent [Field], rcvd [Field], unsendable_for
             (optional condition on my station)}.
             activity: the WstxContact::SpecialActivity the station operates the contest in:
             none (standard messages: report, grid in the CQ and Tx1), na_vhf, ww_digi or
             arrl_digi (grid exchange), field_day, rtty (RTTY Roundup message: report and
             serial, state or province), or eu_vhf (report, serial and 6-character locator;
             accepted in the file before the station can send it, #99; until then the
             station is never in it and ContestRun waits activity).
             cq: the contest's CQ word; default the activity's word (TEST, WW, FD, RU, none
             for none). Field: grid4, grid6, report, rst, serial, fd_class, section,
             state_province, canton, province, member_flag, county; they name what travels
             and where ContestLog reads it (serial SRX, section ARRL_SECT, fd_class CLASS,
             state_province STATE, grid4 and grid6 GRIDSQUARE, report and rst RST_RCVD,
             canton, province, county and member_flag SRX_STRING).
             unsendable_for: when it holds for my station, the station cannot send the
             exchange my side owes (Helvetia as an HB station: the canton, #100; PACCdigi as a
             PA station: the province); the prompt says so and ContestRun waits exchange. */
    }
    attribute def DupeRule {
        doc /* dupe {per [Dim ...], keep "first" (default) or "best"}: a QSO is a dupe of an
             earlier QSO with the same call (case-insensitive) and the same value of every
             listed dimension; per [] is once per call in the period. Dim: band; mode;
             mode_group (ModeRule as_one); mode_class (phone, CW, digital); round (the
             schedule round the QSO lies in); utc_day; their_grid4; my_grid4. A grid
             dimension without a grid: a logged QSO without the grid dupes every grid of that
             call in the other dimensions; a decoded message without a grid is a dupe when
             the call is logged in the other dimensions (as #63 band_grid). keep best: of the
             QSOs that dupe each other, the one with the most points counts and the others
             are dupes (ARRL 222: the longest per pair of grids).
             #63's four rules are band = per [band]; band_mode_class = per [band, mode_class];
             band_grid = per [band, their_grid4]; call = per []. */
    }
    attribute def ContestExpression {
        doc /* The small expression language of points, score, multiplier only, points_cap
             when and entry conditions (#98). Grammar: a number (decimal, e.g. 3000 or
             6378.16); a variable or function of the context; parentheses; + - * / with the
             usual precedence (x/0 is 0); floor, ceil, max, min; "if c then a else b"; a table
             band{6m: 1, 2m: 2, else: 4} on the QSO's band or class{phone: 1, cw: 2,
             digital: 2} on its mode class, a missing key taking else (a table without else
             refuses a missing key at validation only where the record's bands or modes can
             reach it); conditions: and, or, not, = != < <= > >= on numbers, param(name) =
             "value" on a text parameter, and the truth-valued variables. Names are case
             sensitive. A number is exact while it is whole and a 64-bit float otherwise; a
             score or points on the wire is rounded half up to a whole number. */
    }
    attribute def PointsRule {
        doc /* points: a ContestExpression giving one QSO's points from its variables:
             km(grid4 or grid6, earth): great-circle distance between the centres of my and
             their locator cut to 4 or 6 characters; earth 6371 (default), 6378.16 or iaru
             (111.2 km per degree); no value without both locators (then the points are 0);
             same_grid4, same_grid6, grid_known (their grid known); same_dxcc,
             same_continent; their_in(SET), my_in(SET) (the entity's primary prefix in a set
             of ReferenceSets); their_cont(XX), my_cont(XX) (continent code); their_member
             (their call in the record's members list), my_member (entry parameter member);
             param(name) (an entry parameter); band{...}, class{...}. My locator is the QSO's
             MY_GRIDSQUARE, else the station locator; their locator its GRIDSQUARE.
             points_cap {when (a condition), share (a fraction n/d)}: in time order a QSO for
             which when holds scores 0 while the QSOs for which when holds would exceed share
             of all counted QSOs so far (Africa FT4: same entity at most a third).
             #63's seven rules are these expressions: one_plus_per_3000_km 1 +
             floor(km(grid4)/3000); one_plus_per_500_km_up 1 + max(1, ceil(km(grid4)/500));
             field_day class{phone: 1, cw: 2, digital: 2}; vhf_january band{6m: 1, 2m: 1,
             1.25m: 2, 70cm: 2, 33cm: 4, 23cm: 4, else: 8}; vhf_june_september the same with
             33cm and 23cm 3 and else 4; kilometres if same_grid4 then 50 else floor(km(grid4,
             iaru)) + 1; one_per_call 1. */
    }
    attribute def MultiplierRule {
        doc /* multipliers [{name, kind, per, only (optional condition), requires (optional
             all_bands)} ...]: each named set counts its distinct keys among the scoring
             QSOs. kind: dxcc (cty.dat entity), wpx (WstxStrategy::WpxPrefix), continent,
             cq_zone, itu_zone (cty.dat), grid_field (2 characters), grid4, my_grid4 (my
             locator of the QSO, for a rover), call_area(NAME) (ReferenceSets call area of the
             call), exchange(Field) (the received field, ExchangeRule), call. per: contest,
             band, band_mode, round, band_round (the key is joined with these). only: the QSO
             counts for this set only when it holds. requires all_bands: the key counts once
             the call has a scoring QSO on every band of the record. A QSO without the value a
             kind needs adds no key to that set. #63's rules: field_per_band = [{fields,
             grid_field, band}], grid_per_band = [{grids, grid4, band}], none = []. */
    }
    attribute def ScoreRule {
        doc /* score: a ContestExpression over the totals of the scoring QSOs: qsos, points,
             mults (the keys of all sets together), m.NAME (one set). Examples: points *
             mults; qsos * mults; points; points + 500 * m.squares; qsos + 2 * m.areas + 2 *
             m.triples; points * floor(m.grids/3). Additive: exactly points or qsos (needed by
             ScoredWindow best). extras lists what is not computed (power multipliers,
             bonuses, normalised series scores, multipliers FT messages cannot carry). */
    }
    enum def AutomationClause {
        doc /* forbidden: the rules forbid or in effect forbid automatic operation (a warning the
             operator must confirm); silent: the rules do not address it (a short note);
             permitted (#98): the rules allow it (RSGB FT4 OPEN: "any form of automation"; a
             short note, nothing to confirm). automation {clause, text (the clause as the
             rules word it, or that they do not address it), ref (optional), by_section
             (optional: a clause per value of the entry parameter section, the record's
             clause for any other)}. The clause in force is that of the selected section. */
        enum forbidden;
        enum silent;
        enum permitted;
    }
    attribute def EntryRule {
        doc /* entry {eligible (optional condition on my station), workable (optional
             condition on my station and theirs), params [{name, choices (a list of words, or
             "bool"), default} ...] (default none)}. name one of power, section, fd_class,
             canton, province, member, rover, hours, days, category, single_band. eligible:
             when it is false for my station the prompt says "you are not eligible" (a note,
             D4); workable: a station for which it is false is not workable (ContestVerdict).
             A parameter is read by expressions (param, my_member), by a window limit and by
             automation by_section; one that nothing reads is shown only. */
    }
    attribute def ReferenceSets {
        doc /* #98 (CL-098-03). In ContestFile: sets {NAME: [cty.dat primary prefix ...]} (NAME
             ^[A-Z_]{1,12}$): W_VE, VK, PA, HB, OH, I, LA in the bundled file (W_VE: K, KL,
             KH6, VE; the ARRL set is marked unconfirmed); call_areas {NAME: {prefix: area}}:
             the area of a call is that of the longest prefix that starts it (SARL: the call
             areas of the SARL Contest Manual); call_lists {NAME: [call ...]}: club member
             lists (PRO_DIGI, YBDXPI in the bundled file, empty until the organiser's list is
             added; a record whose members list is empty notes "member points not counted").
             CQ and ITU zones, continent and entity come from cty.dat, the WPX prefix from
             WstxStrategy::WpxPrefix; nothing else is looked up. */
    }
    attribute def Subdivisions {
        doc /* #98 (CL-098-03, D16). One table bundled with the station, not part of the
             uploadable file, from the ADIF enumerations: per entry kind (us_state or
             ve_province), code (ADIF STATE of DXCC 291, 6 and 110, or VE_PROV of DXCC 1),
             name, sections (the ARRL/RAC section codes of the ADIF ARRL_SECT enumeration in
             it, e.g. MA: EMA, WMA; HI: PAC) and rtty_ru (true for the RTTY Roundup values).
             It maps a received Field Day section to its state or province and a received
             STATE as is. The decoder's 171 RTTY Roundup values and 86 Field Day sections stay
             as they are (they are message-format tables); every one of them is in this
             table (a test checks it). WstxStrategy's US-state filter (#97) reads it; how a
             station's state is found when no exchange carries it is #97's. */
    }
    attribute def ProfileTable {
        doc /* The records of the bundled ContestFile (#98), in this order; id: name;
             activity and CQ word; bands; modes; dupe; points; multipliers; score; clause;
             schedule (UTC unless a zone is named); entry and notes as the research on #98
             states them. Shared: FT8 and FT4 counted as one mode unless said; HF6 = 160 80 40
             20 15 10 m; VHF = 6 m and every ADIF band above. A rule source that does not state
             something is listed in the record's unconfirmed. Encoding rule: a record encodes
             the rules for a station outside the organiser's area where the rules differ by
             side; a multiplier that FT messages cannot carry and that would be the score's
             only multiplier is an extra, not a multiplier (Hawaii districts, PACCdigi
             provinces).
             ww_digi: CQ WW Digi; ww_digi WW; HF6; [band]; 1 + floor(km(grid4)/3000); fields
             grid_field per band; points * mults; forbidden (IX.12); last full weekend of
             August 0d12:00-1d12:00 (confirmed).
             arrl_digi: ARRL International Digital; arrl_digi TEST; HF6 and 6m;
             digital_no_rtty as one; [band]; 1 + max(1, ceil(km(grid4)/500)); none; points;
             forbidden (OPRG.4); first full weekend of June 0d18:00-2d00:00; window 24 h
             first, off 60 min.
             arrl_field_day: ARRL Field Day; field_day FD; HF6 and VHF; any; [band,
             mode_class]; class{phone: 1, cw: 2, digital: 2}; none; points; extras power
             multiplier, bonus points; forbidden (6.4); fourth full weekend of June
             0d18:00-1d21:00; params fd_class, section, power; eligible note ARRL/RAC and
             IARU R2 (others check-log).
             ft_challenge: International FT Challenge; none; 80 40 20 15 10 m; [band]; if
             grid_known then 1 + floor(km(grid4)/3000) else 1; fields grid_field per band;
             points * mults; forbidden (7.13); first full weekend of December 0d18:00-2d00:00;
             window 24 h first, off 30 min; params power.
             nccc_ft4_sprint: NCCC FT4 Sprint; na_vhf TEST; HF6 and 6m; FT4; [band]; 1; grids
             grid4 per band; qsos * mults; silent; every Friday 0d01:00-0d01:30.
             ft4_field_day: FT4 Field Day; none; HF6; FT4; [band, their_grid4]; if same_grid4
             then 10 else km(grid4, 6378.16); none; points; silent; first Saturday of
             January, April, July, October 0d12:00-1d12:00; window param hours (12 or 24)
             best by hour; standard_messages_only.
             kansas_qp_ft: Kansas QSO Party (FT entry); none; 80 40 20 15 10 6 m; FT8 and FT4
             apart; [band, mode]; 1; none; qsos; silent; dates 2026-08-29 0d14:00-1d02:00 and
             2026-08-30 0d14:00-0d20:00; log email.
             vermont_qp_ft: Vermont QSO Party (FT); none; 30 17 12 m; [band, mode_class];
             class{digital: 2, cw: 3, phone: 1}; grids grid4 per contest; points *
             floor(m.grids/3); extras power factor, out-of-state grid limit; silent; date
             2027-02-06 0d00:00-2d00:00.
             hawaii_qp: Hawaii QSO Party; none; HF6 and 6m; any; [band, mode_class];
             class{digital: 3, else: 0} (phone and CW unconfirmed); none; points; extras
             district, state and province multipliers; silent; date 2026-08-21
             0d16:00-2d04:00.
             arrl_vhf_jan: ARRL January VHF; na_vhf TEST; VHF; any; [band, my_grid4,
             their_grid4] (once per band per pair of grids, so a rover on either side counts
             again from a new grid);
             vhf_january; grids grid4 per band, activated my_grid4 per contest only
             param(rover) = "yes"; points * mults; forbidden (OPRG.4); asked, 0d19:00-2d04:00;
             workable my_in(W_VE) or their_in(W_VE); params category, rover.
             arrl_vhf_jun: ARRL June VHF; as arrl_vhf_jan with vhf_june_september, second full
             weekend of June 0d18:00-2d03:00. arrl_vhf_sep: ARRL September VHF; as
             arrl_vhf_jun in September.
             arrl_222_up: ARRL 222 MHz and Up Distance; eu_vhf; 1.25m 70cm 33cm 23cm 13cm 9cm
             6cm 3cm 1.25cm 6mm 4mm 2.5mm 2mm 1mm; any; [band, my_grid4, their_grid4] keep
             best; band{1.25m: 2, 70cm: 1, 33cm: 4, 23cm: 2, 13cm: 6, 9cm: 10, 6cm: 10, 3cm: 6,
             else: 20} * (if same_grid6 then 1 else km(grid6)); none; points; forbidden
             (OPRG.4); first full weekend of August 0d18:00-1d18:00.
             cq_ww_vhf: CQ WW VHF (digital weekend); na_vhf TEST; 6m 2m; digital; [band,
             their_grid4]; band{6m: 1, 2m: 2}; grids grid4 per band; points * mults; silent;
             third full weekend of July 0d14:00-1d14:00.
             iaru_50_mgm: IARU R1 50 MHz MGM; none; 6m; digital; [band]; kilometres; squares
             grid4 per band; points * mults; silent; third Saturday of April 0d14:00-1d14:00;
             params section SO, MO, 6H (6H a note). iaru_70_mgm: IARU R1 70 MHz MGM; as
             iaru_50_mgm on 4m in May.
             ft8_activity: FT8 Activity; none; 2m 70cm 23cm; [round] (one point per call
             regardless of mode); 1; locators grid4 per round; points * mults; silent; first,
             second, third Wednesday of each month 0d17:00-0d21:00 on 2m, 70cm, 23cm; series
             best 8 of 12 per band; standard_messages_only, no_multistream,
             self_spot_forbidden.
             nac_nrrl: Nordic Activity Contest (NRRL); eu_vhf; Europe/Oslo; any; [round];
             km(grid6) * band{13cm: 2, 9cm: 3, 6cm: 4, 3cm: 5, 1.25cm: 6, 6mm: 7, else: 1};
             squares grid4 per round; points + 500 * m.squares; forbidden (4); Tuesdays 1st 2m,
             2nd 70cm, 3rd 23cm, 4th 13cm and up, Thursdays 2nd 6m, 3rd 4m, 0d19:00-0d23:00;
             series best 9 of 12 per band; eligible my_in(LA).
             rsgb_ft8_ac: RSGB FT8 Activity Contests; none; FT8; [round]; if same_grid4 then
             50 else ceil(km(grid4)); squares grid4 per round; points + 500 * m.squares;
             silent; first Wednesday 2m, second Wednesday 70cm, 0d17:00-0d21:00; series best 8
             of 12 per band, rank; params section, hours (2 or 4).
             ari_ft8_activity: ARI FT8 Activity; none; FT8; [round]; 1; squares grid4 per
             round; points * mults; silent; first Wednesday 2m, second Wednesday 70cm,
             0d17:00-0d20:00 April to October and 0d18:00-0d21:00 November to March; series 12
             of 12, sum_times_rounds; eligible my_in(I).
             wia_ross_hull: WIA Ross Hull Memorial (digital); eu_vhf; VHF; digital; [band,
             mode_class, utc_day]; ceil(km(grid6)/100) * band{6m: 2, 2m: 3, 70cm: 5, 23cm: 8,
             else: 10}; none; points; silent; date 01-01 0d00:00-31d00:00; window param days (7
             or 2) best by utc_day.
             rsgb_ft4_series: RSGB 80 m FT4 Club Championship; none; FT4; [band]; 1; dxcc dxcc
             per contest; points * mults; silent, by_section OPEN permitted; the 2026 dates,
             0d20:00-0d22:00 or 0d19:00-0d21:00; series best 9 of 12, rank; params section
             OPEN or RESTRICTED, power; standard_messages_only.
             rsgb_ft4_iad: RSGB FT4 International Activity Day; none; HF6; FT4; [band]; if
             same_continent then 1 else 3; dxcc dxcc per band; points * mults; silent,
             by_section OPEN permitted; date 2026-04-11 0d12:00-1d12:00; window param hours (12
             or 24) first, off 60 min.
             rsgb_eclipse_ft8: RSGB Eclipse FT8; none; 40m; FT8; []; if same_continent then 1
             else 3; dxcc dxcc per contest; points * mults; permitted; date 2026-08-12
             0d16:30-0d19:30.
             darc_ft4: DARC FT4 Contest; none; 80 40 m; FT4; [band]; 1; prefixes wpx per band;
             points * mults; silent; second Tuesday of February, May, August, November
             0d19:00-0d20:30; params power.
             paccdigi: PACCdigi (VERON); rtty RU; HF6; RTTY, FT8, FT4 with FT8 and FT4 as one;
             [band, mode_group]; if their_in(PA) then 3 else 1; none; points; extras province
             multipliers; forbidden; third full weekend of April 0d12:00-1d12:00; window 18 h
             first, off 60 min; unsendable_for my_in(PA).
             sral_ft8: SRAL FT8 (SM series); na_vhf TEST; Europe/Helsinki; 80 40 m; FT8;
             [band]; 2; squares grid4 per band; points * mults; silent; second Wednesday of
             each month 0d18:00-0d19:00; series best 9 of 12, winner_1000; eligible my_in(OH),
             workable their_in(OH).
             sarl_hf_digi: SARL HF Digital; eu_vhf SARL; 80 40 20 m; [band]; 1; areas
             call_area(SARL) per band, triples call per contest requires all_bands; qsos + 2 *
             m.areas + 2 * m.triples; silent; second Sunday of August 0d13:00-0d16:00.
             africa_ft4: Africa FT4 DX Contest; none; 80 40 20 m; FT4; [band]; if my_cont(AF)
             then (if same_dxcc then 4 else if their_cont(AF) then 6 else 1) else (if
             their_cont(AF) then 4 else 0), points_cap when my_cont(AF) and same_dxcc share
             1/3; none; points; silent; second Saturday of April and September
             0d15:00-0d18:00.
             wia_australia_day: WIA Australia Day (DIGI); none; HF6; [band, mode]; if not
             (my_in(VK) or their_in(VK)) then 0 else (if same_grid4 then 1 else km(grid4));
             none; points; forbidden; date 01-26 -1d22:00-0d10:00.
             zl_sprint_ft4: ZL FT4 Sprint (NZART); ww_digi ZLS; Pacific/Auckland; 80m; FT4;
             [mode]; 1; none; qsos; silent; every Tuesday of April and August 0d21:00-0d21:30;
             log email.
             helvetia: USKA Helvetia; rtty RU; HF6; any (one digital mode per band); [band,
             mode_class]; if their_in(HB) then 10 else if same_continent then 1 else 3; dxcc
             dxcc per band; points * mults; extras canton multipliers; silent; last full
             weekend of April 0d13:00-1d13:00; params canton; unsendable_for my_in(HB) (#100).
             pro_digi: PRO Digi Contest; rtty RU; 80 40 20 15 10 m; PSK63, FT4, RTTY apart;
             [band, mode]; (if same_dxcc then 1 else 2) + (if my_member and their_member then
             6 else if their_member then 2 else 0); prefixes wpx per band only not same_dxcc;
             points * mults; silent; third full weekend of January 0d12:00-1d12:00; params
             member; members PRO_DIGI.
             bucharest_digital: Bucharest Digital Contest; rtty RU; 80 40 m; FT4; [band]; 1;
             none; qsos; silent; third Monday of March 0d18:00-0d21:00.
             ybdxpi_ft8: YB DX Contest FT8; none; HF6; FT8; [band]; if their_member then 5 else
             if same_dxcc then 1 else if same_continent then 2 else 3; prefixes wpx per band,
             dxcc dxcc per band; points * mults; silent; date 2026-11-07 0d00:00-2d00:00;
             members YBDXPI.
             The bundled file is the executable table; its hand oracle is TC-098-001. */
    }
    attribute def ContestHttp {
        doc /* GET /strategy/contests (operating access, no query, empty body; the refusals of GET
             /strategy): {v 1, profile_id, boot_id, file (ContestFileHttp), profiles [...]}. A
             profile on the wire (#98) holds what the prompt shows, not the whole record: id,
             name, organiser, source, checked, cabrillo (log.contest or null),
             cabrillo_confirmed, log_format, activity, cq, bands, modes (words), dupes,
             points, multipliers and score (the record's expressions as text), extras,
             automation (the clause name of the default section), automation_text,
             by_section, schedule (schedule.text), series (words or null), window (words or
             null), entry params, eligible (true, false for my station, or null without a
             rule), exchange_sendable (false when ExchangeRule.unsendable_for holds for my
             station or the activity is one the station cannot be set to), notes, unconfirmed
             and period (null when asked or no date is left, else {start, end, band}:
             ScheduleRule at the time of the request, "YYYY-MM-DDTHH:MMZ", end exclusive,
             band null unless the round names one band). It changes nothing; the browser reads
             it when the period prompt opens and once per connection while a contest is in
             force (for its name), never at a plain page load or reconnect and never on a
             timer. */
    }
    attribute def ContestSelection {
        attribute periodDaysMax : Integer = 31;
        doc /* The optional key contest of WstxStrategy::StrategyConfiguration on PUT /strategy and in
             the GET /strategy snapshot, present only while one is selected: {profile (a profile
             id), start, end (real instants "YYYY-MM-DDTHH:MMZ", end exclusive, start < end, at most
             31 days apart), operation "sp" or "run", repetitions (x of WstxStrategy::LeaveRule,
             1..20, default 2), quiet_minutes (WstxStrategy::QuietTime, 1..120, default 10) and,
             #98, entry (optional: {param: value} for the record's entry params, each a value of
             its choices or a boolean for "bool"; an absent param takes its default; the
             snapshot shows all of them)}.
             Exact keys; each refusal names its field (contest, contest.profile, contest.start,
             contest.end, contest.operation, contest.repetitions, contest.quiet_minutes,
             contest.entry, contest.entry.NAME), 400
             invalid_request like any other field; "colouring" and automation_confirmed are
             refused like any other value or extra key (colouring only is Auto off, and the
             confirmation goes with Auto on, WstxStrategy::AutoToggle). null or absent: no contest. Exactly one strategy
             is active or none: active and contest together are refused with field contest. It
             lives in station memory only: the file never holds it and a station restart starts
             without one (as active, WstxStrategy D2). A changed contest is a changed selection
             (WstxStrategy::StrategyRun: any run ends; with Auto on the new one starts, ContestRun).
             HALT turns Auto off and leaves the contest in force: it then transmits nothing. An MCP principal cannot select one (the PUT
             /strategy principal guard). No alert is recorded for a contest
             (WstxStrategy::Alert follows the active award strategy). The profile is resolved
             in the contest file in use; a file cannot change under a selection
             (ContestFileHttp). */
    }
    attribute def ContestLog {
        doc /* The log read for a contest (#98 D12): the contacts whose QSO_DATE and TIME_ON start
             lies in [start, end) only, with a band of the record (of the round for a round
             with its own bands) and a mode the record counts (ModeRule). Per contact it reads
             CALL, GRIDSQUARE (up to 6 characters), the effective band and mode, the start,
             MY_GRIDSQUARE (else the station locator), STX, SRX, SRX_STRING, STATE, CLASS,
             ARRL_SECT, RST_SENT and RST_RCVD; a record without a band (logged without a
             confirmed CAT dial, WstxContact::DirectLog) counts for nothing. Entity,
             continent, zones and WPX prefix come from cty.dat and WpxPrefix at evaluation.
             In time order: a dupe by DupeRule counts nothing; ScoredWindow decides which of
             the others score; each scoring QSO adds its points (PointsRule, with points_cap)
             and its multiplier keys (MultiplierRule). The tally: qsos, multipliers (mults),
             points and score (ScoreRule); extras are not computed. Unreadable: no claim,
             nothing callable. A contest evaluation reads it on a blocking thread, about one
             read per publication; it scans the records without copying those outside the
             period. */
    }
    attribute def ContestSerial {
        doc /* #98 (CL-098-04, D12). While a contest is selected, the serial number the station
             sends (WstxContact::ContestExchange with the exchange DX or #, and #99's EU VHF
             message) is 1 + the highest STX among the contacts ContestLog reads for the
             selected period (dupes and non-scoring QSOs included) and the contacts this boot
             handed to the log during the period that the log does not show yet; 1 when there
             is none. A contact takes it when its first message carrying the serial is
             generated and keeps it until it ends; a contact that ends without a log entry
             leaves its number free for the next. So a restart, a manual QSO with an STX and
             an imported log continue the count, and no logged serial is sent twice. Without a
             contest selected ContestExchange's boot counter applies as before. */
    }
    attribute def ContestValue {
        doc /* #98 (CL-098-05, D13; open Q1 and Q4 on #98, recommended answers here). The value of
             a decoded station is its projected score gain: S(Z + q) - S(Z), S the record's
             score expression, q the hypothetical QSO with this station now (its points by
             PointsRule, the multiplier keys it adds, one QSO, or nothing when it is a dupe or
             would not score by ScoredWindow), Z the projected end state of the period: each
             total X of the tally (qsos, points, each multiplier set's size) becomes X + r(X)
             * T, where r(X) is X's growth over the last 60 minutes of the period (or since its
             start when that is shorter, counted as at least 15 minutes) per minute, and T the
             minutes from now to the selection's end (for a window first, at most the
             operating time it has left; 0 once it is used up). For points * mults this is p *
             M + m * P + p * m with P and M projected. Unknown locator: for the value only, the
             distance is taken to the centre of the sender's cty.dat entity (as
             WstxStrategy::ValueOrder's distance); the score keeps the rules' value. The
             evaluation is one evaluator call per callable record per publication. */
    }
    attribute def ContestVerdict {
        doc /* WstxStrategy::Verdict with a contest in force, one per decoded record with a resolved
             sender that is standard, or a Field Day exchange (type field_day) to a call, in this
             order of tests: ignored (IgnoreLists, as a strategy); greyed
             (DirectedCqRule with ContestDirective); "my own message"; "band unknown"; "band not
             in the contest"; "mode not in the contest" (#98: the station's mode is not counted
             by ModeRule); "log unreadable"; "not workable" (#98: EntryRule workable is false
             for this sender; also a caller of my call, open Q3 on #98); "dupe" (DupeRule for
             the station band and mode, mode class Digital, my locator the station's; rank
             null, dupe true, also when it calls my call: operator #63 "non-dupe", the one
             difference from WstxStrategy D5); a caller of my call (CallerOfMyCall, also a grid
             or Field Day exchange to it); else the callsign guard (SaneCall; a /R rover passes
             where their_grid4 is a dupe dimension); else "not a CQ": a CQ or an RR73/73 to
             someone else counts as calling, in every contest; else "no score" (#98: value 0,
             ContestValue; not for a caller of my call, open Q3 on #98). So the callable records
             have a rank by ContestValueOrder; every other has rank null. These are the contest's
             rules: the operator's filters of WstxStrategy (#97) are applied after them to the
             callable records only, and can remove a record, never re-admit one. The reply's
             verdicts carry dupe, new_multiplier (the record adds a key to any multiplier set;
             false without the value its kind needs), points (PointsRule; null when not known)
             and value (#98: ContestValue rounded half up; null without a rank).
             POST /strategy/evaluate with strategy null and a contest in force returns these, with
             strategy the profile's name and contest the tally {qsos, multipliers, points, score}
             (null when the log is unreadable); explain false lists the ranked, the greyed and the
             dupes. A draft strategy still previews the draft. why: "calls my call", "new
             multiplier", "<n> points", "value <v>" joined by " \· ", or the reason above. */
    }
    attribute def ContestValueOrder {
        doc /* Smaller first: callers of my call before the others (WstxStrategy D5; only callers
             with a rank, never a dupe); then the larger ContestValue (#98, replacing "a new
             multiplier, then more QSO points"); then the strongest SNR (unknown last); then, for
             an exact tie only, the lower audio frequency, then the call (strategydef Q3, Q9:
             decode order is never a ranking). Replaces WSJT-X's first decoded (operator #63). */
    }
    attribute def ContestPrompt {
        doc /* The Contest button of the strategy element opens a modal dialog with its own HALT (the
             top-bar HALT's action, as WstxStrategy::StrategyEditor); receive keeps running. It reads
             GET /strategy/contests once at opening, so the pre-fill is current. It offers the
             profiles in file order; Start and End (UTC, to the minute): the selection in force when it matches, else
             the profile's period, empty when asked or no date is left; the schedule in words; the operation S&P or
             Run (S&P the default); "Repetitions before leaving" (default 2) and "Quiet time
             (minutes)" (default 10); #98: one control per entry param (its choices, its
             default, or the value in force), the organiser, source and the date the rules were
             checked, the CQ word, "You are not eligible" when eligible is false, "The station
             cannot send this contest's exchange yet" when exchange_sendable is false, the
             series and window in words, the extras as "not computed", and the unconfirmed
             facts; the automation text of the clause in force for the chosen section and the
             notes. Whether it transmits is
             the Auto toggle's (WstxStrategy::AutoToggle): a forbidden clause asks its
             confirmation when Auto is switched on, not at Start. When the profile's
             activity differs from the station's, one line says so. Start with an empty period
             asks for it and sends nothing; else one PUT /strategy with active null and contest
             (with entry). Cancel
             changes nothing. In the selector the contest in force is one more option "<name>
             (contest)"; None or an award strategy sends a PUT without contest (the selector's other
             rule, WstxStrategy::StrategySelector, is unchanged). */
    }
    attribute def ContestView {
        doc /* With a contest in force the browser renders the verdicts as WstxStrategy::ValueView
             does, on the same events (a new publication, a save; never a timer). Band Activity lists
             only the rows with a rank, in rank order under the value sort; rows to my call and the
             partner rows stay (#50); every other row is hidden. Show all (a toggle in the strategy
             element, visible only with a contest, off at each page load, kept in the page only)
             shows them all again without a new request: a dupe, a greyed, a not workable and a
             no-score row dimmed, no colour; a
             row with a new multiplier has its own colour beside the strategy mark
             (WstxOperatingLayout::BandActivityColours: only interesting stations). The colour slots of the
             all-time log (new call, DXCC, zone, grid and LotW) are off while a contest is in force,
             their reasons leave the hover too, and they come back with its end: QSOs outside the
             period do not count (the My call slot stays; the Settings choice is unchanged). The hover names "#n",
             new multiplier, points and value (#98), or the reason. The status beside it: "Contest <name> \· <MM-DD
             HH:MM> to <MM-DD HH:MM> UTC \· <S&P or Run> \· Auto <on or off>" (Auto off is colouring only) and, once evaluated, " \· <n> QSOs \· <m>
             mult \· score <s>". Manual operation stays as it is: every row selects as ever, the
             double-click and the directive warning unchanged. */
    }
    attribute def ContestRun {
        attribute repetitionsDefault : Integer = 2;
        attribute quietMinutesDefault : Integer = 10;
        doc /* A contest with Auto on is a WstxStrategy::StrategyRun: one run at a time, through
             the same internal path and the same contact engine, started only by a browser's
             selection with Auto on or Auto on (WstxStrategy::AutoToggle). Unchanged: HALT stops
             every run from any source and turns Auto off (revision + 1, pushed by
             strategy.state; the contest, its operation and period stay); Esc
             changes neither; ManualIntervention (a double-click always, the run resumes after the
             QSO); WatchdogFromOperator; the 8 hour run limit (run_limit) and 60 s without a client
             (no_client), finishing the QSO first, with the contest staying selected, Auto off
             and the reason shown; the grant (authority_lost); WstxStrategy::FreeTxSlot; an
             AutomationCommand start of what it left is refused operator_required. A contact that
             is no started QSO ends at once at the end of the period (the run waits
             outside_period) and when the contest is deselected (WstxStrategy::StrategyRun
             "Ends at once"); a started QSO is finished (#81, WstxStrategy::StartedQso).
             Waiting reasons in a contest (run.reason while state waiting), besides no_receive,
             auto_seq and call: activity (the station's activity is not the profile's; always
             for eu_vhf until the station can be set to it, #99), band (the
             station band is not in the profile), mode (#98: the station's mode is not counted
             by the profile), exchange (#98: ExchangeRule.unsendable_for holds for my station),
             outside_period (the station clock is outside
             [start, end)). It selects nothing and calls nothing until the reason is gone.
             sp: on each fresh complete publication the list is ContestVerdict with a rank, one per
             call, not completed in this run on this band and mode nor given up; the first is selected
             as a strategy run selects, not in its QuietTime. Leaving: WstxStrategy::LeaveRule with
             the contest's repetitions and quiet_minutes; no skip (WstxStrategy D6).
             run: while waiting and no reason it decides the slot (FreeTxSlot, no called station;
             with Hold Tx on the held Tx, no decision, WstxStrategy D16) and
             sends enable_tx with no partner, which calls CQ with the activity's Tx6 carrying
             the contest's CQ word (ContestDirective, open Q2 on #98); state
             calling_cq. WstxContact::CallFirst does not answer a CQ started by automation. On each
             fresh complete publication of the partner's parity the callers of my call
             (ContestVerdict kind caller: a dupe has no rank; in ContestValueOrder; not worked in this
             run on this band and mode, not given up, not in QuietTime) are read; the first is selected with
             select_row {replace false}, which keeps Enable Tx, and Tx stays on its slot
             (WstxStrategy::FreeTxSlot with that station). No caller: the CQ goes on. In the contact
             as sp; after completion or a leaving it waits, so the next step calls CQ again.
             In calling_cq: a reason appearing disarms and cancels the CQ and it waits; run_limit
             or no_client disarm and cancel the CQ at once and stop (there is no exchange to
             end); an operator's selection or cancel makes it manual; a disarm stops it with
             the cause (tx_watchdog, transmit_stopped): the Tx watchdog counts a repeated CQ like
             any message, so a Run on a silent band stops at its limit until a new selection (the
             step that sees the disarm stops it tx_watchdog, and an automatic enable_tx after a
             watchdog stop is refused besides, WatchdogFromOperator). Every stop
             and a selection cancel a CQ of the run: none is left to read as the operator's contact.
             Esc on the run's own CQ ends that CQ; the run calls again. A dupe caller has no
             rank: it is never answered and never ends a stay (the #63 fix: the stay check read
             the award evaluator, which counts any caller); every check of a contest run reads
             ContestVerdict.
             The log: ContestLog of the last build on the station step, built at the selection
             first; each step of the run asks for it, so a build behind the log runs on its own
             thread as soon as a QSO is logged, also a manual one, well before the next
             publication; until it is done a QSO is held off by this run's own completed list. Band Activity follows ContestView; the status
             names "calling CQ", "<call>", "your QSO", "waiting · <reason>", "stopped · <reason>"
             or "not started · <reason>" from GET /automation on automation.state only, never a
             timer. The prompt offers S&P and Run; AutomationClause forbidden (of the section in
             force) asks
             WstxOperatingLayout's confirmation with the clause's text when Auto is switched on
             and sends automation_confirmed true with POST /strategy/auto, nothing when
             declined; silent and permitted ask nothing, the clause is on the prompt. After a stop only Auto
             on starts it again. No band hopping. */
    }
    attribute def ContestDirective {
        doc /* WstxStrategy::DirectedCqRule in a contest activity: the word of the station's
             current activity (na_vhf and arrl_digi TEST, ww_digi WW, field_day FD, rtty RU) is
             answerable, also with my continent unknown. So it is not greyed, a selection needs no
             directive_confirmed, and a word outside its activity keeps the warning. It depends on
             the activity alone, not on a selected contest strategy (D2).
             #98 (D14; open Q2 on #98, recommended answer here): while a contest is selected and
             the station's activity is the record's, the record's CQ word is answerable in the
             same way, and every CQ the station sends (Tx6, by the operator or a Run) carries
             that word instead of the activity's; without a contest, or in another activity,
             only the activity's word as before. */
    }

    dependency profileClause from ContestProfile to WstxRequirements::'CL-063-01';
    dependency scheduleClause from ScheduleRule to WstxRequirements::'CL-063-01';
    dependency tableClause from ProfileTable to WstxRequirements::'CL-063-01';
    dependency httpClause from ContestHttp to WstxRequirements::'CL-063-01';
    dependency directiveClause from ContestDirective to WstxRequirements::'CL-063-02';
    dependency directiveOwner from ContestDirective to WstxStrategy::DirectedCqRule;
    dependency selectionClause from ContestSelection to WstxRequirements::'CL-063-03';
    dependency promptClause from ContestPrompt to WstxRequirements::'CL-063-03';
    dependency logClause from ContestLog to WstxRequirements::'CL-063-03';
    dependency verdictClause from ContestVerdict to WstxRequirements::'CL-063-04';
    dependency orderClause from ContestValueOrder to WstxRequirements::'CL-063-04';
    dependency viewClause from ContestView to WstxRequirements::'CL-063-04';
    dependency runClause from ContestRun to WstxRequirements::'CL-063-05';
    dependency runSafety from ContestRun to WstxRequirements::'CL-063-06';
    dependency runPath from ContestRun to WstxStrategy::StrategyRun;

    // #98 contest data
    dependency fileClause from ContestFile to WstxRequirements::'CL-098-01';
    dependency fileHttpClause from ContestFileHttp to WstxRequirements::'CL-098-01';
    dependency fileOwner from ContestFile to WstxContact::CountryFile;
    dependency recordClause from ContestProfile to WstxRequirements::'CL-098-02';
    dependency scheduleData from ScheduleRule to WstxRequirements::'CL-098-02';
    dependency windowClause from ScoredWindow to WstxRequirements::'CL-098-02';
    dependency seriesClause from SeriesRule to WstxRequirements::'CL-098-02';
    dependency modeClause from ModeRule to WstxRequirements::'CL-098-02';
    dependency exchangeClause from ExchangeRule to WstxRequirements::'CL-098-02';
    dependency dupeClause from DupeRule to WstxRequirements::'CL-098-02';
    dependency expressionClause from ContestExpression to WstxRequirements::'CL-098-02';
    dependency pointsClause from PointsRule to WstxRequirements::'CL-098-02';
    dependency multiplierClause from MultiplierRule to WstxRequirements::'CL-098-02';
    dependency scoreClause from ScoreRule to WstxRequirements::'CL-098-02';
    dependency clauseData from AutomationClause to WstxRequirements::'CL-098-02';
    dependency entryClause from EntryRule to WstxRequirements::'CL-098-02';
    dependency tableData from ProfileTable to WstxRequirements::'CL-098-02';
    dependency setsClause from ReferenceSets to WstxRequirements::'CL-098-03';
    dependency subdivisionsClause from Subdivisions to WstxRequirements::'CL-098-03';
    dependency logData from ContestLog to WstxRequirements::'CL-098-04';
    dependency serialClause from ContestSerial to WstxRequirements::'CL-098-04';
    dependency serialOwner from ContestSerial to WstxContact::ContestExchange;
    dependency valueClause from ContestValue to WstxRequirements::'CL-098-05';
    dependency verdictData from ContestVerdict to WstxRequirements::'CL-098-05';
    dependency orderData from ContestValueOrder to WstxRequirements::'CL-098-05';
    dependency directiveData from ContestDirective to WstxRequirements::'CL-098-05';
    dependency selectionData from ContestSelection to WstxRequirements::'CL-098-06';
    dependency promptData from ContestPrompt to WstxRequirements::'CL-098-06';
    dependency httpData from ContestHttp to WstxRequirements::'CL-098-06';
    dependency runData from ContestRun to WstxRequirements::'CL-098-06';
}

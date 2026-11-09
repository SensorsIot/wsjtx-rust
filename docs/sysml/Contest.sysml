package WstxContest {
    private import ScalarValues::*;
    doc /* Canonical contract of the contest strategies (issue #63, CL-063-01..06 in
         WstxRequirements; verification TC-063-001..012; contest data issue #98, CL-098-01..06,
         TC-098-001..015): the second strategy class beside WstxStrategy's award strategies.
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
            contests are data now; a record's workable rule is acted on, operator Q3 on #98;
            its eligible rule stays a note, EntryRule.)
         D5 January VHF is not computed, the period prompt asks; IARU MGM uses standard FT8
            messages with report and 4-character locator; a full weekend has Saturday and
            Sunday both in the month; an unconfirmed Cabrillo name stays marked. (#98: an
            operating-time limit a record states as a window is computed, ScoredWindow; any
            other stays a note.)
         D6 Contest strategies are not saved strategies: the profiles are data, and the choice with
            its period is the selection (ContestSelection), never written to the file. The award
            strategy class on the wire stays award (WstxStrategy::StrategyClass): a saved strategy
            of class contest stays refused. (#97 replaces this: see ContestStrategyInterface.)
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
         D13 The value of a station is the projected score gain (ContestValue; operator Q1:
            the last 60 minutes' rate; Q4: a station without a grid is estimated from its
            country centre); callers of my call first (ContestValueOrder).
         D14 A per-contest CQ word (ExchangeRule cq; ContestDirective; operator Q2: both the
            station's CQ and the answerable word).
         D15 The operator's filters (WstxStrategy, #97) apply on top of the contest's rules
            and never widen them (ContestVerdict); stations that score nothing for me are not
            callable, a not-workable caller is not answered (operator Q3); a started QSO is
            always finished (#81).
         D16 Reference data: named entity sets, call areas and call lists in the contest file
            (ReferenceSets); one table of US states, VE provinces, ARRL and RAC sections and the
            other RTTY Roundup exchange values bundled with the station (Subdivisions), also
            read by #97's state filter. CQ and ITU zones and the WPX prefix stay those of
            cty.dat and WstxStrategy::WpxPrefix.
            The definer's listed defaults are on #98. */

    // ---------------------------------------------------------------- the contest file (#98)
    attribute def ContestFile {
        attribute bytesMax : Integer = 1048576;
        doc /* #98 (CL-098-01). All contests are one JSON file (UTF-8, at most bytesMax bytes;
             exactly bytesMax is accepted): {"format": 1, "contests": [ContestProfile ...],
             "sets": {...}, "call_areas": {...}, "call_lists": {...}}; sets, call_areas and
             call_lists may be absent (empty). At every level the keys are exactly those named
             in this package: a required key missing or any other key is refused; an optional
             key takes its stated default. The bundled file is embedded in the station; its
             records are ProfileTable and it passes the same validation (its test fails
             otherwise). An uploaded file replaces it per station profile as contests.json
             beside contacts.adi (written to a temporary file, flushed, renamed under the
             publication gate, as WstxContact::CountryFile); a stored upload that cannot be
             read or does not validate leaves the bundled file in use, is reported
             (upload_unreadable) and is never overwritten. Nothing is downloaded automatically.
             JSON encoding (ContestEncoding) and validation, complete before anything changes:
             valid JSON of that shape; at least one contest; each id matching
             ^[a-z0-9_]{1,32}$ (32 characters accepted, 33 refused) and unique; name 1..40
             printable ASCII (40 accepted, 41 refused); organiser 1..60 printable ASCII; source
             an http or https URL; checked a real date YYYY-MM-DD; bands from the ADIF band list
             of WstxContest::ProfileTable (HF6, 60m, 30m, 17m, 12m and VHF); modes (ModeRule);
             each expression parses (ContestExpression) and uses only what its context allows;
             every set member is the primary prefix of an entity of the cty.dat in use
             (WstxContact::CountryFile); a cq word is 1..4 letters A-Z or three digits (the
             standard CQ modifier that packs); every round's end lies after its start; a time
             zone is UTC or a known IANA zone; a window best only with an additive score; a
             members, call_area or param name that exists. The first fault is refused with its
             JSON path (contests[3].points) and a reason; nothing changes. A set member that a
             later cty.dat no longer has matches no call (no refusal after the fact). */
    }
    attribute def ContestEncoding {
        doc /* #98 (CL-098-02). The JSON form of every part. Text is a JSON string of printable
             ASCII; a list is a JSON array; numbers are JSON numbers.
             Expressions (points, score, only, points_cap when, eligible, workable) are strings
             in ContestExpression. Parametrised names are one string "name:argument": the
             multiplier kinds "call_area:SARL" and "exchange:section", the restriction
             "min_band_stay:5" (whole minutes). points_cap {"when": string, "share": [n, d]}
             with whole numbers 1 <= n < d. A window limit is a number or {"param": name}.
             An entry param {"name", "choices", "default"}: choices "bool" with default true or
             false (a bool param is used directly as a true/false condition, e.g. the ARRL
             VHF rover multiplier and my_member), or a list of 1..8 distinct words (1..16 characters) or of 1..8 distinct
             whole numbers, default one of them. by_section {VALUE: {"clause", "text"}}.
             notes, extras and unconfirmed are lists of strings of 1..200 characters; an
             unconfirmed entry is "field path: words" (e.g. "log.contest: from the contest
             calendar, not the rules"). Days of a round: {"full_weekend": 1..5 or "last",
             "month": 1..12}, {"weekday": "MON".."SUN", "n": 1..5 or "last" or "every",
             "months": "all" or [1..12 ...]}, {"date": "MM-DD"}, {"dates": ["YYYY-MM-DD"
             ...]}, {"asked": true}; time ["Nd HH:MM", "Nd HH:MM"]. */
    }
    attribute def ContestFileHttp {
        doc /* #98 (CL-098-01). GET /strategy/contests (ContestHttp) carries file {source
             "bundled"|"uploaded", contests (the number of records), upload_unreadable}.
             PUT /strategy/contests {v, profile_id, boot_id, text} with exactly these keys,
             body at most 2 MiB (a larger body 413 request_too_large, as PUT /dxcc): text null
             removes the upload (bundled again); a string of at most ContestFile::bytesMax
             bytes replaces the file when it validates, else 400 {error:{code
             invalid_contests, field text, path, reason}}; a longer string or any other text
             400 invalid_request text. While a contest is selected (ContestSelection) the PUT
             is refused 409 state_conflict field contest and changes nothing, so a clause the
             operator confirmed never runs under rules replaced after it. Profile, boot,
             Origin and authorization checks as PUT /dxcc (WstxContact::CountryFileHttp); an
             MCP principal is refused as on PUT /strategy. 200 is the new GET view.
             Settings > General shows "Contest rules: bundled|uploaded, N contests" with
             Upload and Use bundled beside the cty.dat control; a refusal shows its path and
             reason and changes nothing. */
    }
    attribute def ContestProfile {
        doc /* One record of ContestFile: rule facts of one contest, no behaviour of its own.
             Required keys: id; name; organiser; source; checked (the date the rules were last
             read); log {format cabrillo|edi|adif|email, contest (the log name or null),
             confirmed (true or false; an unconfirmed name stays marked)}; schedule
             (ScheduleRule); bands; exchange (ExchangeRule: activity required); dupe
             (DupeRule: per required); points (PointsRule); score (ScoreRule).
             Optional keys and their defaults: modes (ModeRule; FT8 and FT4 counted as one
             mode); points_cap (none); multipliers ([]); extras ([]); automation (silent,
             text "The rules do not address automatic operation.", ref null, no by_section);
             restrictions ([]); entry (EntryRule; no rule, no params); members (null: the name
             of a call list of ReferenceSets holding the club members); notes ([]); unconfirmed
             ([]).
             restrictions, each shown as a note and none enforced by the station, which sends
             one signal, never spots and never changes band by itself: single_signal,
             no_multistream, no_alternating_cq, standard_messages_only (encoded as the
             activity none), self_spot_forbidden, self_spot_limited, self_spot_allowed,
             min_band_stay:N. */
    }
    attribute def ScheduleRule {
        doc /* schedule {tz (default "UTC"; else an IANA zone: the day rules and times are that
             zone's local calendar and clock, so a period follows its daylight saving),
             rounds [Round ...] (at least one), text (the schedule in words for the prompt),
             series (optional, SeriesRule), window (optional, ScoredWindow)}.
             Round {day (a day rule), time [start, end] ("Nd HH:MM", N a whole number of
             days, also negative, from the anchor day; end exclusive and after start), bands
             (optional: the round's own bands, else the record's), label (optional)}.
             Day rules, the anchor day of a round in a month: full_weekend n or "last" of a
             month: the n-th or last Saturday whose Sunday is in the same month; weekday with
             n 1..5, "last" or "every" and months "all" or a list: that weekday of each listed
             month (every: each of them); date "MM-DD" each year; dates: only those days;
             asked: not computable, the prompt asks. #63's forms map to these: FullWeekend,
             LastFullWeekend, Saturday {month, n} = weekday SAT n months [month], EveryMonth =
             months "all". A seasonal time is two rounds with disjoint month lists.
             The current or next occurrence is the earliest occurrence of any round that has
             not ended at that instant; none when every round is asked or every listed date
             has passed (the prompt then asks, as for asked). The period of a selection is
             one occurrence; a round's bands narrow the record's bands for it. */
    }
    attribute def ScoredWindow {
        doc /* window {limit (a number, or {param}: an entry parameter that holds it), unit
             "hour" (default) or "utc_day", scored "first" or "best", min_off_minutes
             (default 0)}: which QSOs of the period score (ContestLog).
             first: the operating time is accumulated over the non-dupe QSOs in time order; a
             gap between two consecutive QSOs of at least min_off_minutes (exactly
             min_off_minutes included) is off time, every shorter gap is operating time; a QSO
             scores while the operating time up to it is at most limit hours.
             best: the limit units (whole UTC hours or UTC days) with the most points score,
             the rest do not; a tie goes to the earlier unit. best is valid only with an
             additive score (ScoreRule), else the file is refused.
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
        doc /* modes {count, as_one}. count: a list of mode names from FT8, FT4, RTTY, PSK31,
             PSK63, CW, SSB, AM, FM, or one class: "digital" (every mode but phone and CW),
             "digital_no_rtty", "any"; default ["FT8", "FT4"]. as_one: a list of mode lists
             that are one mode for the dupe dimension mode_group, "all" (one mode regardless),
             or [] (every mode apart); default [["FT8", "FT4"]].
             A logged contact matches a mode name when its MODE or its SUBMODE equals it,
             case-insensitive (the station logs FT8 as MODE FT8 and FT4 as MODE MFSK with
             SUBMODE FT4; a PSK63 contact imported or updated from other software is MODE PSK
             with SUBMODE PSK63; the station itself logs only FT8 and FT4, WstxContact::LogRecord).
             Phone is SSB, USB, LSB, AM, FM, DIGITALVOICE; CW is CW; every other mode is digital
             (the mode class). A contact whose mode is not counted is not read. The station's
             own mode (FT8 or FT4) is checked against count for its verdicts and run. */
    }
    attribute def ExchangeRule {
        doc /* exchange {activity, cq (optional), sent (optional), rcvd (optional),
             unsendable_for (optional condition on my station)}.
             activity: the WstxContact::SpecialActivity the station operates the contest in:
             none (standard messages), na_vhf, ww_digi or arrl_digi (grid exchange),
             field_day, rtty (RTTY Roundup message), or eu_vhf (report, serial and 6-character
             locator; accepted in the file before the station can send it, #99; until then
             the station is never in it and a contest run waits activity).
             cq: the contest's CQ word; default the activity's word (TEST for na_vhf,
             arrl_digi and eu_vhf, as #99 sends it; WW, FD, RU; none for none, a plain CQ).
             sent and rcvd: lists of Field; defaults by activity: none sent [report], rcvd
             [report, grid4]; na_vhf, ww_digi, arrl_digi [grid4] both; field_day [fd_class,
             section] both; rtty [rst, serial] both; eu_vhf [report, serial, grid6] both.
             Field: grid4, grid6, report, rst, serial, fd_class, section, state_province,
             canton, province, member_flag, county; they name what travels and where
             ContestLog reads it (serial SRX, section ARRL_SECT, fd_class CLASS, state_province
             STATE, grid4 and grid6 GRIDSQUARE, report and rst RST_RCVD; canton, province,
             county and member_flag SRX_STRING).
             unsendable_for: when it holds for my station, the station cannot send the
             exchange my side owes (Helvetia as an HB station: the canton, #100; PACCdigi as a
             PA station: the province); the prompt says so and a contest run waits exchange. */
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
             QSOs that dupe each other, the one with the most points counts (the earlier on a
             tie) and the others are dupes (ARRL 222: the longest per pair of grids).
             #63's four rules are band = per [band]; band_mode_class = per [band, mode_class];
             band_grid = per [band, their_grid4]; call = per []. */
    }
    attribute def ContestExpression {
        doc /* The small expression language (#98). Grammar, lowest precedence first:
             expr = "if" cond "then" expr "else" expr | sum; the else branch extends as far
             right as possible, to the end of the enclosing parentheses, table entry, argument
             or text, so "if same_grid4 then 50 else floor(km(grid4, iaru)) + 1" is 50 for the
             same square (an if inside a sum needs parentheses). sum = term (("+" | "-")
             term)*; term = factor (("*" | "/") factor)*; factor = number | variable |
             function "(" args ")" | table | "(" expr ")". number: decimal (3000, 6378.16).
             Functions: floor, ceil, max, min (two arguments). table: band{6m: 1, 2m: 2,
             else: 4} on the QSO's band, class{phone: 1, cw: 2, digital: 2} on its mode class;
             a key not listed takes else; a table without else is refused when the record's
             bands or modes can reach a missing key. cond = "not" cond | cond "and" cond |
             cond "or" cond (and binds tighter than or) | "(" cond ")" | a truth-valued
             variable | expr ("=" | "!=" | "<" | "<=" | ">" | ">=") expr | param(name) "="
             "word". x/0 is 0. A number is exact while whole and a 64-bit float otherwise;
             points and score on the wire are rounded half up to whole numbers.
             Contexts and what each may use (validation refuses anything else):
             points and points_cap when: every QSO variable of PointsRule;
             multiplier only: the QSO variables that are truth values and comparisons of the
             others; eligible: my_in, my_cont, my_member, param; workable: my_in, my_cont,
             their_in, their_cont, same_dxcc, same_continent, my_member, their_member, param
             (no locator, so it holds for a decoded station without a grid); score: qsos,
             points, mults, m.NAME and the functions, no condition; a window limit: a number
             or a param. */
    }
    attribute def PointsRule {
        doc /* points: a ContestExpression giving one QSO's points from its variables:
             km(grid4 or grid6, earth): great-circle distance between the centres of my and
             their locator cut to 4 or 6 characters; earth 6371 (default), 6378.16 or iaru
             (111.2 km per degree); no value without both locators (then the points are 0);
             same_grid4, same_grid6, grid_known (their grid known); same_dxcc,
             same_continent; their_in(SET), my_in(SET) (the entity's primary prefix in a set
             of ReferenceSets); their_cont(XX), my_cont(XX) (continent code); their_member
             (their call in the record's members list), my_member (the bool entry parameter
             member); param(name) (an entry parameter); band{...}, class{...}. My locator is
             the QSO's MY_GRIDSQUARE, else the station locator; their locator its GRIDSQUARE.
             points_cap {when, share n/d} (the organiser's form, Africa FT4 "1/3 of the total
             log items submitted"): with N the scoring QSOs of the period, of the QSOs for
             which when holds only the first floor(N * n / d) in time order keep their points;
             the others score 0. Evaluated on the whole period at each evaluation.
             #63's seven rules are these expressions: one_plus_per_3000_km 1 +
             floor(km(grid4)/3000); one_plus_per_500_km_up 1 + max(1, ceil(km(grid4)/500));
             field_day class{phone: 1, cw: 2, digital: 2}; vhf_january band{6m: 1, 2m: 1,
             1.25m: 2, 70cm: 2, 33cm: 4, 23cm: 4, else: 8}; vhf_june_september the same with
             33cm and 23cm 3 and else 4; kilometres if same_grid4 then 50 else floor(km(grid4,
             iaru)) + 1; one_per_call 1. */
    }
    attribute def MultiplierRule {
        doc /* multipliers [{name, kind, per, only (optional condition), requires (optional,
             "all_bands")} ...], names unique per record: each named set counts its distinct
             keys among the scoring QSOs. kind: dxcc (cty.dat entity), wpx
             (WstxStrategy::WpxPrefix), continent, cq_zone, itu_zone (cty.dat), grid_field (2
             characters), grid4, my_grid4 (my locator of the QSO, for a rover),
             call_area:NAME (ReferenceSets), exchange:FIELD (the received field,
             ExchangeRule), call. per: contest, band, band_mode, round, band_round (the key is
             joined with these). only: the QSO counts for this set only when it holds.
             requires all_bands: the key counts once the call has a scoring QSO on every band
             of the record. A QSO without the value a kind needs adds no key to that set.
             #63's rules: field_per_band = [{fields, grid_field, band}], grid_per_band =
             [{grids, grid4, band}], none = []. */
    }
    attribute def ScoreRule {
        doc /* score: a ContestExpression over the totals of the scoring QSOs: qsos, points,
             mults (the keys of all sets together), m.NAME (one set). Additive: exactly
             "points" or "qsos" (needed by ScoredWindow best). extras lists what is not
             computed (power multipliers, bonuses, multipliers FT messages cannot carry). */
    }
    enum def AutomationClause {
        doc /* forbidden: the rules forbid or in effect forbid automatic operation (a warning the
             operator must confirm); silent: the rules do not address it (a short note);
             permitted (#98): the rules allow it (a short note, nothing to confirm).
             automation {clause, text, ref (optional), by_section (optional: {VALUE: {clause,
             text}} for values of the entry parameter section; the record's clause and text
             for any other value)}. The clause in force is that of the selected section. */
        enum forbidden;
        enum silent;
        enum permitted;
    }
    attribute def EntryRule {
        doc /* entry {eligible (optional condition on my station), workable (optional
             condition on my station and theirs), params [Param ...] (default [])}. A param
             name is one of section, hours, days, rover, member, power, category, canton,
             province, fd_class, single_band, unique per record. eligible: when it is false
             for my station the prompt says "You are not eligible" (a note, D4); workable: a
             station for which it is false is not workable (ContestVerdict). A parameter is
             read by expressions (param, my_member), by a window limit and by automation
             by_section; its value lives on the selection (ContestSelection), never in the
             file. */
    }
    attribute def ReferenceSets {
        doc /* #98 (CL-098-03). In ContestFile: sets {NAME: [cty.dat primary prefix ...]} (NAME
             ^[A-Z_]{1,12}$); call_areas {NAME: {PREFIX: AREA, "*": AREA}}: the area of a call
             (upper case, as decoded) is that of the longest PREFIX that starts it, else "*"
             (absent: no area, no key); call_lists {NAME: [call ...]}: club member lists.
             The bundled file holds exactly:
             sets W_VE [K, KL, KH6, VE] (ARRL's exact W/VE set unconfirmed), VK [VK], PA [PA],
             HB [HB], OH [OH], I [I], LA [LA];
             call_areas SARL (SARL Contest Manual 2027, HF contests 6.4): ZS1, ZR1, ZU1 area 1;
             ZS2, ZR2, ZU2 area 2; ZS3, ZR3, ZU3 area 3; ZS4, ZR4, ZU4 area 4; ZS5, ZR5, ZU5
             area 5; ZS6, ZR6, ZU6 area 6; V5 area 7; 3DA, 7P, 7Q, 9J, C9, A2, D2, Z2, ZD7, ZD9,
             ZS7, ZS8, FR, 3B8, 5R, FH, D6 area 8; "*" area 9 (the rest of the world);
             call_lists PRO_DIGI [] and YBDXPI [] (empty until the organiser's list is added;
             a record whose members list is empty shows the note "member points not counted").
             CQ and ITU zones, continent and entity come from cty.dat, the WPX prefix from
             WstxStrategy::WpxPrefix; nothing else is looked up. */
    }
    attribute def Subdivisions {
        doc /* #98 (CL-098-03, D16). One table bundled with the station, not part of the
             uploadable file. Each row is {kind, code, name, maps_to [codes], rtty_ru, fd}:
             us_state: the 50 states and DC, code the ADIF STATE (Primary Administrative
             Subdivision) of DXCC 291, AK of 6 and HI of 110; maps_to [itself].
             ve_province: AB BC MB NB NL NS NT NU ON PE QC SK YT, the ADIF VE_PROV codes of
             DXCC 1; maps_to [itself].
             ve_alias: the RTTY Roundup codes of WSJT-X that are older province codes: NWT to
             NT, NF to NL, LB to NL, PEI to PE.
             nl_province: DR FR GD GR OV ZH ZL (the PACC province codes WSJT-X carries);
             maps_to [itself]; no state.
             rtty_number: X01 to X99; maps_to []; no state.
             arrl_section (ARRL section list): AK AK, AL AL, AR AR, AZ AZ, CO CO, CT CT, DE DE,
             EB CA, EMA MA, ENY NY, EPA PA, EWA WA, GA GA, IA IA, ID ID, IL IL, IN IN, KS KS,
             KY KY, LA LA, LAX CA, MDC MD and DC, ME ME, MI MI, MN MN, MO MO, MS MS, MT MT, NC
             NC, ND ND, NE NE, NFL FL, NH NH, NLI NY, NM NM, NNJ NJ, NNY NY, NTX TX, NV NV, OH
             OH, OK OK, OR OR, ORG CA, PAC HI, PR none (DXCC entity KP4), RI RI, SB CA, SC SC,
             SCV CA, SD SD, SDG CA, SF CA, SFL FL, SJV CA, SNJ NJ, STX TX, SV CA, TN TN, UT UT,
             VA VA, VI none (DXCC entity KP2), VT VT, WCF FL, WI WI, WMA MA, WNY NY, WPA PA, WTX
             TX, WV WV, WWA WA, WY WY (71 sections).
             rac_section (RAC section list): AB AB, BC BC, GH ON, MB MB, NB NB, NL NL, NS NS,
             ONE ON, ONN ON, ONS ON, PE PE, QC QC, SK SK, TER NT and NU and YT (14 sections).
             dx: DX (the Field Day exchange outside W/VE); maps_to [].
             rtty_ru is true exactly for the 171 values of the decoder's RTTY Roundup table
             (us_state 51, ve_province AB BC MB NB NS QC ON SK NU YT, ve_alias 4, nl_province 7,
             rtty_number 99); fd is true exactly for the 86 values of the decoder's Field Day
             section table (arrl_section 71, rac_section 14, dx). The decoder's tables stay as
             they are (message-format tables); every one of their values is a row here.
             Who reads it: a received Field Day section gives the states or provinces of its
             maps_to; a received RTTY Roundup STATE gives its row's maps_to; a value whose
             maps_to holds more than one code (MDC, TER) or none gives no single state.
             WstxStrategy's US-state list (#97) offers the us_state rows (50 states and DC) and
             takes a station's state from the exchange through this table; its other sources
             (the log's STATE; FCC/ISED and grid, #101) are #97's and #101's. */
    }
    attribute def ProfileTable {
        doc /* The 35 records of the bundled ContestFile (#98), in this order; this is the
             hand oracle of TC-098-001. Every record: checked "2026-11-09"; keys not named take
             the defaults of ContestProfile. Shorthands: HF6 = [160m, 80m, 40m, 20m, 15m,
             10m]; VHF = [6m, 5m, 4m, 2m, 1.25m, 70cm, 33cm, 23cm, 13cm, 9cm, 6cm, 3cm, 1.25cm,
             6mm, 4mm, 2.5mm, 2mm, 1mm, submm]; FDB = HF6 then VHF; W = weekday, FW =
             full_weekend; a round as day, start-end; FT4 only = modes {count [FT4], as_one
             []}; FT8 only likewise. Texts: T_ARRL "Each contact must include contemporaneous
             direct initiation by both operators making a contact. Initiation of a contact may
             be by either local or remote control. Fully automated contacts are prohibited.";
             T_VHF the same without its last sentence; T_OPEN "OPEN: Two radios and/or any form
             of automation.". Encoding rules: a record encodes the rules for a station outside
             the organiser's area where they differ by side; a multiplier that FT messages
             cannot carry and that would be the score's only multiplier is an extra (Hawaii,
             PACCdigi).

             1 ww_digi "WW Digi"; organiser "CQ Communications and WWROF"; source
             https://ww-digi.com/rules/; log cabrillo WW-DIGI confirmed; FW last month 8,
             0d12:00-1d12:00; text "Last full weekend of August, 1200 UTC Saturday to 1159 UTC
             Sunday"; bands HF6; activity ww_digi; dupe [band]; points "1 +
             floor(km(grid4)/3000)"; multipliers [fields grid_field band]; score "points *
             mults"; forbidden ref IX.12 "A human operator must initiate calling each QSO
             partner. Autonomous systems or robots that emulate this action are prohibited.";
             restrictions [no_alternating_cq, self_spot_forbidden]; notes ["Self-spotting or
             asking to be spotted is not permitted (IX.4)."].
             2 arrl_digi "ARRL Digi"; ARRL; https://contests.arrl.org/ContestRules/Digital-Rules.pdf;
             cabrillo ARRL-DIGI unconfirmed; FW 1 month 6, 0d18:00-2d00:00; "First full weekend
             of June, 1800 UTC Saturday to 2359 UTC Sunday"; window {limit 24, hour, first,
             min_off 60}; bands HF6 then 6m; modes {count digital_no_rtty, as_one all};
             activity arrl_digi; dupe [band]; points "1 + max(1, ceil(km(grid4)/500))"; score
             "points"; forbidden ref OPRG.4 T_ARRL; restrictions [no_multistream,
             no_alternating_cq, self_spot_allowed]; notes ["Busted or NIL QSOs are removed
             with a penalty of their points (not computed)."]; unconfirmed ["log.contest: from
             the contest calendar, not the rules"].
             3 arrl_field_day "ARRL Field Day"; ARRL;
             https://www.arrl.org/files/file/Field-Day/2026/2026-Field-Day-Rules.pdf; cabrillo
             ARRL-FD unconfirmed; FW 4 month 6, 0d18:00-1d21:00; "Fourth full weekend of June,
             1800 UTC Saturday to 2059 UTC Sunday"; bands FDB; modes {count any}; activity
             field_day; dupe [band, mode_class]; points "class{phone: 1, cw: 2, digital: 2}";
             score "points"; extras ["power multiplier x1, x2 or x5", "bonus points"];
             forbidden ref 6.4 T_ARRL; restrictions [no_multistream]; notes ["Entries from
             ARRL/RAC areas and IARU Region 2; DX stations in other regions may be contacted
             and may submit check-logs only (1).", "27 hours when set-up starts no earlier than
             1800 UTC Saturday, otherwise 24 consecutive hours (a note, not tracked).", "Class
             and section are the station's Field Day exchange."]; unconfirmed ["log.contest:
             inferred"].
             4 ft_challenge "FT Challenge"; "RTTYcontesting.com";
             https://www.rttycontesting.com/ft-challenge/rules/; cabrillo FT-CHALLENGE
             confirmed; FW 1 month 12, 0d18:00-2d00:00; "First full weekend of December, 1800
             UTC Saturday to 2359 UTC Sunday"; window {limit 24, hour, first, min_off 30};
             bands [80m, 40m, 20m, 15m, 10m]; activity none; dupe [band]; points "if grid_known
             then 1 + floor(km(grid4)/3000) else 1"; multipliers [fields grid_field band];
             score "points * mults"; forbidden ref 7.13 "Robotic operation is not allowed.
             However, transmissions within a single QSO may be automatically generated.";
             restrictions [no_multistream]; notes ["A missing grid counts as ZZ00: 1 point,
             no multiplier.", "HIGH power entries are check-logs."]; unconfirmed ["score: the
             combined formula is inferred"].
             5 nccc_ft4_sprint "NCCC FT4 Sprint"; "Northern California Contest Club";
             https://www.ncccsprint.com/ft4ns.html; cabrillo NCCC-SPRINT-FT4 unconfirmed; W FRI
             n every months all, 0d01:00-0d01:30; "Every Friday 0100 to 0129 UTC"; bands HF6
             then 6m; FT4 only; activity na_vhf; dupe [band]; points "1"; multipliers [grids
             grid4 band]; score "qsos * mults"; notes ["The runner may log after the caller's
             R report; RR73 is optional.", "100 W at most."]; unconfirmed ["log.contest: not
             in the rules"].
             6 ft4_field_day "FT4 Field Day"; "ft4fd.com"; https://ft4fd.com/; cabrillo
             FT4-FIELD-DAY confirmed; W SAT n 1 months [1, 4, 7, 10], 0d12:00-1d12:00; "First
             weekend of January, April, July and October, 1200 UTC Saturday to 1159 UTC
             Sunday"; window {limit {param hours}, hour, best}; bands HF6; FT4 only; activity
             none; dupe [band, their_grid4]; points "if same_grid4 then 10 else km(grid4,
             6378.16)"; score "points"; restrictions [standard_messages_only]; entry params
             [hours [12, 24] default 24]; notes ["A worked call must appear in two other logs
             (checked by the organiser).", "One transceiver within a 300 m circle."];
             unconfirmed ["schedule.rounds: first weekend read as the first Saturday",
             "points: rounding of the distance"].
             7 kansas_qp_ft "Kansas QSO Party (FT)"; "Kansas QSO Party";
             https://ksqsoparty.org/rules/KSQPRules2026.pdf; email null unconfirmed; dates
             [2026-08-29] 0d14:00-1d02:00 and dates [2026-08-30] 0d14:00-0d20:00; "Last weekend
             of August: Saturday 1400 to Sunday 0159 UTC and Sunday 1400 to 1959 UTC"; bands
             [80m, 40m, 20m, 15m, 10m, 6m]; modes {count [FT8, FT4], as_one []}; activity none;
             rcvd [grid4]; dupe [band, mode]; points "1"; score "qsos"; notes ["A Kansas
             station's county also separates dupes; FT messages cannot carry it."];
             unconfirmed ["schedule: only the 2026 dates were read"].
             8 vermont_qp_ft "Vermont QSO Party (FT)"; "Radio Amateurs of Northern Vermont";
             https://www.ranv.org/vtqso.html; cabrillo null unconfirmed; dates [2027-02-06]
             0d00:00-2d00:00; "First full weekend of February, 0000 UTC Saturday to 2359 UTC
             Sunday"; bands [30m, 17m, 12m]; activity none; dupe [band, mode_class]; points
             "class{digital: 2, cw: 3, phone: 1}"; multipliers [grids grid4 contest]; score
             "points * floor(m.grids/3)"; extras ["power factor 1.0, 1.5 or 2.0", "out-of-state
             stations count at most 5 Vermont grids"]; notes ["FT modes count only on the WARC
             bands."]; unconfirmed ["schedule: only the 2027 date was read", "multipliers:
             grid scope", "log.format: not read"].
             9 hawaii_qp "Hawaii QSO Party"; "Hawaii QSO Party";
             https://www.hawaiiqsoparty.org/rules-page/; cabrillo null unconfirmed; dates
             [2026-08-21] 0d16:00-2d04:00; "Late August, Friday 1600 UTC to Sunday 0359 UTC";
             bands HF6 then 6m; modes {count any}; activity none; dupe [band, mode_class];
             points "class{digital: 3, else: 0}"; score "points"; extras ["district, state and
             province multipliers (FT stations send a grid instead)"]; unconfirmed ["points:
             phone and CW values", "dupe: the rules contradict themselves", "schedule: only
             the 2026 date was read", "log.format: not read"].
             10 arrl_vhf_jan "ARRL January VHF"; ARRL;
             https://contests.arrl.org/ContestRules/JanJunSep-VHF-Rules.pdf; cabrillo
             ARRL-VHF-JAN unconfirmed; asked, 0d19:00-2d04:00; "Third or fourth full weekend of
             January as announced (enter the date), 1900 UTC Saturday to 0359 UTC Monday";
             bands VHF; modes {count any}; activity na_vhf; dupe [band, my_grid4, their_grid4]
             (once per band per pair of grids, so a rover on either side counts again from a
             new grid); points "band{6m: 1, 2m: 1, 1.25m: 2, 70cm: 2, 33cm: 4, 23cm: 4, else:
             8}"; multipliers [grids grid4 band; activated my_grid4 contest only
             "param(rover)"]; score "points * mults"; forbidden ref OPRG.4 T_VHF; restrictions
             [no_multistream, self_spot_allowed]; entry {workable "my_in(W_VE) or
             their_in(W_VE)", params [rover bool default false]}; notes ["Stations may be
             contacted once per band from any specific grid square (2.2)."]; unconfirmed
             ["sets.W_VE: ARRL's exact W/VE definition"].
             11 arrl_vhf_jun "ARRL June VHF": as 10 with cabrillo ARRL-VHF-JUN, FW 2 month 6,
             0d18:00-2d03:00, "Second full weekend of June, 1800 UTC Saturday to 0259 UTC
             Monday", points "band{6m: 1, 2m: 1, 1.25m: 2, 70cm: 2, 33cm: 3, 23cm: 3, else:
             4}". 12 arrl_vhf_sep "ARRL September VHF": as 11 with ARRL-VHF-SEP, month 9,
             "Second full weekend of September, 1800 UTC Saturday to 0259 UTC Monday".
             13 arrl_222_up "ARRL 222 MHz and Up"; ARRL;
             https://contests.arrl.org/ContestRules/222-MHz-Rules.pdf; cabrillo ARRL-222
             unconfirmed; FW 1 month 8, 0d18:00-1d18:00; "First full weekend of August, 1800
             UTC Saturday to 1759 UTC Sunday"; bands [1.25m, 70cm, 33cm, 23cm, 13cm, 9cm, 6cm,
             3cm, 1.25cm, 6mm, 4mm, 2.5mm, 2mm, 1mm]; modes {count any}; activity eu_vhf; sent
             [grid6]; rcvd [grid6]; dupe [band, my_grid4, their_grid4] keep best; points
             "band{1.25m: 2, 70cm: 1, 33cm: 4, 23cm: 2, 13cm: 6, 9cm: 10, 6cm: 10, 3cm: 6,
             else: 20} * (if same_grid6 then 1 else km(grid6))"; score "points"; forbidden ref
             OPRG.4 T_ARRL; unconfirmed ["exchange.activity: EU VHF inferred", "points:
             distance rounding", "restrictions: self-spotting (OPRG.8.1 against PROH.4)"].
             14 cq_ww_vhf "CQ WW VHF (digital)"; "CQ Communications";
             https://cqww-vhf.com/rules/2026_cq_ww_vhf_rules.pdf; cabrillo CQ-VHF unconfirmed;
             FW 3 month 7, 0d14:00-1d14:00; "Third full weekend of July (the digital weekend),
             1400 UTC Saturday to 1359 UTC Sunday"; bands [6m, 2m]; modes {count digital};
             activity na_vhf; dupe [band, their_grid4]; points "band{6m: 1, 2m: 2}";
             multipliers [grids grid4 band]; score "points * mults"; restrictions
             [self_spot_allowed]; notes ["Signal reports are not required."]; unconfirmed
             ["schedule: only the 2026 dates were read", "log.contest: not in the rules"].
             15 iaru_50_mgm "IARU R1 50 MHz MGM"; "IARU Region 1";
             https://www.iaru-r1.org/wp-content/uploads/2026/02/VHF_Handbook_V10_03_final.pdf;
             edi null unconfirmed; W SAT n 3 months [4], 0d14:00-1d14:00; "Third Saturday of
             April, 1400 UTC Saturday to 1400 UTC Sunday"; bands [6m]; modes {count digital};
             activity none; dupe [band]; points "if same_grid4 then 50 else floor(km(grid4,
             iaru)) + 1"; multipliers [squares grid4 band]; score "points * mults";
             restrictions [self_spot_limited, single_signal]; notes ["Standard FT8 messages
             with report and 4-character locator; no serial number.", "6H section: 6 hours in
             at most two periods with a pause of more than 2 hours (a note, not tracked).",
             "Self-spots: only when first soliciting QSOs on a new frequency, then at most every
             10 minutes."]. 16 iaru_70_mgm "IARU R1 70 MHz MGM": as 15 with W SAT n 3 months
             [5], "Third Saturday of May, 1400 UTC Saturday to 1400 UTC Sunday", bands [4m].
             17 ft8_activity "FT8 Activity"; "FT8 Activity (ft8activity.eu)";
             https://ft8activity.eu/rules/; adif null unconfirmed; rounds W WED n 1 months all
             bands [2m], W WED n 2 months all bands [70cm], W WED n 3 months all bands [23cm],
             each 0d17:00-0d21:00; "Each month: first Wednesday 2 m, second Wednesday 70 cm,
             third Wednesday 23 cm, 1700 to 2059 UTC"; series {best 8, of 12, per band,
             normalise none}; bands [2m, 70cm, 23cm]; activity none; rcvd [grid4]; dupe
             [round]; points "1"; multipliers [locators grid4 round]; score "points * mults";
             restrictions [standard_messages_only, no_multistream, self_spot_forbidden]; notes
             ["ON4KST is for skeds only."].
             18 nac_nrrl "Nordic Activity Contest (NRRL)"; NRRL;
             https://ladxg.no/content/nrrl_nac_logrobot/nac_rules.asp; edi null unconfirmed;
             tz Europe/Oslo; rounds W TUE n 1 [2m], W TUE n 2 [70cm], W TUE n 3 [23cm], W TUE n
             4 [13cm, 9cm, 6cm, 3cm, 1.25cm, 6mm], W THU n 2 [6m], W THU n 3 [4m], months all,
             each 0d19:00-0d23:00; "Tuesdays: 1st 2 m, 2nd 70 cm, 3rd 23 cm, 4th 13 cm and up;
             Thursdays: 2nd 6 m, 3rd 4 m; 1900 to 2259 Norwegian time"; series {best 9, of 12,
             per band, normalise none}; bands [6m, 4m, 2m, 70cm, 23cm, 13cm, 9cm, 6cm, 3cm,
             1.25cm, 6mm]; modes {count any}; activity eu_vhf; sent [rst, grid6]; rcvd [grid6];
             dupe [round]; points "km(grid6) * band{13cm: 2, 9cm: 3, 6cm: 4, 3cm: 5, 1.25cm: 6,
             6mm: 7, else: 1}"; multipliers [squares grid4 round]; score "points + 500 *
             m.squares"; forbidden ref 4 "For MGM, fully automatic QSO software is not
             permitted; the operator must personally carry out all parts of the contact
             exchange."; entry {eligible "my_in(LA)"}; notes ["The SSA, SRAL and EDR versions
             differ; this is the NRRL version."]; unconfirmed ["points: rounding and the
             same-square value", "exchange.activity: EU VHF inferred"].
             19 rsgb_ft8_ac "RSGB FT8 Activity Contests"; RSGB;
             https://www.rsgbcc.org/cgi-bin/contest_rules.pl?year=2026&contest=2m4hmgmac; adif
             null unconfirmed; rounds W WED n 1 months all bands [2m], W WED n 2 months all
             bands [70cm], each 0d17:00-0d21:00; "First Wednesday 2 m, second Wednesday 70 cm,
             1700 to 2059 UTC (2-hour section 1900 to 2059)"; series {best 8, of 12, per band,
             normalise rank}; bands [2m, 70cm]; FT8 only; activity none; dupe [round]; points
             "if same_grid4 then 50 else ceil(km(grid4))"; multipliers [squares grid4 round];
             score "points + 500 * m.squares"; restrictions [single_signal, self_spot_limited,
             standard_messages_only]; notes ["Sections Open, Restricted and Low Power; for the
             2-hour section enter 1900 to 2100 as the period."]; unconfirmed ["points:
             distance rounding for MGM"].
             20 ari_ft8_activity "ARI FT8 Activity"; ARI;
             https://contest.ari.it/rules/regolamentoiacft8_2026.pdf; adif null unconfirmed;
             rounds W WED n 1 months [4..10] bands [2m] 0d17:00-0d20:00, W WED n 1 months [11,
             12, 1, 2, 3] bands [2m] 0d18:00-0d21:00, W WED n 2 months [4..10] bands [70cm]
             0d17:00-0d20:00, W WED n 2 months [11, 12, 1, 2, 3] bands [70cm] 0d18:00-0d21:00;
             "First Wednesday 2 m, second Wednesday 70 cm; 1700 to 1959 UTC April to October,
             1800 to 2059 UTC November to March"; series {best 12, of 12, per band, normalise
             none, annual sum_times_rounds}; bands [2m, 70cm]; FT8 only; activity none; dupe
             [round]; points "1"; multipliers [squares grid4 round]; score "points * mults";
             restrictions [standard_messages_only, no_multistream]; entry {eligible
             "my_in(I)"}; notes ["A log must hold at least one QSO with an Italian station."];
             unconfirmed ["dupe: the rules state no dupe rule"].
             21 wia_ross_hull "WIA Ross Hull Memorial (digital)"; WIA;
             https://www.wia.org.au/members/contests/rosshull; cabrillo null unconfirmed; date
             01-01, 0d00:00-31d00:00; "1 to 31 January; the best 7 (or 2) UTC days count";
             window {limit {param days}, utc_day, best}; bands VHF; modes {count digital};
             activity eu_vhf; dupe [band, mode_class, utc_day]; points "ceil(km(grid6)/100) *
             band{6m: 2, 2m: 3, 70cm: 5, 23cm: 8, else: 10}"; score "points"; entry params [days
             [7, 2] default 7]; unconfirmed ["log.format: not read"].
             22 rsgb_ft4_series "RSGB 80 m FT4 Club Championship"; RSGB;
             https://www.rsgbcc.org/hf/rules/2026/r80m_ft4.shtml; cabrillo null unconfirmed;
             rounds dates [2026-01-19, 2026-02-23, 2026-03-16, 2026-10-26, 2026-11-16,
             2026-12-14] 0d20:00-0d22:00 and dates [2026-04-27, 2026-05-18, 2026-06-15,
             2026-07-27, 2026-08-17, 2026-09-28] 0d19:00-0d21:00; "Twelve Mondays a year (RSGB
             calendar), 2000 to 2159 UTC in winter, 1900 to 2059 UTC in summer"; series {best 9,
             of 12, per contest, normalise rank}; bands [80m]; FT4 only; activity none; dupe
             [band]; points "1"; multipliers [dxcc dxcc contest]; score "points * mults";
             automation silent by_section {OPEN: permitted T_OPEN}; restrictions
             [standard_messages_only]; entry params [section [OPEN, RESTRICTED] default
             RESTRICTED]; notes ["Power 100 W or 10 W (a note)."]; unconfirmed ["bands: the
             research listed 80 to 10 m; the rules page is the 80 m championship"].
             23 rsgb_ft4_iad "RSGB FT4 International Activity Day"; RSGB;
             https://www.rsgbcc.org/hf/rules/2026/rallband_ft4.shtml; cabrillo null
             unconfirmed; dates [2026-04-11] 0d12:00-1d12:00; "One Saturday in April (2026: 11
             April), 1200 UTC Saturday to 1159 UTC Sunday"; window {limit {param hours}, hour,
             first, min_off 60}; bands HF6; FT4 only; activity none; dupe [band]; points "if
             same_continent then 1 else 3"; multipliers [dxcc dxcc band]; score "points *
             mults"; automation silent by_section {OPEN: permitted T_OPEN}; restrictions
             [standard_messages_only]; entry params [section [OPEN, RESTRICTED] default
             RESTRICTED; hours [12, 24] default 24]; unconfirmed ["multipliers: per band or per
             contest", "schedule: only the 2026 date was read", "log.format: not read"].
             24 rsgb_eclipse_ft8 "RSGB Eclipse FT8"; RSGB;
             https://www.rsgbcc.org/hf/rules/2026/r_eclipse_ft8.shtml; cabrillo null
             unconfirmed; dates [2026-08-12] 0d16:30-0d19:30; "12 August 2026 (one-off), 1630
             to 1929 UTC"; bands [40m]; FT8 only; activity none; dupe []; points "if
             same_continent then 1 else 3"; multipliers [dxcc dxcc contest]; score "points *
             mults"; automation permitted "The rules permit automatic operation.";
             unconfirmed ["source: the rules page was not read in full", "automation.text",
             "log.format: not read"].
             25 darc_ft4 "DARC FT4 Contest"; DARC; https://www.darc.de/; cabrillo null
             unconfirmed; W TUE n 2 months [2, 5, 8, 11], 0d19:00-0d20:30; "Second Tuesday of
             February, May, August and November, 1900 to 2029 UTC"; bands [80m, 40m]; FT4 only;
             activity none; dupe [band]; points "1"; multipliers [prefixes wpx band]; score
             "points * mults"; restrictions [no_multistream, self_spot_forbidden]; notes
             ["Power LP or QRP (a note)."]; unconfirmed ["source: the address of the rules
             page", "multipliers: the prefix definition read as WPX", "automation: not read",
             "restrictions: from DARC's general rules"].
             26 paccdigi "PACCdigi"; VERON; https://www.veron.nl/; cabrillo null unconfirmed;
             FW 3 month 4, 0d12:00-1d12:00; "Third full weekend of April, 1200 UTC Saturday to
             1159 UTC Sunday"; window {limit 18, hour, first, min_off 60}; bands HF6; modes
             {count [RTTY, FT8, FT4], as_one [[FT8, FT4]]}; activity rtty; dupe [band,
             mode_group]; points "if their_in(PA) then 3 else 1"; score "points"; extras
             ["province multipliers (PA stations send their province, which FT messages cannot
             carry)"]; forbidden "The use of a QSO robot is strictly prohibited. The operator
             must operate the equipment during the QSO."; restrictions [no_multistream,
             self_spot_forbidden]; exchange unsendable_for "my_in(PA)"; notes ["A station may
             be logged at most 10 times per band."]; unconfirmed ["source: the address of the
             rules page", "schedule: only the 2026 date was read; 2027's time differs",
             "log.format: not read"].
             27 sral_ft8 "SRAL FT8 (SM series)"; SRAL;
             https://www.sral.fi/wp-content/uploads/2025/12/FT8-kilpailujen-SM-sarja-saannot-2026.pdf;
             cabrillo null unconfirmed; tz Europe/Helsinki; W WED n 2 months all,
             0d18:00-0d19:00; "Second Wednesday of each month, 1800 to 1859 Finnish time";
             series {best 9, of 12, per contest, normalise winner_1000}; bands [80m, 40m]; FT8
             only; activity na_vhf; dupe [band]; points "2"; multipliers [squares grid4 band];
             score "points * mults"; restrictions [single_signal]; entry {eligible
             "my_in(OH)", workable "their_in(OH)"}; notes ["1 point instead of 2 with an
             exchange error (checked by the organiser)."].
             28 sarl_hf_digi "SARL HF Digital"; SARL; https://mysarl.org.za/contest-resources/;
             cabrillo SARL-HF-DIGI unconfirmed; W SUN n 2 months [8], 0d13:00-0d16:00; "Second
             Sunday of August, 1300 to 1559 UTC"; bands [80m, 40m, 20m]; activity eu_vhf cq
             SARL; dupe [band]; points "1"; multipliers [areas call_area:SARL band; triples
             call contest requires all_bands]; score "qsos + 2 * m.areas + 2 * m.triples";
             restrictions [self_spot_forbidden]; notes ["The EU VHF contest message with the
             contest name SARL (SARL Contest Manual 2027, 5.2)."].
             29 africa_ft4 "Africa FT4 DX Contest"; SARL; https://mysarl.org.za/contest-resources/;
             adif null; W SAT n 2 months [4, 9], 0d15:00-0d18:00; "Second Saturday of April and
             September, 1500 to 1759 UTC"; bands [80m, 40m, 20m]; FT4 only; activity none; dupe
             [band]; points "if my_cont(AF) then (if same_dxcc then 4 else if their_cont(AF)
             then 6 else 1) else (if their_cont(AF) then 4 else 0)"; points_cap {when
             "my_cont(AF) and same_dxcc", share [1, 3]}; score "points"; restrictions
             [standard_messages_only, no_multistream, single_signal, self_spot_allowed]; notes
             ["Power at most 100 W."].
             30 wia_australia_day "WIA Australia Day (DIGI)"; WIA;
             https://www.wia.org.au/members/contests/australiaday/; cabrillo "WIA-AUSTRALIA
             DAY" confirmed; date 01-26, -1d22:00-0d10:00; "26 January, 2200 UTC on 25 January
             to 0959 UTC"; bands HF6; activity none; dupe [band, mode]; points "if not
             (my_in(VK) or their_in(VK)) then 0 else (if same_grid4 then 1 else km(grid4))";
             score "points"; forbidden "Fully automated operation is not permitted; however,
             computers can be used for logging or CW reception and/or keying."; unconfirmed
             ["points: distance rounding", "modes: FT8 and FT4 counted as one mode"].
             31 zl_sprint_ft4 "ZL FT4 Sprint"; NZART;
             https://nzart.org.nz/activities/contests/sprints/; email null unconfirmed; tz
             Pacific/Auckland; W TUE n every months [4, 8], 0d21:00-0d21:30; "Every Tuesday of
             April and August, 2100 to 2129 New Zealand time"; bands [80m]; FT4 only; activity
             ww_digi cq ZLS; dupe [mode]; points "1"; score "qsos"; unconfirmed ["schedule: the
             page says 0900 UTC and 8 pm regardless of daylight saving"].
             32 helvetia "Helvetia Contest"; USKA; https://www.uska.ch/; cabrillo null
             unconfirmed; FW last month 4, 0d13:00-1d13:00; "Last full weekend of April, 1300
             UTC Saturday to 1259 UTC Sunday"; bands HF6; modes {count any}; activity rtty;
             dupe [band, mode_class]; points "if their_in(HB) then 10 else if same_continent
             then 1 else 3"; multipliers [dxcc dxcc band]; score "points * mults"; extras
             ["canton multipliers (FT messages cannot carry the canton, #100)"]; exchange
             unsendable_for "my_in(HB)"; notes ["Per band: CW, SSB and one digital mode."];
             unconfirmed ["source: the rules PDF was not readable", "multipliers", "automation",
             "restrictions", "points for HB stations"].
             33 pro_digi "PRO Digi Contest"; "PRO Radio Contest Club";
             https://proradiocontestclub.com/PDC%20Rules.html; cabrillo PDC confirmed; FW 3
             month 1, 0d12:00-1d12:00; "Third full weekend of January, 1200 UTC Saturday to
             1159 UTC Sunday"; bands [80m, 40m, 20m, 15m, 10m]; modes {count [PSK63, FT4,
             RTTY], as_one []}; activity rtty; rcvd [rst, serial, member_flag]; dupe [band,
             mode]; points "(if same_dxcc then 1 else 2) + (if my_member and their_member then 6
             else if their_member then 2 else 0)"; multipliers [prefixes wpx band only "not
             same_dxcc"]; score "points * mults"; restrictions [min_band_stay:5]; entry params
             [member bool default false]; members PRO_DIGI; notes ["A member's M suffix cannot
             be sent in FT messages; member points come from the member list.", "1 percent
             penalty per band-stay violation (not computed)."].
             34 bucharest_digital "Bucharest Digital Contest"; "yo3test201x";
             https://yo3test201x.blogspot.com/; cabrillo BUCURESTI-DIGITAL confirmed; W MON n 3
             months [3], 0d18:00-0d21:00; "Third Monday of March, 1800 to 2059 UTC"; bands
             [80m, 40m]; FT4 only; activity rtty; dupe [band]; points "1"; score "qsos";
             restrictions [single_signal]; notes ["RTTY Roundup exchange with DX: report and
             serial."]; unconfirmed ["organiser: only the blog's name was read"].
             35 ybdxpi_ft8 "YB DX Contest FT8"; YBDXPI; https://contest.ybdxpi.net/ft8/rules/;
             cabrillo null unconfirmed; dates [2026-11-07] 0d00:00-2d00:00; "Early November
             (2026: 7 and 8 November), 0000 UTC Saturday to 2359 UTC Sunday"; bands HF6; FT8
             only; activity none; rcvd [grid4]; dupe [band]; points "if their_member then 5
             else if same_dxcc then 1 else if same_continent then 2 else 3"; multipliers
             [prefixes wpx band; dxcc dxcc band]; score "points * mults"; restrictions
             [single_signal]; members YBDXPI; unconfirmed ["schedule: dates vary by year",
             "members: the source of the member list", "log.format: not read"].
             Silent records (every record above without a clause) carry the default
             automation. A rule source that does not state something is in unconfirmed. */
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
             null), params (the record's entry params), eligible (true, false for my station,
             or null without a rule), exchange_sendable (false when ExchangeRule.unsendable_for
             holds for my station or the activity is one the station cannot be set to), notes,
             unconfirmed and period (null when asked or no date is left, else {start, end,
             band}: ScheduleRule at the time of the request, "YYYY-MM-DDTHH:MMZ", end
             exclusive, band null unless the round names one band). It changes nothing; the
             browser reads it when the period prompt opens and once per connection while a
             contest is in force (for its name), never at a plain page load or reconnect and
             never on a timer. */
    }
    attribute def ContestSelection {
        attribute periodDaysMax : Integer = 31;
        doc /* The optional key contest of WstxStrategy::StrategyConfiguration on PUT /strategy and in
             the GET /strategy snapshot, present only while one is selected: {profile (a profile
             id), start, end (real instants "YYYY-MM-DDTHH:MMZ", end exclusive, start < end, at most
             31 days apart), operation "sp" or "run", repetitions (x of WstxStrategy::LeaveRule,
             1..20, default 2), quiet_minutes (WstxStrategy::QuietTime, 1..120, default 10) and,
             #98, entry (optional: {NAME: value} for the record's entry params, each one of its
             choices, true or false for "bool"; an absent param takes its default; the snapshot
             shows all of them)}. After #97 lands, operation, repetitions and quiet_minutes go
             (ContestStrategyInterface) and the other keys stay.
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
    attribute def ContestStrategyInterface {
        doc /* #98 with #97 (strategy redesign), valid whichever lands first.
             #98 supplies, per contest record: the rule-layer ContestVerdict (callable, or one
             reason: ignored, greyed, band, mode, log, not workable, dupe, callsign guard, not a
             CQ, no score); ContestValue and the tally; the record's activity, CQ word, clause of
             the selected section, period and entry params; the Subdivisions table.
             #97 supplies: the strategy's bands, the operator filters (country, US state, CQ
             target lists) applied after the contest verdict to callable records only, never
             re-admitting one; leaving, Tx frequency, busy pause, CQ when idle, retry pause;
             callers_first.
             Selection: before #97 ContestSelection as above. After #97 a contest strategy is
             active and the selection is {profile, start, end, entry}: entry stays on the
             selection in station memory in both orders (it describes this entry: section,
             hours, rover, member), never saved with the strategy; S&P/Run, repetitions and
             quiet_minutes go (#97 Q1).
             Callers first: #97's callers_first switch governs a contest strategy; on, callers
             of my call rank first (ContestValueOrder); off, they rank by value among the
             others. Before #97 it is always on. A dupe or not-workable caller has no rank
             either way.
             CQ: every CQ a contest strategy sends, #63's Run or #97's CQ when idle, carries the
             record's CQ word (ContestDirective); a contest run waits activity, band, mode,
             exchange and outside_period (ContestRun) whichever operation calls CQ. */
    }
    attribute def ContestLog {
        doc /* The log read for a contest (#98 D12): the contacts whose QSO_DATE and TIME_ON start
             lies in [start, end) only, with a band of the record (of the round for a round
             with its own bands) and a mode the record counts (ModeRule). Per contact it reads
             CALL, GRIDSQUARE (up to 6 characters), the effective band, MODE and SUBMODE, the
             start, MY_GRIDSQUARE (else the station locator), STX, SRX, SRX_STRING, STATE, CLASS,
             ARRL_SECT, RST_SENT and RST_RCVD; a record without a band (logged without a
             confirmed CAT dial, WstxContact::DirectLog) counts for nothing. Entity,
             continent, zones and WPX prefix come from cty.dat and WpxPrefix at evaluation.
             In time order: a dupe by DupeRule counts nothing; ScoredWindow decides which of
             the others score; each scoring QSO adds its points (PointsRule; points_cap over
             the period) and its multiplier keys (MultiplierRule). The tally: qsos (scoring
             QSOs), multipliers (mults), points and score (ScoreRule); extras are not
             computed. Unreadable: no claim, nothing callable. A contest evaluation reads it on
             a blocking thread, about one read per publication; it scans the records without
             copying those outside the period. */
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
        doc /* #98 (CL-098-05, D13; operator Q1 and Q4 on #98). The value of a decoded station is
             its projected score gain: S(Z + q) - S(Z), S the record's score expression, q the
             hypothetical QSO with this station now (its points by PointsRule, the multiplier
             keys it adds, one QSO, or nothing when it is a dupe or would not score by
             ScoredWindow), Z the projected end state of the period: each total X of the tally
             (qsos, points, each multiplier set's size) becomes X + G(X) / W * T, where e is
             the minutes from the period's start to now, W = max(15, min(60, e)), G(X) is what
             the QSOs whose start lies in (now - min(60, e), now] added to X (a QSO exactly 60
             minutes before now is outside), and T the minutes from now to the selection's end
             (for a window first, at most the operating time it has left; 0 once it is used
             up). For points * mults this is p * M + m * P + p * m with P and M projected.
             Without a known locator the distance is taken, for the value only, to the centre
             of the sender's cty.dat entity (as WstxStrategy::ValueOrder's distance); the
             logged score keeps the rules' value. One evaluator call per callable record per
             publication. */
    }
    attribute def ContestVerdict {
        doc /* WstxStrategy::Verdict with a contest in force, one per decoded record with a resolved
             sender that is standard, or a Field Day exchange (type field_day) to a call, in this
             order of tests: ignored (IgnoreLists, as a strategy); greyed
             (DirectedCqRule with ContestDirective); "my own message"; "band unknown"; "band not
             in the contest"; "mode not in the contest" (#98: the station's mode is not counted
             by ModeRule); "log unreadable"; "not workable" (#98: EntryRule workable is false
             for this sender, also a caller of my call: not answered, operator Q3); "dupe"
             (DupeRule for the station band and mode, mode class Digital, my locator the
             station's; rank null, dupe true, also when it calls my call: operator #63
             "non-dupe", the one difference from WstxStrategy D5); a caller of my call
             (CallerOfMyCall, also a grid or Field Day exchange to it); else the callsign guard
             (SaneCall; a /R rover passes where their_grid4 is a dupe dimension); else "not a
             CQ": a CQ or an RR73/73 to someone else counts as calling, in every contest; else
             "no score" (#98: value 0, ContestValue; not for a caller of my call, who is
             answered, operator Q3). So the callable records have a rank by ContestValueOrder;
             every other has rank null. These are the contest's rules: the operator's filters
             of WstxStrategy (#97) are applied after them to the callable records only, and can
             remove a record, never re-admit one. The reply's verdicts carry dupe,
             new_multiplier (the record adds a key to any multiplier set; false without the
             value its kind needs), points (PointsRule; null when not known) and value (#98:
             ContestValue rounded half up; null without a rank).
             POST /strategy/evaluate with strategy null and a contest in force returns these, with
             strategy the profile's name and contest the tally {qsos, multipliers, points, score}
             (null when the log is unreadable); explain false lists the ranked, the greyed and the
             dupes. A draft strategy still previews the draft. why: "calls my call", "new
             multiplier", "<n> points", "value <v>" joined by " \· ", or the reason above. */
    }
    attribute def ContestValueOrder {
        doc /* Smaller first: callers of my call before the others while callers first is on
             (WstxStrategy D5; only callers with a rank, never a dupe or not workable; #97's
             callers_first switch governs, ContestStrategyInterface); then the larger
             ContestValue (#98, replacing "a new multiplier, then more QSO points"); then the
             strongest SNR (unknown last); then, for an exact tie only, the lower audio
             frequency, then the call (strategydef Q3, Q9: decode order is never a ranking).
             Replaces WSJT-X's first decoded (operator #63). */
    }
    attribute def ContestPrompt {
        doc /* The Contest button of the strategy element opens a modal dialog with its own HALT (the
             top-bar HALT's action, as WstxStrategy::StrategyEditor); receive keeps running. It reads
             GET /strategy/contests once at opening, so the pre-fill is current. It offers the
             profiles in file order; Start and End (UTC, to the minute): the selection in force when it matches, else
             the profile's period, empty when asked or no date is left; the schedule in words; the operation S&P or
             Run (S&P the default) and "Repetitions before leaving" (default 2) and "Quiet time
             (minutes)" (default 10) until #97 replaces them (ContestStrategyInterface); #98:
             one control per entry param (its choices, its default, or the value in force),
             the organiser, source and the date the rules were checked, the CQ word, "You are
             not eligible" when eligible is false, "The station cannot send this contest's
             exchange yet" when exchange_sendable is false, the series and window in words, the
             extras as "not computed", and the unconfirmed facts; the automation text of the
             clause in force for the chosen section and the notes. Whether it transmits is
             the Auto toggle's (WstxStrategy::AutoToggle): a forbidden clause asks its
             confirmation when Auto is switched on, not at Start. When the profile's
             activity differs from the station's, one line says so. Start with an empty period
             asks for it and sends nothing; else one PUT /strategy with the selection (with
             entry). Cancel
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
             These waits and the CQ word hold for whichever operation calls CQ: #63's run below
             or, after #97, a contest strategy with CQ when idle on (ContestStrategyInterface).
             sp: on each fresh complete publication the list is ContestVerdict with a rank, one per
             call, not completed in this run on this band and mode nor given up; the first is selected
             as a strategy run selects, not in its QuietTime. Leaving: WstxStrategy::LeaveRule with
             the contest's repetitions and quiet_minutes; no skip (WstxStrategy D6).
             run: while waiting and no reason it decides the slot (FreeTxSlot, no called station;
             with Hold Tx on the held Tx, no decision, WstxStrategy D16) and
             sends enable_tx with no partner, which calls CQ with the activity's Tx6 carrying
             the contest's CQ word (ContestDirective); state
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
             current activity (na_vhf, arrl_digi and eu_vhf TEST, ww_digi WW, field_day FD, rtty RU) is
             answerable, also with my continent unknown. So it is not greyed, a selection needs no
             directive_confirmed, and a word outside its activity keeps the warning. It depends on
             the activity alone, not on a selected contest strategy (D2).
             #98 (D14, operator Q2 on #98): while a contest is selected and the station's
             activity is the record's, the record's CQ word is answerable in the same way, and
             every CQ the station sends (Tx6, by the operator, by #63's Run or by #97's CQ when
             idle) carries that word instead of the activity's; without a contest, or in
             another activity, only the activity's word as before. */
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
    dependency encodingClause from ContestEncoding to WstxRequirements::'CL-098-02';
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
    dependency interfaceClause from ContestStrategyInterface to WstxRequirements::'CL-098-05';
    dependency interfaceSelection from ContestStrategyInterface to WstxRequirements::'CL-098-06';
    dependency selectionData from ContestSelection to WstxRequirements::'CL-098-06';
    dependency promptData from ContestPrompt to WstxRequirements::'CL-098-06';
    dependency httpData from ContestHttp to WstxRequirements::'CL-098-06';
    dependency runData from ContestRun to WstxRequirements::'CL-098-06';
}

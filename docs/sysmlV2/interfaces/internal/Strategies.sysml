package WstxStrategies {
    private import WstxQsoControl::Activity;
    private import ScalarValues::*;
    private import WstxRankingControl::RankingKeys;
    private import WstxRankingControl::RankingRules;
    private import ModelNotes::FollowsSource;

    doc /* What a strategy and a contest are; what the supervisor commands the
         operating function and what operating answers; and what operating gives
         ranking, Auto and the contact of the active strategy.
         A strategy is a named set of rules: the rules by which ranking orders the
         decoded stations, the rules Auto executes, and for a contest the facts of its
         official rules. It decides and does nothing itself. */

    enum def StrategyClass {
        doc /* strategy: the ranking rules are the strategy's own.
             contest: the ranking rules come from a contest, with the strategy's bands
             and its country, US state and CQ target lists on top. */
        enum strategy;
        enum contest;
    }
    enum def LeaveMode {
        doc /* How a station that does not answer is left.
             calls: after a number of calls.
             until_logged: when it has not been decoded for a number of minutes.
             contest: after a number of Tx changes, while it does not hear the station
             or is not the most valuable one. */
        enum calls;
        enum until_logged;
        enum contest;
    }
    attribute def AutoKeys {
        doc /* The rules of one strategy that Auto executes. Every strategy of either
             class has every one of them. */
        attribute leaveMode : LeaveMode;
        attribute leaveCalls : Integer[0..1] {
            doc /* With calls: the calls without an answer, 1 to 20. */ }
        attribute leaveCallsHeard : Integer[0..1] {
            doc /* With calls: the calls while the station is heard there, from
                 leaveCalls to 40. */ }
        attribute goneMinutes : Integer[0..1] {
            doc /* With until_logged: 1 to 60. */ }
        attribute txChanges : Integer[0..1] {
            doc /* With contest: 1 to 20. */ }
        attribute moveEveryHeard : Integer {
            doc /* How often the transmit frequency moves while the called station hears
                 the station: 0 never, 1 at every call, n at every n-th call, up to
                 20. */ }
        attribute moveEveryNotHeard : Integer {
            doc /* The same while it reports and does not hear the station. */ }
        attribute moveEveryNoReports : Integer {
            doc /* The same while it does not report, or that is unknown. */ }
        attribute cqWhenIdle : Boolean {
            doc /* CQ is called when nothing can be called. */ }
        attribute cqWaitPeriods : Integer {
            doc /* The periods with nothing to call before that CQ: 1 to 20. It is
                 held also while cqWhenIdle is off. */ }
        attribute retryMinutes : Integer {
            doc /* The pause before a station that was left is called again: 1 to
                 120. */ }
        attribute cqQuietPeriods : Integer {
            doc /* The periods without a CQ after a CQ that nobody answered: 0 to 40.
                 It is held also while cqWhenIdle is off. */ }
    }
    attribute def Strategy {
        doc /* One strategy. Every strategy has every setting; the class says where its
             ranking rules come from. */
        attribute name : String {
            doc /* 1 to 32 printable ASCII characters, without a space at either end.
                 Among the saved strategies a name stands once, without regard to letter
                 case, and is not the name of a built-in one. */ }
        attribute strategyClass : StrategyClass;
        attribute ranking : RankingKeys;
        attribute contest : String[0..1] {
            doc /* For class contest: the id of its contest in ContestTable. Absent for
                 class strategy. */ }
        attribute auto : AutoKeys;
        attribute alert : AlertSound[0..1] {
            doc /* The sound of the strategy's alerts (WstxAlert::AlertRule); absent: Off,
                 the strategy alerts not. */ }
    }
    enum def AlertSound {
        doc /* The sounds of the station's alerts, distinct from one another. */
        enum oldPhone;
        enum bell;
        enum chime;
        enum beep;
    }
    attribute def BuiltinStrategies {
        doc /* The strategies the station offers beside the saved ones. They cannot be
             changed. They are listed in this order.
             Every built-in of class strategy has, unless its line says otherwise: every
             band; region all; no minimum SNR; worked since all; Treat 73 as CQ on;
             empty country, US state and CQ target lists; calling stations answered;
             leaving after 4 calls and after 8 while heard; the transmit frequency moved
             never, at every call and at every 2nd call for the three cases in the order
             of AutoKeys; no CQ when idle; a CQ wait of 2 periods; a
             retry pause of 10 minutes; a CQ pause of 8 periods; no alert.
             DXCC all: new dxcc per band_mode, not_confirmed; order most_wanted, snr;
             leaving until_logged after 10 minutes.
             New DXCC on band: as DXCC all, per band.
             New DXCC: as DXCC all, per ever.
             Casual: new call per band, not_worked; order snr_bucket, distance; CQ when
             idle.
             POTA/SOTA: as Casual, with worked since today, the CQ targets POTA and SOTA
             included, and no CQ when idle.
             One built-in of class contest for each contest of ContestTable, in its
             order, with the name of the contest: every band; empty lists; no order;
             calling stations answered; leaving in the mode contest after 2 Tx changes;
             the transmit frequency moved never, at every 2nd call and at every 2nd
             call; CQ when idle with a CQ wait of 2 periods; a retry
             pause of 10 minutes; a CQ pause of 8 periods; no alert. */
    }
    attribute def StrategyConfiguration {
        doc /* The strategies of a profile and what is selected. The saved strategies are
             managed by the settings function (WstxProfileAccess::StrategyDefinitions)
             and given to operating as SavedStrategies. The active strategy and the
             contest are changed by SelectStrategy and held while the station runs: at
             station start none is active and no contest is in force. */
        attribute strategiesMax : Integer = 16;
        attribute active : String[0..1] {
            doc /* The name of the active strategy, a saved or a built-in one, exactly as
                 it is written. Absent: no strategy is active. */ }
        attribute strategies : Strategy[0..*] ordered {
            doc /* The saved strategies, at most strategiesMax. */ }
        attribute contest : ContestSelection[0..1] {
            doc /* Present exactly while the active strategy is of class contest, and
                 then for that strategy's contest. */ }
    }
    attribute def ConfigurationKeys {
        doc /* The names under which the values of a StrategyConfiguration are written
             in the strategies file and named in a refusal. A value is named by its
             keys from the configuration down, joined by a full stop, with the place
             in a list in square brackets counted from 0: strategies[0].leave.calls.
             The configuration as a whole is named configuration.
             The configuration has the keys active, strategies and contest. contest
             may be left out; left out and null both
             say that no contest is selected. Its keys are profile, start and end.
             A strategy has the keys name, class, bands, filters, order, contest,
             callers_first, leave, tx_move_every, cq_when_idle,
             cq_wait_periods, retry_minutes, cq_quiet_periods and alert. alert may be
             left out; left out and null both say Off.
             bands, order and callers_first are those of RankingKeys. filters holds
             the other features of RankingKeys: for class strategy new, new_per,
             new_means, region with kind and for selected continents, min_snr_db,
             worked_since with kind and for from_to the keys from and to,
             treat_73_as_cq, countries, states and cq_targets; for class contest the
             last three only. Each of these three has the keys include and exclude; a
             country entry has kind, value and bands.
             leave has mode and, by the mode, calls and calls_heard, gone_minutes, or
             tx_changes. tx_move_every has heard, not_heard and no_reports.
             A value that the model writes as absent is null. A day is written
             YYYY-MM-DD, an instant YYYY-MM-DDTHH:MMZ.
             Every object has exactly its keys. One with a key missing or with another
             key is named as a whole, with two exceptions: a strategy without
             cq_wait_periods or cq_quiet_periods is named by that key, and so is a
             contest selection that
             carries one of the keys automation_confirmed, operation, repetitions and
             quiet_minutes.
             A list that is too long or too short is named as a whole; a member of it
             that is outside its rule or stands twice is named by its place. */
    }
    attribute def StrategyForm {
        doc /* The rules of a saved strategy, wherever one is created or changed.
             It is a Strategy: each of its values lies within the rule its feature
             states, in Strategy, in AutoKeys and in WstxRankingControl::RankingKeys
             with the definitions those name.
             A strategy of class strategy names no contest.
             A strategy of class contest names a contest of ContestTable, has an empty
             order, and has of the ranking rules only the bands, the country, US state
             and CQ target lists and callersFirst.
             A country entry of the kind country names an entity of the country file,
             without regard to letter case, and is held as the country file writes
             the name.
             There are at most StrategyConfiguration::strategiesMax saved strategies.
             A strategy outside these rules is not taken; one value that is outside
             its rule is named, as ConfigurationKeys says. */
    }
    attribute def StrategyReading {
        doc /* How saved strategies are read from the strategies file, also from the
             forms of its older schema versions 1, 2 and 3.
             A strategy without cq_wait_periods is read with a CQ wait of 2, and one
             without cq_quiet_periods with a CQ pause of 8; a strategy that holds
             busy_pause is read without it. A
             configuration that also holds one of the keys continent, ignore_calls and
             session_ignore_minutes is read without them: their values are not taken
             over and are not checked. A country entry is read as it stands.
             A saved strategy whose name is that of a built-in, without regard to
             letter case, is read under another name: the name with copy after it,
             and when that name is taken, with copy 2, copy 3 and so on, the first
             that is neither a built-in's nor a saved one; the name is cut so that the
             whole has at most 32 characters.
             Version 3. A strategy has exactly the keys name, class with the value
             award, goals, needed, region, min_snr_db, value, callers_first,
             cq_when_no_target, repetitions, quiet_minutes, treat_73_as_cq and window.
             It is read as a strategy of class strategy for every band, with empty
             country, US state and CQ target lists. Its goals give what must be new
             and the scope: dxcc is dxcc per ever, dxcc_band dxcc per band, dxcc_slot
             dxcc per band_mode, waz cq_zone per ever, wpx prefix per ever, grid grid
             per ever, new_call call per ever, new_call_band call per band; each once,
             in the order of the goals; of different scopes the one scope is
             band_mode before band before ever. needed is what new means, window the
             worked since, value the order with new_dxcc_slot read as
             new_dxcc_band_mode; region, min_snr_db, treat_73_as_cq and callers_first
             are taken as they are. It is left after repetitions calls and after twice
             as many while heard; the transmit frequency moves never, at every call
             and at every 2nd call for the three cases in the order of AutoKeys;
             cq_when_no_target is CQ when idle, with a CQ wait of 2;
             quiet_minutes is the retry pause.
             Version 2. A strategy has calls_per_station, from 1 to 20, in the place
             of value, callers_first, cq_when_no_target, repetitions and
             quiet_minutes. It is read as one of version 3 with the order most_wanted,
             calling stations answered, no CQ when idle, 4 repetitions and 10 quiet
             minutes; calls_per_station is not taken over.
             Version 1. The strategies are not taken over.
             A file of another version, and one of whose strategies is not of its
             version's form or outside StrategyForm, cannot be used. */
    }

    enum def DupeRule {
        doc /* When a second QSO with a station counts nothing.
             band: on the same band.
             band_mode_class: on the same band in the same of phone, CW and digital.
             band_grid: on the same band from the same grid.
             call: in the same period. */
        enum band;
        enum band_mode_class;
        enum band_grid;
        enum call;
    }
    enum def PointsRule {
        doc /* The points of one QSO. A distance is that between the centres of the two
             four-character squares, on a sphere of 6371 km radius.
             one_plus_per_3000_km: 1, and 1 more for each full 3000 km.
             one_plus_per_500_km_up: 1, and 1 more for each 500 km begun, one at least.
             field_day: 1 in phone, 2 in CW and in a digital mode.
             vhf_january: 1 on 6m, 5m, 4m and 2m; 2 on 1.25m and 70cm; 4 on 33cm and
             23cm; 8 above.
             vhf_june_september: 1, 2, 3 and 4 on the same bands.
             kilometres: 50 within one four-character square; otherwise 1 and the whole
             kilometres, with 111.2 km for a degree.
             one_per_call: 1. */
        enum one_plus_per_3000_km;
        enum one_plus_per_500_km_up;
        enum field_day;
        enum vhf_january;
        enum vhf_june_september;
        enum kilometres;
        enum one_per_call;
    }
    enum def MultiplierRule {
        doc /* What counts as a multiplier.
             none: nothing.
             field_per_band: each first two characters of a grid, on each band.
             grid_per_band: each first four characters of a grid, on each band. */
        enum none;
        enum field_per_band;
        enum grid_per_band;
    }
    enum def CountedModes {
        doc /* The modes whose QSOs a contest counts.
             ft8Ft4: FT8 and FT4.
             digital: every mode that is neither CW nor phone.
             digitalNoRtty: those, without RTTY.
             any: every mode.
             Phone is SSB, USB, LSB, AM, FM and DIGITALVOICE. */
        enum ft8Ft4;
        enum digital;
        enum digitalNoRtty;
        enum any;
    }
    enum def AutomationClause {
        doc /* What the rules of a contest say about automatic operation.
             forbidden: they forbid it.
             silent: they do not speak of it. */
        enum forbidden;
        enum silent;
    }
    attribute def ScheduleRule {
        doc /* When a contest takes place. A contest has one or more rounds. A round has
             a day, and a start and an end in minutes from 00:00 UTC of that day; the
             end is the first minute after the round.
             The day is the n-th or the last full weekend of a month, the n-th Saturday
             of a month, the n-th of a weekday in every month, or it is asked. A full
             weekend is a Saturday whose Sunday lies in the same month; its day is the
             Saturday.
             The period offered for a contest is that of the round that has not ended
             and starts first. A contest whose day is asked has none. */
    }
    attribute def ContestProfile {
        doc /* The facts of one contest, from its official rules. Its name in the
             Cabrillo format, its exchange, its score, the wording of its automation
             clause, its schedule in words, its notes and the address of its rules are
             texts for the operator. */
        attribute id : String;
        attribute name : String;
        attribute activity : Activity[0..1] {
            doc /* The special activity of the station that goes with the contest. */ }
        attribute cqWords : String[0..*] {
            doc /* The contest's own CQ words: a CQ that carries one of them is for the
                 station while the contest is in force and station time lies in its
                 period (WstxContestRanking::ContestDirective). They are also the words the
                 station may put after CQ in its own CQ in the contest; how a CQ to send
                 is chosen is the contact's and Auto's. */ }
        attribute bands : String[1..*] { doc /* ADIF band names in lower case. */ }
        attribute dupes : DupeRule;
        attribute points : PointsRule;
        attribute multipliers : MultiplierRule;
        attribute counted : CountedModes;
        attribute automation : AutomationClause;
        attribute schedule : ScheduleRule;
    }
    attribute def ContestTable {
        doc /* The contests the station knows, in the order in which they are offered.
             A profile is written as id: name; activity; bands; dupes, points,
             multipliers, counted modes; automation; schedule.
             ww_digi: WW Digi; ww_digi; 160m, 80m, 40m, 20m, 15m, 10m; band,
             one_plus_per_3000_km, field_per_band, ft8Ft4; forbidden; the last full
             weekend of August, Saturday 12:00 to Sunday 12:00.
             arrl_digi: ARRL Digi; arrl_digi; those six and 6m; band,
             one_plus_per_500_km_up, none, digitalNoRtty; forbidden; the first full
             weekend of June, Saturday 18:00 to Monday 00:00.
             arrl_field_day: ARRL Field Day; field_day; those six and every band from 6m
             up; band_mode_class, field_day, none, any; forbidden; the fourth full
             weekend of June, Saturday 18:00 to Sunday 21:00.
             arrl_vhf_jan: ARRL January VHF; na_vhf; every band from 6m up; band_grid,
             vhf_january, grid_per_band, any; forbidden; asked.
             arrl_vhf_jun: ARRL June VHF; as arrl_vhf_jan with vhf_june_september; the
             second full weekend of June, Saturday 18:00 to Monday 03:00.
             arrl_vhf_sep: ARRL September VHF; as arrl_vhf_jun, in September.
             iaru_50_mgm: IARU R1 50 MHz MGM; no activity; 6m; band, kilometres,
             grid_per_band, digital; silent; the third Saturday of April, 14:00 to
             Sunday 14:00.
             iaru_70_mgm: IARU R1 70 MHz MGM; as iaru_50_mgm on 4m, in May.
             ft8_activity: FT8 Activity; no activity; 2m, 70cm, 23cm; call,
             one_per_call, grid_per_band, digital; silent; in every month the first
             Wednesday on 2m, the second on 70cm and the third on 23cm, 17:00 to 21:00,
             each round with its one band.
             The CQ words of a contest are the word of its activity: WW for ww_digi,
             TEST for arrl_digi and the three ARRL VHF contests, FD for arrl_field_day;
             a contest without an activity has none. */
        @FollowsSource {
            reference = "The official rules of each contest; a profile names the "
                + "address of its rules";
        }
    }
    attribute def ContestSelection {
        doc /* The contest in force and its period. */
        attribute periodDaysMax : Integer = 31;
        attribute profile : String { doc /* The id of a contest of ContestTable. */ }
        attribute start : String {
            doc /* The first minute of the period, an instant of UTC to the minute. */ }
        attribute 'end' : String {
            doc /* The first minute after the period: after start, and at most
                 periodDaysMax days after it. */ }
    }

    item def SavedStrategies {
        doc /* The strategies the operator has saved, as the settings function keeps
             them (WstxProfileAccess::StrategyDefinitions). The supervisor gives
             them at station start and after every change. */
        attribute strategies : Strategy[0..*] ordered;
    }
    item def SelectStrategy {
        doc /* Make this strategy the active one, for class contest with its contest, or
             none. It is the one command by which the operator selects the active
             strategy and a contest. Answered by StrategiesState or
             StrategiesRefused. */
        attribute active : String[0..1] { doc /* As StrategyConfiguration::active. */ }
        attribute contest : ContestSelection[0..1] {
            doc /* As StrategyConfiguration::contest. */ }
    }
    item def ReadStrategies { doc /* Ask for the state. Answered by StrategiesState. */ }
    item def ReadContests {
        doc /* Ask for the contests with the period of each. Answered by ContestList. */
    }

    item def StrategiesState {
        doc /* What operating holds, at the moment it is given. */
        attribute configuration : StrategyConfiguration;
        attribute builtins : Strategy[1..*] ordered {
            doc /* The strategies of BuiltinStrategies, in their order. */ }
    }
    attribute def OfferedPeriod {
        doc /* The period of the round of a contest that ScheduleRule offers. */
        attribute start : String { doc /* As ContestSelection::start. */ }
        attribute 'end' : String { doc /* As ContestSelection::'end'. */ }
        attribute band : String[0..1] {
            doc /* The one band of the round. Absent for a round on every band of the
                 contest. */ }
    }
    attribute def ContestOffer {
        attribute profile : String { doc /* The id of a contest of ContestTable. */ }
        attribute period : OfferedPeriod[0..1] {
            doc /* Absent for a contest whose day is asked. */ }
    }
    item def ContestList {
        doc /* The contests of ContestTable, in its order, each with its period at the
             moment of the ReadContests. */
        attribute contests : ContestOffer[1..*] ordered;
    }
    item def StrategiesRefused {
        doc /* The answer to a SelectStrategy that is not carried out: a value of it is
             outside its rule. A refused selection changes nothing. */
        attribute field : String {
            doc /* That value, named as ConfigurationKeys says. */ }
    }

    attribute def AutoStrategy {
        doc /* What Auto needs of one strategy. */
        attribute name : String;
        attribute keys : AutoKeys;
        attribute contest : ContestSelection[0..1] {
            doc /* Present for a strategy of class contest: its contest and the period
                 in force. */ }
        attribute automation : AutomationClause[0..1] {
            doc /* Present for a strategy of class contest: what the rules of its
                 contest say of automatic operation (ContestProfile::automation). */ }
    }
    item def AutoRules {
        doc /* The rules Auto executes. Operating gives them at station start and
             whenever one changes. */
        attribute active : AutoStrategy[0..1] {
            doc /* The active strategy. Absent while none is active. */ }
    }
    item def ContestActivity {
        doc /* The special activity that goes with the contest in force. Operating gives it
             at station start and whenever it changes; the contact uses it as
             WstxSpecialActivities::ActivityRule says. */
        attribute inForce : Boolean { doc /* A contest is in force. */ }
        attribute activity : Activity[0..1] {
            doc /* ContestProfile::activity of the contest in force. Absent while no
                 contest is in force, and for a contest without an activity. */ }
    }

    port def StrategiesPort {
        doc /* Written from the supervisor's side; operating uses the conjugate.
             SavedStrategies has no answer. An answer goes to the one command it
             belongs to. */
        out item saved : SavedStrategies;
        out item selection : SelectStrategy;
        out item readStrategies : ReadStrategies;
        out item readContests : ReadContests;
        in item strategies : StrategiesState;
        in item contests : ContestList;
        in item refused : StrategiesRefused;
    }
    interface def StrategiesControl {
        doc /* The supervisor commands the operating function; operating answers
             with what it holds. */
        end station : StrategiesPort;
        end operating : ~StrategiesPort;
    }
    port def RankingSharePort {
        doc /* Written from operating's side; ranking uses the conjugate. RankingRules
             has no answer. */
        out item rules : RankingRules;
    }
    interface def RankingShare {
        doc /* Operating gives ranking the ranking rules of the active strategy. */
        end operating : RankingSharePort;
        end ranking : ~RankingSharePort;
    }
    port def AutoSharePort {
        doc /* Written from operating's side; Auto uses the conjugate. AutoRules has no
             answer. */
        out item rules : AutoRules;
    }
    interface def AutoShare {
        doc /* Operating gives Auto the rules of the active strategy that it
             executes. */
        end operating : AutoSharePort;
        end auto : ~AutoSharePort;
    }
    port def ActivitySharePort {
        doc /* Written from operating's side; the contact uses the conjugate.
             ContestActivity has no answer. */
        out item activity : ContestActivity;
    }
    interface def ActivityShare {
        doc /* Operating gives the contact the special activity of the contest in
             force. */
        end operating : ActivitySharePort;
        end qso : ~ActivitySharePort;
    }
}

package WstxRankingControl {
    private import ScalarValues::*;
    private import WstxModeProcessing::Mode;
    private import WstxDecodes::JobIdentity;
    private import WstxDecodes::PeriodView;
    private import WstxLogControl::Continent;
    private import WstxLogControl::WorkedStatus;
    private import WstxProfileAccess::MostWantedList;
    private import WstxStrategies::AlertSound;
    private import WstxModelNotes::CodeDiffers;

    doc /* What the supervisor gives the ranking function (what the profile and the
         radio say, and the operator's commands); the rules operating gives it of the
         active strategy; and what ranking answers and reports: the ranked list, the
         facts of each decoded record, its lists and the alerts. */

    enum def NewWhat {
        doc /* What must be new.
             dxcc: the DXCC entity of the sender.
             call: the sender's call.
             grid: the first four characters of the grid in the message.
             cqZone, ituZone, continent: those of the sender's entity.
             prefix: the prefix of the sender's call by the rules of the CQ WPX contest. */
        enum dxcc;
        enum call;
        enum grid;
        enum cqZone;
        enum ituZone;
        enum continent;
        enum prefix;
    }
    enum def NewPer {
        doc /* The scope in which it must be new.
             ever: in any QSO.
             band: on the station's band, in any mode.
             bandMode: on the station's band in the operating mode. */
        enum ever;
        enum band;
        enum bandMode;
    }
    enum def Needed {
        doc /* What new means.
             notWorked: no QSO holds the key in the scope.
             notConfirmed: no QSO holds it there, or none of them is confirmed. */
        enum notWorked;
        enum notConfirmed;
    }
    enum def ValueCriterion {
        doc /* The criteria of an order. What each one puts first is said by
             WstxValueOrder::ValueOrder. */
        enum mostWanted;
        enum newDxcc;
        enum newDxccBand;
        enum newDxccBandMode;
        enum newCall;
        enum newCallBand;
        enum newGrid;
        enum newGridBand;
        enum newCqZone;
        enum newItuZone;
        enum newContinent;
        enum newPrefix;
        enum snrBucket;
        enum snr;
        enum distance;
        enum hearsUs;
    }
    enum def RegionKind {
        doc /* 'all': every sender.
             dx: a sender of another continent than the station's.
             selected: a sender of one of the continents listed. */
        enum 'all';
        enum dx;
        enum selected;
    }
    enum def WindowKind {
        doc /* Which QSOs count as worked.
             'all': every QSO of the logbook.
             today: those of the current UTC date.
             fromTo: those from a first to a last date, both included. */
        enum 'all';
        enum today;
        enum fromTo;
    }
    attribute def WorkedSince {
        doc /* The QSOs that count as worked for a strategy. */
        attribute kind : WindowKind;
        attribute firstDate : String[0..1] {
            doc /* With fromTo: a day of the calendar from 1930 to 2099, as YYYYMMDD. */
            @CodeDiffers {
                what = "The code names it from (worked_since in server/src/operating/strategy.rs).";
            }
        }
        attribute lastDate : String[0..1] {
            doc /* With fromTo: as firstDate, and not before it. */
            @CodeDiffers {
                what = "The code names it to (worked_since in server/src/operating/strategy.rs).";
            }
        }
    }
    attribute def StrategyBands {
        doc /* The bands a strategy works on: band names of the ADIF enumeration in lower
             case, each once, at most RankingLimits::bandsMax. */
        attribute bands : String[1..*];
    }
    enum def CountryKind {
        doc /* prefix: the entry is the beginning of a call.
             country: the entry is the name of an entity as the country file writes it. */
        enum prefix;
        enum country;
    }
    attribute def CountryEntry {
        attribute kind : CountryKind;
        attribute value : String {
            doc /* A prefix has 1 to 13 characters of A to Z, 0 to 9 and "/". A country
                 name has 1 to 64 characters. */ }
        attribute bands : StrategyBands[0..1] {
            doc /* The bands on which the entry counts; absent for every band. */ }
    }
    attribute def CountryList {
        doc /* The prefixes and countries a strategy takes and leaves out, at most
             RankingLimits::countriesMax in each list. An entry may stand twice. */
        attribute included : CountryEntry[0..*] {
            @CodeDiffers {
                what = "The code names it include (lists_of in server/src/operating/strategy.rs).";
            }
        }
        attribute excluded : CountryEntry[0..*] {
            @CodeDiffers {
                what = "The code names it exclude (lists_of in server/src/operating/strategy.rs).";
            }
        }
    }
    attribute def UsStateFilter {
        doc /* The US states a strategy takes and leaves out: the two-letter codes of the
             50 states and DC, each once in a list. */
        attribute included : String[0..51] {
            @CodeDiffers {
                what = "The code names it include (lists_of in server/src/operating/strategy.rs).";
            }
        }
        attribute excluded : String[0..51] {
            @CodeDiffers {
                what = "The code names it exclude (lists_of in server/src/operating/strategy.rs).";
            }
        }
    }
    attribute def CqTargetList {
        doc /* The CQ directives a strategy takes and leaves out: words of 1 to 8
             characters of A to Z and 0 to 9, each once in a list, at most
             RankingLimits::cqTargetsMax in each.
             The included words are the strategy's own CQ words: a CQ that carries one
             of them is for the station under the strategy
             (WstxValueOrder::DirectedCqRule). They are also words the station may put
             after CQ in its own CQ under the strategy; how a CQ to send is chosen is
             the contact's and Auto's. */
        attribute included : String[0..*] {
            @CodeDiffers {
                what = "The code names it include (lists_of in server/src/operating/strategy.rs).";
            }
        }
        attribute excluded : String[0..*] {
            @CodeDiffers {
                what = "The code names it exclude (lists_of in server/src/operating/strategy.rs).";
            }
        }
    }
    attribute def RankingKeys {
        doc /* The ranking rules of one strategy. A strategy of class contest gives
             bands, countries, states, cqTargets and callersFirst; its other rules come
             from its contest. */
        attribute bands : StrategyBands[0..1] { doc /* Absent: every band. */ }
        attribute newWhat : NewWhat[0..7] {
            doc /* One at least for a strategy of class strategy, each once. */ }
        attribute newPer : NewPer[0..1] { doc /* One scope for every NewWhat. */ }
        attribute newMeans : Needed[0..1];
        attribute region : RegionKind[0..1];
        attribute regionContinents : Continent[0..7] {
            doc /* With selected: one at least, each once. */
            @CodeDiffers {
                what = "The code names it continents, inside region "
                    + "(server/src/operating/strategy.rs).";
            }
        }
        attribute minSnrDb : Integer[0..1] {
            doc /* -50 to 49. Absent: no minimum. */ }
        attribute workedSince : WorkedSince[0..1];
        attribute treat73AsCq : Boolean[0..1];
        attribute countries : CountryList;
        attribute states : UsStateFilter;
        attribute cqTargets : CqTargetList;
        attribute order : ValueCriterion[0..*] ordered {
            doc /* Each criterion once, at most RankingLimits::orderMax; the first
                 decides. Empty for class contest. */ }
        attribute callersFirst : Boolean {
            doc /* Stations that call the profile's call are answered. */ }
    }
    attribute def ContestInForce {
        doc /* The contest a strategy of class contest ranks by, and its period. */
        attribute profile : String {
            doc /* The id of the contest in WstxStrategies::ContestTable. */ }
        attribute startUtcMs : Integer { doc /* The first instant of the period. */ }
        attribute endUtcMs : Integer { doc /* The first instant after it. */ }
    }
    attribute def StrategyRules {
        doc /* What ranking needs of one strategy. */
        attribute name : String;
        attribute keys : RankingKeys;
        attribute contest : ContestInForce[0..1] {
            doc /* Present for a strategy of class contest. */ }
    }

    attribute def RankingLimits {
        attribute orderMax : Integer = 16 { doc /* Criteria in an order. */ }
        attribute bandsMax : Integer = 32 { doc /* Bands in a StrategyBands. */ }
        attribute countriesMax : Integer = 64 { doc /* Entries in each country list. */ }
        attribute cqTargetsMax : Integer = 32 { doc /* Words in each CQ target list. */ }
        attribute ignoreListMax : Integer = 100 {
            doc /* Entries in the ignore list. */
            @CodeDiffers {
                what = "The code keeps two lists in server/src/operating/strategy.rs: a saved list "
                    + "of at "
                    + "most IGNORE_CALLS_MAX 100 calls (parse_config) and a session list of "
                    + "SESSION_IGNORE_MAX 64, whose 65th entry drops the oldest (Session::add).";
            }
        }
        attribute wantedListMax : Integer = 100 {
            doc /* Entries in the wanted list. */
            @CodeDiffers {
                what = "The code has no wanted list.";
            }
        }
        attribute evaluateMax : Integer = 2048 {
            doc /* Records one EvaluateRequest may span. */ }
        attribute alertHistoryMax : Integer = 100 { doc /* Alerts the history keeps. */ }
        attribute alertDedupeMinutes : Integer = 10 {
            doc /* The time in which a call alerts once on a band. */ }
    }
    attribute def WantedEntry {
        doc /* One entry of the wanted list (WstxWantedList::WantedRule). The settings
             function keeps the list for the shack's stations: at most
             RankingLimits::wantedListMax entries in the order they were added, each
             call once. */
        attribute call : String {
            doc /* A call or a pattern, of the form of IgnoreCommand::call. */ }
        attribute addedUtcMs : Integer {
            doc /* When the entry was added, in milliseconds of UTC since 1970; set by
                 the settings function when it adds the entry. */
            @CodeDiffers {
                what = "The code has no wanted list.";
            }
        }
    }
    item def RankingContext {
        doc /* What ranking needs to know of the station. The supervisor gives it
             at station start and whenever one of its values changes. */
        attribute call : String[0..1] {
            doc /* The profile's call. Absent while the profile has none. */ }
        attribute locator : String[0..1] { doc /* The profile's locator. */ }
        attribute band : String[0..1] {
            doc /* The station's band (WstxOperatingSelection::StationBandRule). */ }
        attribute mode : Mode { doc /* The station's operating mode. */ }
        attribute continent : Continent[0..1] {
            doc /* The continent the operator has set for the station,
                 WstxProfileAccess::ShackConfig::continent. Absent: ranking derives
                 it. */ }
        attribute cqWords : String[0..*] {
            doc /* The CQ words for this station,
                 WstxProfileAccess::ShackConfig::cqWords. */
            @CodeDiffers {
                what = "The code has no CQ words of the station; the included CQ targets of the "
                    + "active strategy are its CQ words (server/src/operating/strategy.rs).";
            }
        }
        attribute wanted : WantedEntry[0..*] ordered {
            doc /* The wanted list, as the settings function keeps it
                 (WstxProfileAccess::DefinitionsSnapshot::wanted). */ }
        attribute mostWanted : MostWantedList[0..1] {
            doc /* The Most Wanted list, as the settings function keeps it
                 (WstxProfileAccess::DefinitionsSnapshot::mostWanted). */ }
    }
    item def RankingRules {
        doc /* The rules ranking works by. Operating gives them at station start and
             whenever one changes, on its own connection to ranking. */
        attribute active : StrategyRules[0..1] {
            doc /* The active strategy. Absent while Default is active: ranking then
                 gives no ranked list and records no alert. */ }
    }
    item def EvaluateRequest {
        doc /* Evaluate the records of one job from firstSequence up to, and not
             including, nextSequence. Answered by EvaluateReply or RankingRefused. */
        attribute job : JobIdentity;
        attribute firstSequence : Integer;
        attribute nextSequence : Integer {
            doc /* Not below firstSequence, and at most RankingLimits::evaluateMax above
                 it. */ }
        attribute draft : StrategyRules[0..1] {
            doc /* The strategy to evaluate. Absent: the active one. */ }
        attribute explain : Boolean { doc /* Ask for every verdict with its reason. */ }
    }
    item def IgnoreCommand {
        doc /* Put an entry on the ignore list, or take it off. Answered by RankingState
             or RankingRefused. */
        attribute call : String {
            doc /* The entry, a call or a pattern: 1 to 13 characters of A to Z, 0 to 9,
                 "/", "*" and "?", with at least one letter. */ }
        attribute ignore : Boolean { doc /* False takes the entry off. */ }
    }
    item def ClearIgnoreList {
        doc /* Take every entry off the ignore list. Answered by RankingState. */
    }
    item def ReadRankingState { doc /* Ask for the lists. Answered by RankingState. */ }
    item def ReadAlerts { doc /* Ask for the alert history. Answered by Alert. */ }
    item def ClearAlerts { doc /* Empty the alert history. Answered by Alert. */ }

    enum def VerdictKind {
        doc /* What a ranked record is.
             wanted: its sender is wanted and can be called
             (WstxWantedList::WantedRule).
             caller: its sender calls the profile's call.
             candidate: every other ranked record. */
        enum wanted;
        enum caller;
        enum candidate;
    }
    attribute def ContestVerdict {
        doc /* What a verdict adds under a contest. */
        attribute dupe : Boolean;
        attribute newMultiplier : Boolean;
        attribute points : Integer[0..1] { doc /* Absent when they are not known. */ }
    }
    attribute def Verdict {
        doc /* The verdict on one decoded record. */
        attribute sequence : Integer { doc /* The number of the record. */ }
        attribute rank : Integer[0..1] {
            doc /* The place among the ranked records of the evaluation, from 0. Absent:
                 the record is not ranked. */ }
        attribute kind : VerdictKind[0..1] { doc /* Present with a rank. */ }
        attribute grey : Boolean {
            doc /* The record is a CQ whose directive leaves the station out. */ }
        attribute why : String[0..1] {
            doc /* The reason for the verdict. In an EvaluateReply it is present only
                 when the request asked for it. */ }
        attribute contest : ContestVerdict[0..1] {
            doc /* Present under a contest, from the dupe test on. */ }
    }
    item def RankedList {
        doc /* The verdicts of one evaluation: the ranked records by their rank, then the
             records without a rank by the same criteria. */
        item periodView : PeriodView {
            doc /* The period view whose records were evaluated; it names the job and
                 says whether the period is complete. */
            @CodeDiffers {
                what = "The reply names no period view; the request names the job by source_id "
                    + "and job_id (server/src/operating/strategy.rs).";
            }
        }
        attribute verdicts : Verdict[0..*] ordered;
        attribute offBand : Boolean {
            doc /* The station's band is none of the bands of the active strategy, or of
                 the contest in force; then no verdict has a rank. */ }
    }
    attribute def ContestTally {
        doc /* What the logbook holds of the contest's period. */
        attribute qsos : Integer;
        attribute multipliers : Integer;
        attribute points : Integer;
        attribute score : Integer;
    }
    item def EvaluateReply {
        doc /* The answer to an EvaluateRequest. */
        attribute strategy : String {
            doc /* The name of the strategy evaluated; under a contest the name of the
                 contest. */ }
        attribute myContinent : Continent[0..1];
        attribute verdicts : Verdict[0..*] ordered {
            doc /* As in RankedList: every verdict, with or without explain. */ }
        attribute tally : ContestTally[0..1] {
            doc /* Present under a contest while the logbook is available. */ }
    }
    attribute def MostWantedStatus {
        doc /* The Most Wanted list in use. */
        attribute date : String { doc /* The UTC date of the download. */ }
        attribute entries : Integer { doc /* The entities the list ranks. */ }
        attribute unmapped : Integer {
            doc /* The entries whose number no entity of the country file carries. */ }
    }
    item def RankingState {
        doc /* The lists and values ranking holds, at the moment they are read. */
        attribute ignoreList : String[0..*] ordered {
            doc /* The entries of the ignore list, in the order in which they were put
                 on it. */ }
        attribute mostWanted : MostWantedStatus[0..1] {
            doc /* Absent while ranking has no list. */ }
        attribute myContinent : Continent[0..1] {
            doc /* The station's continent as ranking uses it. */ }
        attribute derivedContinent : Continent[0..1] {
            doc /* The continent of the entity of the profile's call. */ }
    }
    attribute def AlertEntry {
        attribute id : Integer {
            doc /* 1 for the first alert since station start, one higher for each
                 alert. */ }
        attribute utc : String {
            doc /* The start of the record's period, as the record gives it. */ }
        attribute call : String { doc /* The sender. */ }
        attribute messageText : String { doc /* The text of the record. */ }
        attribute rule : String { doc /* The name of the active strategy. */ }
        attribute band : String[0..1] {
            doc /* The station's band. Absent when it is unknown. */ }
        attribute mode : Mode { doc /* The mode of the job. */ }
        attribute snrDb : Real[0..1];
        attribute dxcc : String[0..1] {
            doc /* The sender's entity as the country file writes it. Absent without an
                 entity. */ }
        attribute sound : AlertSound { doc /* The active strategy's Strategy::alert. */ }
    }
    item def Alert {
        doc /* The alert history: the newest RankingLimits::alertHistoryMax alerts in the
             order in which they were recorded. Given as the answer to ReadAlerts and
             ClearAlerts and whenever it changes. */
        attribute revision : Integer {
            doc /* 0 at station start, one higher for each alert recorded and for each
                 ClearAlerts. */ }
        attribute history : AlertEntry[0..*] ordered;
    }
    enum def NewFlag {
        doc /* What is new about the sender of a decoded record: its call, the grid of
             its message, its entity, and the continent and the zones of that entity,
             each in any QSO and, with the ending Band, on the station's band in any
             mode. */
        enum newCall;
        enum newCallBand;
        enum newGrid;
        enum newGridBand;
        enum newDxcc;
        enum newDxccBand;
        enum newContinent;
        enum newContinentBand;
        enum newCqZone;
        enum newCqZoneBand;
        enum newItuZone;
        enum newItuZoneBand;
    }
    attribute def EntityView {
        doc /* The entity of a sender, for a display. */
        attribute name : String { doc /* The shown name of the entity. */ }
        attribute continent : Continent;
        attribute cqZone : Integer;
        attribute ituZone : Integer;
        attribute km : Integer[0..1] {
            doc /* The distance from the profile's locator to the position of the
                 entity. Absent while the profile has no locator. */ }
    }
    item def DecodedFacts {
        doc /* What ranking adds to one decoded record. */
        attribute job : JobIdentity;
        attribute sequence : Integer { doc /* The number of the record. */ }
        attribute entity : EntityView[0..1] {
            doc /* Absent when the sender has no entity. */ }
        attribute flags : NewFlag[0..12] { doc /* Those that hold, each once. */ }
        attribute worked : WorkedStatus[0..1] {
            doc /* Whether the sender has been worked on the station's band in the mode
                 of the job. Absent where WstxValueOrder::DecodedEntity gives none. */ }
    }
    enum def RankingRefusal {
        doc /* Why a command is refused.
             notConfigured: Default is active and the request names no draft.
             staleRequest: the job of the request is not the station's current job.
             ignoreListFull: the ignore list holds RankingLimits::ignoreListMax entries
             and the entry is not among them. */
        enum notConfigured;
        enum staleRequest;
        enum ignoreListFull {
            @CodeDiffers {
                what = "The code refuses no entry: a full session list drops its oldest entry "
                    + "(Session::add in server/src/operating/strategy.rs).";
            }
        }
    }
    item def RankingRefused {
        doc /* The answer to an EvaluateRequest or an IgnoreCommand that is refused. A
             refused command changes nothing. */
        attribute refusal : RankingRefusal;
    }

    item def WantedWorked {
        doc /* An exact entry of the wanted list with whose call a QSO has been logged
             after it was added (WstxWantedList::WantedRemoval). The supervisor
             removes it from the list (WstxProfileAccess::DeleteEntry). */
        attribute call : String;
    }
    port def RankingControlPort {
        doc /* Written from the supervisor's side; ranking uses the conjugate.
             RankingContext has no answer. An answer goes to the one command it belongs
             to. RankedList, DecodedFacts and Alert are also given without a command,
             when ranking has made them. */
        out item context : RankingContext;
        out item evaluate : EvaluateRequest;
        out item ignore : IgnoreCommand;
        out item clearIgnore : ClearIgnoreList {
            @CodeDiffers {
                what = "The code has no such command; a change of the station band empties the "
                    + "session list (Session::observe_band in server/src/operating/strategy.rs).";
            }
        }
        out item readState : ReadRankingState {
            @CodeDiffers {
                what = "The code reads the lists by GET /strategy (snapshot in "
                    + "server/src/operating/strategy.rs).";
            }
        }
        out item readAlerts : ReadAlerts {
            @CodeDiffers {
                what = "The code reads them by GET /strategy/alerts (alerts_route in "
                    + "server/src/operating/strategy.rs).";
            }
        }
        out item clearAlerts : ClearAlerts;
        in item ranked : RankedList;
        in item reply : EvaluateReply;
        in item lists : RankingState;
        in item alerts : Alert;
        in item facts : DecodedFacts;
        in item refused : RankingRefused;
        in item wantedWorked : WantedWorked {
            @CodeDiffers {
                what = "The code has no wanted list.";
            }
        }
    }
    interface def RankingControl {
        doc /* The supervisor commands the ranking function; ranking reports the
             ranked list, what it knows of each decoded record, its lists and its
             alerts. */
        end station : RankingControlPort;
        end ranking : ~RankingControlPort;
    }
}

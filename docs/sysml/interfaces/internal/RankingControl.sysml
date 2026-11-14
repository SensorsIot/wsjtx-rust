package WstxRankingControl {
    private import ScalarValues::*;
    private import WstxModeProcessing::Mode;
    port def RankingControlPort {
        out item rules : RankingRules;
        in item ranked : RankedList;
        in attribute alert : Alert;
    }
    item def RankingRules {
        doc /* The active strategy's ranking rules, the lists and the commands the station sends:
             the filters, the order, the contest and the ignore lists, and one command each to
             evaluate, to add or remove a session ignore entry, to clear the alerts and to update
             the Most Wanted list. The wire keys are those of the strategy. */
        attribute keys : RankingKeys;
        attribute ignore : IgnoreLists;
        attribute mostWanted : MostWantedList[0..1];
        attribute evaluate : EvaluateRequest[0..1];
        attribute ignoreCommand : IgnoreCommand[0..1];
        attribute clearAlerts : Boolean = false;
        attribute updateMostWanted : Boolean = false;
    }
    item def RankedList {
        doc /* The ranked verdicts of the evaluated records, the evaluate reply and the ranking
             state: the session ignore list, the Most Wanted status, my continent as configured
             or as derived from my callsign. */
        attribute reply : EvaluateReply;
        attribute rankingState : RankingState;
    }
    attribute def RankingKeys {
        doc /* The ranking group of a strategy: bands, filters, order, contest and whether
             callers of
             my call are answered first. */
        attribute bands : StrategyBands;
        attribute newWhat : NewWhat[0..7];
        attribute newPer : NewPer;
        attribute newMeans : Needed;
        attribute region : RegionKind;
        attribute regionContinents : Continent[0..7];
        attribute minSnrDb : Integer[0..1];
        attribute workedSince : WorkedWindow;
        attribute treat73AsCq : Boolean = true;
        attribute countries : CountryList;
        attribute states : UsStateFilter;
        attribute cqTargets : CqTargetList;
        attribute order : ValueCriterion[0..16];
        attribute contest : String[0..1];
        attribute callersFirst : Boolean = true;
    }
    attribute def EvaluateReply {
        doc /* The verdicts of an evaluate request, in display order, and with a contest in
             force the
             contest verdicts and the tally. */
        attribute verdicts : Verdict[0..*];
        attribute contestVerdicts : ContestVerdict[0..*];
        attribute contestTally : ContestTally[0..1];
    }
    attribute def RankingState {
        doc /* The session ignore list, the Most Wanted status, and my continent as configured or as
             derived from my callsign. */
        attribute sessionIgnore : SessionIgnoreEntry[0..*];
        attribute mostWantedStatus : MostWantedStatus[0..1];
        attribute myContinent : Continent[0..1];
        attribute derivedContinent : Continent[0..1];
    }
    interface def RankingControl {
        doc /* The station service commands the ranking function; ranking reports the ranked
             list and its alerts. */
        end station : RankingControlPort;
        end ranking : ~RankingControlPort;
    }

    enum def Continent { enum AF; enum AN; enum AS; enum EU; enum NA; enum OC; enum SA; }
    enum def NewWhat {
        doc /* What must be new, wire names exactly, multiple choice: dxcc (the DXCC entity), call,
             grid (the 4-character grid), cq_zone (WAZ), itu_zone, continent (WAC), prefix (WPX,
             WpxPrefix). */
        enum dxcc; enum call; enum grid; enum cq_zone; enum itu_zone; enum continent; enum prefix;
    }
    enum def NewPer {
        doc /* New per: ever (any band and mode), band (the station band, any mode), band_mode (the
             station band and the operating mode, ADIF MODE, an MFSK record by its SUBMODE). One
             choice for every NewWhat of the strategy. */
        enum ever; enum band; enum band_mode;
    }
    enum def Needed {
        doc /* New means: not_worked; not_confirmed (not worked, or worked and not confirmed: LoTW,
             QSL or eQSL received, dxcc::Standing). */
        enum not_worked; enum not_confirmed;
    }
    enum def ValueCriterion {
        doc /* The criteria of ValueOrder, wire names exactly. */
        enum most_wanted; enum new_dxcc; enum new_dxcc_band; enum new_dxcc_band_mode;
        enum new_call; enum new_call_band; enum new_grid; enum new_grid_band;
        enum new_cq_zone; enum new_itu_zone; enum new_continent; enum new_prefix;
        enum snr_bucket; enum snr; enum distance; enum hears_us;
    }
    enum def RegionKind { enum 'all'; enum dx; enum selected; }
    enum def WindowKind { enum 'all'; enum today; enum from_to; }
    attribute def WorkedWindow {
        attribute kind : WindowKind;
        attribute firstDate : String[0..1];
        attribute lastDate : String[0..1];
        doc /* The window of the worked set: from_to carries two real calendar dates
             "YYYY-MM-DD" between 1930-01-01 and 2099-12-31 with firstDate <= lastDate. */
    }
    attribute def StrategyBands {
        attribute bands : String[0..32];
        doc /* The ADIF band names, in lower case ("20m", "6m", "2m", "70cm"), 1..32 unique, of the
             ADIF band enumeration; none: every band. */
    }
    enum def CountryKind { enum prefix; enum country; }
    attribute def CountryEntry {
        attribute kind : CountryKind;
        attribute value : String;
        attribute bands : StrategyBands[0..1];
        doc /* kind prefix: value 1..13 of A-Z 0-9 / (upper case); kind country: a full entity
             name of
             the country table. */
    }
    attribute def CountryList {
        attribute entriesMax : Integer = 64;
        attribute included : CountryEntry[0..*];
        attribute excluded : CountryEntry[0..*];
        doc /* The prefix and country lines of the filters, each list 0..entriesMax entries. */
    }
    attribute def UsStateFilter {
        attribute included : String[0..51];
        attribute excluded : String[0..51];
        doc /* Unique two-letter codes of the 50 US states and DC (ADIF Primary Administrative
             Subdivision of the entities 291, 6 and 110). */
    }
    attribute def CqTargetList {
        attribute entriesMax : Integer = 32;
        attribute included : String[0..*];
        attribute excluded : String[0..*];
        doc /* The CQ target lines of the filters: each list 0..entriesMax unique words of 1..8 A-Z
             0-9. */
    }
    attribute def Verdict {
        attribute sequence : Integer;
        attribute rank : Integer[0..1];
        attribute grey : Boolean;
        attribute why : String[0..1];
        doc /* The verdict of one decoded standard record with a resolved sender: its place in the
             decode order, its rank (null: not ranked), whether it is greyed and, when asked,
             why. */
    }
    attribute def ContestVerdict {
        attribute dupe : Boolean;
        attribute newMultiplier : Boolean;
        attribute points : Integer[0..1];
        doc /* The verdict with a contest in force: a Verdict with whether the record is a dupe, a
             new multiplier and its QSO points (null when not known). */
    }
    attribute def ContestTally {
        attribute qsos : Integer;
        attribute multipliers : Integer;
        attribute points : Integer;
        attribute score : Integer;
        doc /* The tally of the contest log in the period. */
    }
    attribute def EvaluateRequest {
        attribute recordsMax : Integer = 2048;
        attribute sourceId : String;
        attribute jobId : String;
        attribute generation : Integer;
        attribute firstSequence : Integer;
        attribute nextSequence : Integer;
        attribute draft : RankingKeys[0..1];
        attribute explain : Boolean;
        doc /* The retained records [firstSequence, nextSequence) of one live job, at most
             recordsMax, evaluated for the saved active strategy or, with a draft, for the draft;
             explain asks for the reason of every verdict. */
    }
    attribute def IgnoreCommand {
        attribute call : String;
        attribute ignore : Boolean;
        doc /* Add the entry (the key stays call) to the session ignore list (or renew it) or, with
             ignore false, remove it (not listed: no change). */
    }
    attribute def SessionIgnoreEntry {
        attribute call : String;
        attribute band : String[0..1];
        attribute expiry : String;
        doc /* One entry of the session ignore list: the entry (the key stays call), the station
             band when it was added (null when unknown) and its expiry. */
    }
    attribute def IgnoreLists {
        attribute sessionEntriesMax : Integer = 64;
        attribute permanent : String[0..*];
        attribute session : SessionIgnoreEntry[0..*];
        doc /* The permanent list (the entries of the strategy configuration) and the session list
             (at most sessionEntriesMax entries in the order added). */
    }
    attribute def MostWantedEntry {
        attribute rank : Integer;
        attribute adifNumber : Integer;
        doc /* The rank of one DXCC entity, by its ADIF number. */
    }
    attribute def MostWantedList {
        attribute entriesMax : Integer = 1000;
        attribute entries : MostWantedEntry[0..*];
        doc /* The list, 1..entriesMax entries, kept in the profile folder as most_wanted.json
             {schema_version 1, profile_id, date (UTC date of the download), list}. */
    }
    attribute def MostWantedStatus {
        attribute date : String;
        attribute entries : Integer;
        attribute unmapped : Integer;
        attribute unreadable : Boolean;
        attribute attribution : String =
            "Club Log Most Wanted list, Club Log (c) Michael Wells G7VJR, clublog.org";
        doc /* The status of the list: the date of the download, the number of entries and of
             numbers that no cty.dat entity maps to; unreadable when the file cannot be read. */
    }
    attribute def AlertEntry {
        attribute id : Integer;
        attribute utc : String;
        attribute call : String;
        attribute messageText : String;
        attribute rule : String;
        attribute band : String[0..1];
        attribute mode : Mode;
        attribute snrDb : Integer[0..1];
        attribute dxcc : String[0..1];
        doc /* One alert: id (1, 2, ... since the station started), utc (the record's
             period_start_utc), call, messageText (the record text), rule (the strategy name), band
             (station band, null when unknown), mode (the live job mode), snrDb (null when
             unknown), dxcc (the full entity name of WstxCountryFile::EntityOfCall, null
             without an entity). */
    }
    attribute def Alert {
        attribute historyMax : Integer = 100;
        attribute dedupeMinutes : Integer = 10;
        attribute revision : Integer;
        attribute history : AlertEntry[0..*];
        doc /* The alert history: station memory only (it survives page reloads, a station restart
             empties it), the last historyMax alerts in the order recorded (a further alert drops
             the oldest); revision counts every alert recorded and every clear since the station
             started. */
    }
}

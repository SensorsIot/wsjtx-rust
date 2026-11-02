package WstxStrategy {
    private import ScalarValues::*;
    doc /* Canonical contract of the strategy engine (issue #39, CL-039-01..07 in
         WstxRequirements; verification TC-039-001..007): named strategies, the
         directed-CQ rule, Highlight in Band Activity, the strategy editor popup and Auto
         strategy runs of WstxMcp::OperatingAutomation. Nothing here is an execution
         result.

         Decisions (operator design interview on #37 and comments on #39/#42, 2026-11-01;
         defaults chosen by the implementing CR where the record left a choice open,
         listed on #39):
         D1 One evaluator: the station evaluates every strategy (Evaluate). The browser
            shows verdicts (POST /strategy/evaluate) and never evaluates a rule itself;
            Auto uses the same verdicts.
         D2 Data in this slice: worked status from the internal log (call and 4-character
            grid, ever or on this band and mode, WstxContact::WorkedBeforeQuery); the
            continent, distance and azimuth of a station come from the grid in its
            message (ContinentOfGrid; none without a grid). cty.dat (DXCC, CQ/ITU zone,
            new DXCC, rarest) is not available yet (CL-039-07).
         D3 Treat 73 as CQ: an RR73 or 73 that ends another station's QSO counts as
            calling for message type cq, in Highlight and Auto; Auto then keeps my Tx
            frequency (Hold Tx) so the answer never lands on the final 73.
         D4 Auto roles in the first version: Auto Call (answer the best matching CQ),
            Auto CQ (call CQ, answer the best caller) and Alternate (switch between them
            after switch_after consecutive tries without a contact).
         D5 No QSO or time limit is offered: the Tx watchdog bounds Auto
            (WatchdogFromOperator). The browser's Auto sends the WstxMcp run bounds at
            their maxima (max_contacts 100, max_run_minutes 480).
         D6 Skip after N: a station given up after skip_after partner periods without an
            answer is skipped for the rest of the run; the run goes on (no stop).
         D7 Manual intervention ends Auto (the existing WstxMcp contact_changed stop); a
            second Auto click starts it again. The first Auto use in a page session asks
            for confirmation once.
         D8 Out (operator decision on #42): band hopping, also as a suggestion; Rapid
            RR73; unauthenticated UDP control; shell-command alerts. */

    enum def MessageType { enum cq; enum directed_cq; enum to_me; enum signoff; }
    enum def NewScope { enum ever; enum band; }
    enum def ConditionKind {
        enum 'message'; enum new_call; enum new_grid; enum continent; enum distance_km;
        enum azimuth_deg; enum snr_db; enum dt_s; enum audio_hz; enum call; enum cq_target;
        enum band;
    }
    enum def SortOrder { enum strongest; enum weakest; enum furthest; enum newest; }
    enum def AutoRole { enum call; enum cq; enum alternate; }
    attribute def Condition {
        attribute kind : ConditionKind;
        attribute negate : Boolean;
        doc /* Wire keys: {kind, negate} plus value (message: MessageType; new_call,
             new_grid: NewScope), or values (continent: unique AF AN AS EU NA OC SA; call:
             unique 1..13 of A-Z 0-9 /, a prefix match on the sender's call; cq_target:
             unique 1..4 of A-Z 0-9, the word after "CQ "; band: unique ADIF band names,
             stored lower case), 1..32 entries; or min and max (null or a number, at least
             one set; distance_km 0..20038, azimuth_deg 0..360 where min > max wraps
             through north, snr_db -50..49, dt_s -7.5..7.5, audio_hz 0..3500; min <= max
             otherwise; bounds inclusive). Exactly these keys.
             Holds (before negation), for a decoded standard message from a resolved call:
             message cq: a CQ (to token "CQ" or "CQ x"), or with treat_73_as_cq an RR73/73
             to a call other than mine; directed_cq: "CQ x"; to_me: to my call; signoff:
             exchange RR73 or 73. new_call ever: the sender is not in the log; band: not
             worked on this band and mode. new_grid: as new_call for the message's grid
             square (no grid: false). continent: ContinentOfGrid of the message grid is
             listed (no grid: false). distance_km/azimuth_deg: great circle from my locator
             to the message grid in whole km / whole degrees (no grid: false). snr_db,
             dt_s, audio_hz: the record's value (unknown: false). call: a listed prefix
             starts the sender's call. cq_target: a CQ whose target is listed. band: the
             station band (CAT dial band, else the operating selection band) is listed.
             negate true inverts the result. */
    }
    attribute def Strategy {
        attribute name : String;
        attribute sort : SortOrder;
        attribute treat73AsCq : Boolean;
        attribute applyToCallers : Boolean;
        attribute skipAfter : Integer;
        attribute autoRole : AutoRole;
        attribute switchAfter : Integer;
        assert constraint skipRange { skipAfter >= 1 and skipAfter <= 20 }
        assert constraint switchRange { switchAfter >= 1 and switchAfter <= 20 }
        doc /* Wire keys exactly name (1..32 printable ASCII, no leading/trailing space,
             unique ignoring case), rules (1..8, each {conditions: 0..12 Condition}; rule
             order is priority, rule 1 highest; an empty rule holds for every message),
             sort, treat_73_as_cq, apply_to_callers, skip_after, auto_role, switch_after. */
    }
    attribute def StrategyConfiguration {
        attribute continent : String[0..1];
        attribute active : String[0..1];
        attribute highlight : Boolean;
        attribute strategiesMax : Integer = 16;
        doc /* Wire keys exactly continent (null: derived from the locator, else one of
             the seven codes: my continent for the directed-CQ rule), active (null or the
             name of a listed strategy), highlight, strategies (0..16 Strategy). Persisted
             as strategy.json beside profile.json: {schema_version 1, profile_id, revision,
             configuration}, written atomically like udp.json; missing: the default
             {null, null, false, []} at revision 0; foreign, malformed or larger than
             262144 bytes: configuration null with configuration_error
             invalid_configuration until a PUT replaces it. */
    }
    calc def ContinentOfGrid {
        in grid : String;
        return continent : String[0..1];
        doc /* The centre of a 4- or 6-character locator (lat, lon) as the browser computes
             it, then: lat < -60 AN; -170 <= lon < -30: NA when lat > 12 or (lon < -77 and
             lat > 7), else SA; -30 <= lon < 60 and lat >= 35: AS when lon > 40 and
             lat < 42, else EU; -30 <= lon < 52 and lat < 37: AS when lon > 33 and
             lat > 12, else AF; (lat >= -11 and lon >= 60) or lat >= 35: AS; else OC.
             A coarse rectangle rule until cty.dat is available. */
    }
    calc def DirectedCqRule {
        in target : String;
        in myContinent : String[0..1];
        in senderContinent : String[0..1];
        return addressedToMe : Boolean;
        doc /* The hard rule, applied before any strategy: a CQ "CQ x" with x one of the
             seven continent codes is addressed to me only when x is my continent; "CQ DX"
             only when both continents are known and differ (a CQ DX from my own continent,
             or from an unknown one, is not for me); any other target (TEST, POTA, a
             number, a country) is not continent-directed: Highlight leaves it to the
             rules, and Auto answers it only when the matched rule has a non-negated
             cq_target condition listing that target (AutoTarget), so a country-directed
             CQ such as CQ JA is never answered by default. A CQ not addressed to me is greyed in Band Activity, never matches
             a rule and is never answered by Auto. My continent unknown: every continent-
             directed CQ and CQ DX is greyed. */
    }
    attribute def Verdict {
        attribute sequence : Integer;
        attribute rank : Integer[0..1];
        attribute grey : Boolean;
        doc /* One per decoded standard record with a resolved sender (others have none):
             grey per DirectedCqRule; else rank = index (0-based) of the first rule all of
             whose conditions hold, null when none. why (explain only): "matches rule n",
             "no match (rule n: <first failing condition>; ...)" or "CQ x is not
             addressed to my continent (c)". Display order: rank ascending, then the sort
             (strongest: SNR descending, weakest: SNR ascending, furthest: distance
             descending, newest: sequence descending; unknown values last), then sequence;
             records without a rank follow in sequence order. */
    }
    attribute def StrategyHttp {
        attribute bodyBytesMax : Integer = 32768;
        attribute evaluateRecordsMax : Integer = 2048;
        doc /* GET /strategy (operating access, no query, empty body): {v 1, profile_id,
             boot_id, revision, configuration (or null), configuration_error, my_continent
             (configured, else derived; null when unknown), derived_continent}.
             PUT /strategy {v, profile_id, boot_id, expected_revision, configuration}:
             exact keys; same Origin/authorization/media/size rules and refusal codes as
             PUT /udp (400 invalid_request with the field, unsupported_version, 403
             wrong_profile, 409 state_conflict boot_id, 409 stale_revision, 409
             state_conflict active when the active name would change while an Auto
             strategy run is active); returns the snapshot with revision + 1.
             POST /strategy/evaluate {v, profile_id, boot_id, source_id, job_id,
             generation, first_sequence, next_sequence (0 <= next - first <= 2048),
             strategy (null: the saved active strategy, else a draft Strategy), explain}:
             the verdicts of the retained live records [first, next) of exactly that live
             job (another job: 409 stale_request job_id; no active strategy: 409
             not_configured strategy) in display order: every one when explain, else only
             those with a rank or grey. Never changes station state. */
    }
    attribute def HighlightView {
        doc /* Highlight on (configuration highlight with an active strategy): after a
             period is complete (or at most every 15 s while it loads) the browser asks
             POST /strategy/evaluate for the shown sequences of the current live identity
             once; matching rows get the strategy mark and rule number and move to the top
             of their period block in display order; greyed rows are dimmed and struck
             through; other rows keep the ActivityOrdering. Highlight off: no evaluation
             request and no mark. Choosing a strategy or toggling Highlight is one PUT
             /strategy; it never restarts receive. */
    }
    attribute def StrategyEditor {
        doc /* The edit (pencil) popup (a modal dialog carrying its own HALT with the top-bar HALT's
             action and enabled state; receive keeps running): choose, add, duplicate and
             delete strategies; name; rules with conditions (kind, not, value) in priority
             order; sort; Treat 73 as CQ; Auto role, switch after, skip after, Auto CQ
             answers only matching callers. The live preview evaluates the unsaved draft
             against the latest period (POST /strategy/evaluate with explain, 400 ms after
             an edit) and shows each decode's rank and why. Save sends one PUT /strategy
             and applies at once (also to a running Auto run); the edited strategy becomes
             active when none is. My continent is set in Settings > General
             (StrategyConfiguration continent, saved by PUT /strategy). */
    }
    attribute def AutoStrategyRun {
        doc /* The Auto button: the first use in a page session asks once (popup naming the
             strategy, the role and the watchdog); then AutomationCommand configure with
             {modes [current mode], ranking first_seen, min_snr_db null, empty call lists,
             max_contacts 100, max_unanswered_periods 20, completion_action
             next_candidate, max_run_minutes 480, strategy true} and start with the shown
             safety revision. While the run is active the button shows its state (waiting,
             CQ, the partner call), the strategy cannot be switched, and a click sends stop.
             The browser itself never sends enable_tx for Auto.
             At the station a strategy run (WstxMcp::OperatingAutomation with strategy
             true) needs the active strategy at start (else not_configured strategy) and
             reads it at every step (none: stop strategy_missing). Role Call or Alternate
             starts as Auto Call, Cq as Auto CQ; a saved role other than alternate applies
             at the next step.
             Auto Call (waiting): on each fresh complete publication the candidates are
             the verdicts with a rank, cq-like (D3), not greyed, a CQ target other than a
             continent or DX only when the matched rule asks for it with a non-negated
             cq_target condition, a sane call (SaneCall),
             not mine, not completed or skipped in this run, one per call, in display
             order; the first is selected (select_row) and armed (enable_tx); an RR73/73
             candidate keeps the previous Tx frequency (set_frequency). No candidate: one
             try.
             Auto CQ (waiting in role cq): enable_tx with no contact in progress (a new
             own CQ, calling_cq). On each fresh partner-parity publication the callers are
             the messages to my call that are not RR73/73 (no tailender after their sign-
             off), from a sane, not completed or skipped call, matching the strategy only
             when apply_to_callers, in display order (all rank 0 otherwise); the first is
             selected (the armed CQ becomes that contact). No caller: one try.
             Alternate: switch_after consecutive tries switch Call -> CQ or CQ -> Call
             (the CQ is cancelled); a contact resets the tries.
             In a contact: completion counts and returns to waiting (CQ again in role
             cq); skip_after partner periods without progress give the station up (D6),
             disarm and cancel the contact and count a try. All other WstxMcp stops
             (halted, context, authority, time, contact changed, transmit stopped) are
             unchanged; a disarm by the Tx watchdog stops tx_watchdog. */
    }
    calc def SaneCall {
        in call : String;
        return sane : Boolean;
        doc /* At least 3 characters with a digit and a letter, not ending /R (rover). */
    }
    attribute def WatchdogFromOperator {
        doc /* The Tx watchdog counts from the last operator action and is never paused or
             reset by automation. Only a human action in the browser is an operator
             action: an Enable Tx, any accepted ContactCommand or an Auto start sent by
             the browser (cookie session, not an MCP tool call). Never operator actions:
             commands of a run (select_row, set_frequency, enable_tx, cancel, disarm), any
             MCP request (also starting or restarting a run) and any UDP command (Reply,
             Free Text). Such an enable_tx arms with the watchdog already counting from
             the last browser action and is refused tx_watchdog when that time is spent
             (until a human acts in the browser); an MCP-started run is bounded by it; a changed message text of a contact armed by
             automation does not reset it. Halt from any source stops the run; grant,
             clock, period and safety-revision checks are unchanged. */
    }

    dependency storeClause from StrategyConfiguration to WstxRequirements::'CL-039-01';
    dependency evaluateClause from Verdict to WstxRequirements::'CL-039-02';
    dependency directedClause from DirectedCqRule to WstxRequirements::'CL-039-03';
    dependency highlightClause from HighlightView to WstxRequirements::'CL-039-04';
    dependency editorClause from StrategyEditor to WstxRequirements::'CL-039-04';
    dependency autoClause from AutoStrategyRun to WstxRequirements::'CL-039-05';
    dependency watchdogClause from WatchdogFromOperator to WstxRequirements::'CL-039-06';
    dependency automationPath from AutoStrategyRun to WstxMcp::OperatingAutomation;
    dependency watchdogOwner from WatchdogFromOperator to WstxContact::TxWatchdog;
}

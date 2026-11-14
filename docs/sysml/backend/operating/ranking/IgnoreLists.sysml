package WstxIgnoreLists {
    private import ScalarValues::*;
    private import WstxRequirements::'FR-026';
    private import WstxRequirements::ImplementationState;
    private import ModelBindings::ImplementedIn;
    private import WstxRankingPart::RankingService;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import WstxRequirements::AutomationState;
    private import ModelBindings::TestedBy;
    private import RequirementDerivation::*;

    attribute def IgnoreListsRule {
        doc /* A sender is ignored when an entry of the permanent list (configuration
             ignore_calls) or of the session list matches its call (the entry form and the
             matching of CL-042-02). The session list lives in
             station memory only (never persisted; a station restart empties it): at most 64
             entries in the order added, each {entry, band, expiry}, the band being the station
             band (CAT dial band, else the operating selection band; null when unknown) and the
             expiry session_ignore_minutes after the add, both taken when added (adding a listed
             entry again renews them and moves it last; adding a 65th entry drops the oldest).
             An entry ends at its expiry.
             Band change: any change of the station band (also to or from unknown) empties the
             session list, so it is empty before the next evaluation or run step on the new
             band.
             Effect: an ignored sender's verdict has rank null and is not greyed, why "<call> is
             ignored (session list)" or "(permanent list)" for an exact entry and "<call> is
             ignored (session list: <entry>)" or "(permanent list: <entry>)" for a pattern; the
             session list is named before the permanent list when the sender is on both, and in
             one list the exact entry before a pattern; so it
             gets no mark, a run never selects it, also when it calls me. A contact already in
             progress is not changed by ignoring its partner. A manual Reply, Select or
             double-click of an ignored station is still the operator's explicit choice and is
             not refused. */
    }

    attribute ignoreListsRule : IgnoreListsRule;

    satisfy 'CL-042-02' by ignoreListsRule;

    requirement 'CL-042-02' {
        subject ranking : RankingService;
        doc /* Two-tier ignore lists govern the strategy: a permanent list of entries (saved in
             the strategy configuration) and a session list in station memory (POST
             /strategy/ignore), whose entries end after the configured minutes (1..720, default
             30) and which the station empties on any change of the station band.
             An entry of either list is a call or a pattern: 1..13 characters of A-Z, 0-9, /
             and *, with at least one character other than *, so *, ** and *** are refused.
             * stands for any run of characters, the empty run included, anywhere in the entry
             and any number of times; every other character matches itself. An entry matches a
             sender when it matches the whole resolved call, so an entry without * matches
             exactly that call. The permanent list refuses a duplicate entry; adding an entry
             to the session list again renews it and moves it last.
             An ignored sender is never a candidate or a caller: it gets no mark and a run
             never selects it; a contact already in progress and a manual Reply or Select are
             not changed. Its why text names the entry when the entry is a pattern. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/strategy.rs; server/src/contest.rs; server/src/automation.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js; client/recording.css";
        }
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-042-02';
    }

    verification 'TC-125-001' {
        doc /* TC-125-001 — Pattern entries in the ignore lists
             CL-042-02
             Setup: hand-authored rows (CQs and callers); the station HB9BLA on 40m; the
             actual station router and contact engine on the recording hardware double
             (virtual UTC; no audio, PTT or radio).
             (a) Validation. The pattern star-slash-MM (a * and then /MM), BY*, K*1ABC and
             *K1ABCDEFGHI* (13 characters) are accepted in both lists. *, **, ***, k1abc,
             14 characters, the empty entry and K1?BC are refused with their fields
             (ignore_calls[i] or call). A duplicate BY* in ignore_calls is refused with
             ignore_calls[i]. Adding BY* to the session list twice renews it and moves it
             last, as for an exact call (guard of the rule before patterns).
             (b) Matching. Star-slash-MM matches DL1ABC/MM and not DL1ABC/M. BY* matches BY1AA
             and BYA1B and not ABY1A. *K1ABC* matches K1ABC and K1ABC/P. K1ABC matches only K1ABC.
             (c) Compound calls. EA8/DL1ABC is matched by EA8/ followed by a * and by a *
             followed by /DL1ABC, and not by DL1*.
             (d) Why texts. "BY1AA is ignored (permanent list: BY*)", "JA1ABC is ignored
             (session list: JA*)" and "K1ABC is ignored (session list)"; the session list is
             named before the permanent list, and an exact entry before a pattern.
             (e) A caller or a CQ matched by a pattern gets no rank and is not called by Auto.
             A contest strategy gives the sender rank null with the why text naming the
             pattern, and a pounce on it gets no answer and no key.
             (f) A stored schema 4 file with exact entries reads unchanged (guard, green on both).
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-042-02';
        }
        @TestedBy {
            test = "server/src/strategy_tests.rs";
        }
    }
}

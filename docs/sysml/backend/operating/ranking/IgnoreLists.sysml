package WstxIgnoreLists {
    private import ScalarValues::*;
    private import WstxRequirements::'FR-026';
    private import WstxRequirements::ImplementationState;
    private import ModelBindings::ImplementedIn;
    private import WstxRankingPart::RankingService;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import RequirementDerivation::*;

    attribute def IgnoreListsRule {
        doc /* A sender is ignored when its call (exactly, not as a prefix) is on the permanent
             list (configuration ignore_calls) or on the session list. The session list lives in
             station memory only (never persisted; a station restart empties it): at most 64
             entries in the order added, each {call, band, expiry}, the band being the station
             band (CAT dial band, else the operating selection band; null when unknown) and the
             expiry session_ignore_minutes after the add, both taken when added (adding a listed
             call again renews them and moves it last; adding a 65th call drops the oldest). An
             entry ends at its expiry.
             Band change: any change of the station band (also to or from unknown) empties the
             session list, so it is empty before the next evaluation or run step on the new
             band.
             Effect: an ignored sender's verdict has rank null and is not greyed, why "<call> is
             ignored (session list)" or "(permanent list)" (session first when on both); so it
             gets no mark, a run never selects it, also when it calls me. A contact already in
             progress is not changed by ignoring its partner. A manual Reply, Select or
             double-click of an ignored station is still the operator's explicit choice and is
             not refused. */
    }

    attribute ignoreListsRule : IgnoreListsRule;

    satisfy 'CL-042-02' by ignoreListsRule;

    requirement 'CL-042-02' {
        subject ranking : RankingService;
        doc /* Two-tier ignore lists govern the strategy: a permanent list of calls (saved in
             the strategy configuration) and a session list in station memory (POST
             /strategy/ignore), whose entries end after the configured minutes (1..720, default
             30) and which the station empties on any change of the station band. An ignored
             sender (exact call) is never a candidate or a caller: it gets no mark and a run
             never selects it; a contact already in progress and a manual Reply or Select are
             not changed. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/strategy.rs; server/src/automation.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js; client/recording.css";
        }
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-042-02';
    }
}

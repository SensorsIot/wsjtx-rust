package WstxIgnoreLists {
    private import ScalarValues::*;
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::'FR-010';
    private import WstxRequirements::'FR-020';
    private import WstxRankingControl::IgnoreLists;
    private import WstxRequirements::ImplementationState;
    private import WstxContact::'TC-042-002';
    private import WstxContact::'TC-042-003';

    dependency ignoreClause from IgnoreLists to WstxIgnoreLists::'CL-042-02';

    requirement 'CL-042-02' {
        doc /* Two-tier ignore lists govern the strategy: a permanent list of calls (Settings > General, saved in the strategy configuration) and a session list in station memory (Band Activity right-click "Ignore <call>" / "Stop ignoring <call>", POST /strategy/ignore), whose entries end after the configured minutes (1..720, default 30) and which the station empties on any change of the station band. An ignored sender (exact call) is never a candidate or a caller: it gets no mark and a run never selects it; a contact already in progress and a manual Reply or Select are not changed. A saved configuration from before the lists reads with empty lists and 30 minutes. Details: WstxRankingControl::IgnoreLists. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/automation.rs; server/src/contact_http.rs; server/src/main.rs; client/contact.js; client/recording.css";
    }
    dependency CL_042_02_to_FR_007 from 'CL-042-02' to 'FR-007';
    dependency CL_042_02_to_FR_010 from 'CL-042-02' to 'FR-010';
    dependency CL_042_02_to_FR_020 from 'CL-042-02' to 'FR-020';
    dependency CL_042_02_verified_by_TC_042_002 from 'CL-042-02' to 'TC-042-002';
    dependency CL_042_02_verified_by_TC_042_003 from 'CL-042-02' to 'TC-042-003';
}

package WstxAlert {
    private import ScalarValues::*;
    private import WstxRankingControl::Alert;
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::'FR-020';
    private import WstxRequirements::ImplementationState;
    private import WstxContact::'TC-042-006';
    private import WstxContact::'TC-042-007';

    dependency alertClause from Alert to WstxAlert::'CL-042-04';

    requirement 'CL-042-04' {
        doc /* Alert has no setting: for each new candidate of the active strategy (an ignored sender, a directed CQ not for me and a caller of my call never alert), the station records an alert (time, call, message, strategy name, band, mode, SNR, DXCC entity) in a history of the last 100 alerts in station memory (kept across page reloads, empty after a station restart), at most one per call and band in 10 minutes, and announces it to the browser; the browser plays a short sound and/or shows a browser notification as the operator chose in Settings > General (both off by default; the notification permission is asked only on the operator's click; no sound while the page is hidden), and lists the history with a Clear. An alert never transmits or changes a contact or automation run. An MCP client may read the history (wstx_read alerts), not clear it. Details: WstxRankingControl::Alert; WstxMcpInterface::ToolCatalog. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/strategy.rs; server/src/contact_http.rs; server/src/main.rs; server/src/mcp.rs; client/contact.js";
    }
    dependency CL_042_04_to_FR_007 from 'CL-042-04' to 'FR-007';
    dependency CL_042_04_to_FR_020 from 'CL-042-04' to 'FR-020';
    dependency CL_042_04_verified_by_TC_042_006 from 'CL-042-04' to 'TC-042-006';
    dependency CL_042_04_verified_by_TC_042_007 from 'CL-042-04' to 'TC-042-007';
}

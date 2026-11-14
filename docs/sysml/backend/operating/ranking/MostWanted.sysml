package WstxMostWanted {
    private import ScalarValues::*;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-007';
    private import WstxRequirements::ImplementationState;
    private import WstxRankingControl::MostWantedList;
    private import WstxContact::'TC-039-006';

    dependency mostWantedClause from MostWantedList to WstxMostWanted::'CL-039-10';

    requirement 'CL-039-10' {
        doc /* The value order can use the Club Log Most Wanted list: Settings shows "List from <date>" with its entries, unmapped numbers and source attribution, and one button Update Most Wanted that fetches it once on the operator's click; there is no upload, a failed download keeps the list and shows the reason in one line; it is validated, stored in the profile folder and mapped to cty.dat entities by ADIF number (an unmapped number is ignored and counted). No automatic refresh and nothing bundled (operator decision, #39 comment 6685317139; Club Log states no terms, recorded in WstxStrategy D12). Everything works without a list (strongest first). The list is read off the station step. Details: WstxRankingControl::MostWantedList, ValueOrder. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/most_wanted.rs; server/src/strategy.rs; client/contact.js";
    }
    dependency CL_039_10_to_FR_007 from 'CL-039-10' to 'FR-007';
    dependency CL_039_10_verified_by_TC_039_031 from 'CL-039-10' to 'TC-039-031';
    dependency CL_039_10_verified_by_TC_039_006 from 'CL-039-10' to 'TC-039-006';

    verification 'TC-039-031' {
        doc /* TC-039-031 — Most Wanted list: parsing, mapping, routes
             CL-039-10
             Setup: hand-written list text (no network); the bundled cty.dat; the actual station router on a disposable HTTPS profile; a test seam in place of the HTTP fetch.
             Steps: parse valid and refused lists; map every bundled cty.dat entity; Update Most Wanted (the download route) with a fake fetch: a list with an unknown number, a failure, a reply that is no list; read the snapshot; open a new owner; POST to the former upload route; POST with the MCP cookie.
             Expected: the refused lists parse to nothing; every bundled entity has an ADIF number, exactly 340 distinct numbers; status {date, entries, unmapped 1}; the new owner reads it; each failure is 502 download_failed with its reason and changes nothing; the upload route is gone (405 or 404); the MCP cookie is refused 401.
             2 — Isolated automated tests; Windows development PC, no network. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-039-10';
        }
        attribute executable : String = "server/src/strategy_tests.rs";
    }
}

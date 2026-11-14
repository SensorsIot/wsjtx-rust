package WstxMostWanted {
    private import ScalarValues::*;
    private import ModelBindings::Automation;
    private import WstxRequirements::AutomationState;
    private import WstxRequirements::'FR-026';
    private import WstxRequirements::ImplementationState;
    private import ModelBindings::ImplementedIn;
    private import ModelNotes::NotStated;
    private import WstxRankingPart::RankingService;
    private import ModelBindings::Status;
    private import ModelBindings::TestedBy;
    private import RequirementDerivation::*;

    attribute def MostWantedListRule {
        @NotStated {
            what = "how ranking obtains the profile folder that holds most_wanted.json: "
                + "ranking has no connection to the profile files";
        }
        doc /* Parsed exactly: an object of 1..1000 keys, each a positive integer in text, each
             value a positive integer below 10000 in text or as a number, no number twice; else
             the update fails, nothing changed.
             cty.dat has no ADIF numbers: the table most_wanted::ENTITIES maps cty.dat entity
             full names to ADIF numbers (the 340 current entities; WAE-only entities, Sicily,
             African Italy, Bear Island, Shetland Islands, European Turkey and Vienna Intl Ctr,
             carry their DXCC parent's number). A number of the list without a table entry is
             ignored and counted as unmapped in the status. An entity not in the table or not on
             the list has no rank (ValueOrder sorts it after the listed ones). A list once
             fetched stays until the next update. The file is read off the station step (the
             first GET /strategy, POST /strategy/evaluate or selection, on a blocking thread).
             An unreadable file: no list, most_wanted_unreadable true. */
    }

    attribute mostWantedListRule : MostWantedListRule;

    satisfy 'CL-039-10' by mostWantedListRule;

    requirement 'CL-039-10' {
        subject ranking : RankingService;
        doc /* The value order can use the Club Log Most Wanted list: it is validated, stored in
             the profile folder and mapped to cty.dat entities by ADIF number (an unmapped
             number is ignored and counted). No automatic refresh and nothing bundled (Club Log
             states no terms). Everything works without a list (strongest first). The list is
             read off the station step. */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/most_wanted.rs; server/src/strategy.rs; client/contact.js";
        }
    }
    #derivation connection {
        end #original ::> 'FR-026';
        end #derive ::> 'CL-039-10';
    }

    verification 'TC-039-031' {
        doc /* TC-039-031 — Most Wanted list: parsing, mapping, routes
             CL-039-10
             Setup: hand-written list text (no network); the bundled cty.dat; the actual station
             router on a disposable HTTPS profile; a test seam in place of the HTTP fetch.
             (a) Refused lists: they parse to nothing.
             (b) Every bundled cty.dat entity has an ADIF number: exactly 340 distinct numbers.
             (c) Update Most Wanted (the download route) with a fake fetch whose list has an
             unknown number: the status is {date, entries, unmapped 1}, and a new owner reads
             it.
             (d) A failing fetch, and a reply that is no list: each is 502 download_failed with
             its reason and changes nothing.
             (e) POST to the former upload route: the route is gone (405 or 404).
             (f) POST with the MCP cookie: refused 401.
             2 — Isolated automated tests; Windows development PC, no network. */
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-039-10';
        }
        @TestedBy {
            test = "server/src/strategy_tests.rs";
        }
    }
}

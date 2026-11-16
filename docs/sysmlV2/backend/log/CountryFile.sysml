package WstxCountryFile {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-011';
    private import WstxLogPart::LogService;
    private import WstxLogControl::CallEntity;
    private import WstxLogControl::CountryFileState;
    private import WstxLogControl::ReplaceCountryFile;
    private import WstxLogControl::EntityRequest;
    private import WstxLogControl::LogRefusal;
    private import WstxLogControl::LogLimits;
    private import WstxOperatingChain::WorkedSet;
    private import ModelNotes::FollowsSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    // ---- The entity of a call -------------------------------------------------------------

    requirement 'CL-055-01' {
        subject log : LogService;
        doc /* Log MUST resolve a call to its DXCC entity, with the continent, the zones
             and the position the country file gives for it, as WSJT-X does
             (EntityOfCall, CountryFile). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-055-01'; }

    action def EntityOfCall {
        in call : String;
        out entity : CallEntity[0..1];
        doc /* How an EntityRequest is answered from the country file in use.
             The call is read in upper case. An empty call, a call with a character
             outside ASCII and a call that ends in /MM or /AM have no entity.
             The effective prefix: endings after a "/" are taken off from the right
             while they are a digit, A, M, P, Q, R, QRP, FD, FF, AM, MM, LH, LT or LGT;
             of a call that then still has a "/", the shorter side is the prefix, and
             the left side when both are equally long.
             When the effective prefix is not the whole call, an exact entry of the
             file for the whole call decides.
             Otherwise the longest entry that begins the effective prefix decides; an
             exact entry counts only when it is as long as the whole call.
             A call that begins with KG4 and has neither three nor five characters is
             of the entity whose primary prefix is K.
             The answer is the entity with what the deciding entry says in its place
             for the CQ zone, the ITU zone, the continent and the position; the
             longitude is turned to positive east.
             The shown name is the name shortened as WSJT-X shortens it, with an entity
             that only the WAE list knows shown as its DXCC entity; the name itself
             stays the one of the file. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: AD1CCty lookup and "
                + "abbreviated_entity_name, Radio effective_prefix, and the display of "
                + "entities with the extra WAE entities off";
        }
    }

    attribute def CountryFile {
        doc /* The country file and how it is read.
             The file bundled with the station is cty.dat as WSJT-X at the behaviour
             baseline ships it.
             A line with fewer than seven ":" is skipped. Each other line begins an
             entity, whose entries follow up to a ";".
             An entry given a second time keeps the entity of its first place.
             An exact entry VER followed by eight digits is the version of the file.
             A file is refused, with the line of the entity counted from 1, for a
             number that cannot be read, a CQ zone above 40 or an ITU zone above 90,
             also in an entry, a continent that is none of Continent, a shown name that
             is not 1 to 40 printable ASCII characters, an entity without a primary
             prefix, and entries that do not end with ";". A file without an entity
             is refused with line 1. */
        @FollowsSource {
            reference = "AD1C cty.dat, the format of the country files of "
                + "country-files.com; WSJT-X at the behaviour baseline: AD1CCty load_cty";
        }
    }

    verification 'TC-055-001' {
        doc /* Calls resolved against known answers.
             Setup: the bundled country file, and country files written by hand.
             (a) The effective prefix of K1ABC is K1ABC; of EA8/K1ABC, K1ABC/EA8 and
             EA8/K1A it is EA8, each also with /P, /QRP and /P/QRP behind it; of W1AW/4
             it is W1AW; of DL/HB9BLA/M it is DL; of HB9BLA/LGT it is HB9BLA.
             (b) The bundled file, VER20250115 with 346 entities. HB9BLA and hb9bla:
             Switzerland, EU, zones 14 and 28. K1ABC: United States, shown U.S.A., NA,
             5 and 8, at 37.60 north and 91.87 west. DL1XYZ: Fed. Rep. of Germany,
             shown Germany. EA8ABC: Canary Islands, shown Canary Is., AF, 33 and 36.
             HB9BLA/P, HB9BLA/QRP and HB9BLA/P/QRP: Switzerland. W1AW/4: United States.
             DL/HB9BLA and HB9BLA/DL: Germany. EA8/K1ABC and K1ABC/EA8: Canary Islands.
             HB9BLA/MM and K1ABC/AM: none. KG4AB and W1AW/KG4: Guantanamo Bay, 8 and
             11. KG4ABC and KG4AB/P: United States. 3D2CR: Conway Reef. 3D2CR/P and
             3D2ABC: Fiji. 3D2AG/P: Rotuma Island, shown Rotuma Is. RA0DAA: Asiatic
             Russia, shown AS Russia, 19 and 33; RA0ABC: 18 and 32; RA9ABC: 17 and 30.
             KG4IJS/0: United States, 4 and 7. IT9ABC: Sicily, shown Italy. 4U1VIC:
             Vienna Intl Ctr, shown Austria. 2M0BDR: Shetland Islands, shown Scotland.
             GB3LER: Scotland. FO5ABC: French Polynesia, shown Fr.Polynesia. UA3ABC:
             European Russia, shown EU Russia. Q1ABC, an empty call and a call with a
             letter outside ASCII: none.
             (c) A file with the entities Alpha Islands, zones 10 and 20 at 10 north,
             and Beta with the primary prefix *BB. AA5Q: shown Alpha Is., CQ zone 10.
             AB5Q under the entry AB(3)[4]: zones 3 and 4. AA1X under the exact entry
             with the position 1.5/-2.5: 1.5 north, 2.5 east; AA1XY: 10 north. AC1A
             under AC{SA}: SA. AA2B under Beta's entry AA2: Beta with the prefix BB.
             AB, listed again under Beta: Alpha Islands. No version.
             (d) Refused with line 1: the continent XX; the entry X(a); entries without
             ";"; a text without an entity; the CQ zone 41; the ITU zone 91; the
             entries X(41) and X[91]; an empty name; a name of 41 characters; a name
             outside ASCII. Refused with line 3: a second entity with the ITU zone
             z. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-055-01'; }
        @TestedBy {
            test = "server/src/dxcc_tests.rs::"
                + "tc_055_001_effective_prefix_matches_wsjtx_unit_vectors; "
                + "server/src/dxcc_tests.rs::tc_055_001_known_answers_from_the_bundled_file; "
                + "server/src/dxcc_tests.rs::tc_055_001_overrides_and_refused_files";
        }
    }

    // ---- The operator's country file ------------------------------------------------------

    requirement 'CL-055-03' {
        subject log : LogService;
        doc /* Log MUST use, in the place of the bundled country file, a file the
             operator gives for the profile once it has read it without a fault, and
             return to the bundled file on request (ProfileCountryFile). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-011'; end #derive ::> 'CL-055-03'; }

    attribute def ProfileCountryFile {
        doc /* What the log does with a ReplaceCountryFile, and which file is in use.
             A text that reads as CountryFile is stored as cty.dat in the operator's
             folder, under the file's lock, written anew, made durable and put in place in one step.
             It is
             in use from then on, also after a station start, for every EntityRequest
             and every WorkedSet made afterwards.
             A text that does not read so is refused (LogRefusal::invalidCty) with the
             line; a text over LogLimits::countryFileBytesMax is refused
             (LogRefusal::invalidRequest); a file that cannot be stored is refused
             (LogRefusal::storageUnavailable). A refusal changes neither the stored
             file nor the file in use.
             An absent text takes the stored file away; the bundled file is in use.
             At station start a stored file that cannot be read, or does not read as
             CountryFile, is left as it is; the bundled file is in use and
             CountryFileState::uploadUnreadable says so. */
    }

    verification 'TC-055-003' {
        doc /* The operator's country file in the place of the bundled one.
             Setup: the station on a throw-away profile; the log is asked through the
             station service.
             (a) At first: bundled, VER20250115, 346 entities, nothing unreadable.
             HB9BLA: Switzerland. DL/HB9BLA: Germany. K1ABC/MM: none.
             (b) A file with the one entity Testland, its entries TT and HB, and the
             version VER20991231: uploaded, that version, 1 entity; cty.dat holds the
             text; HB9BLA: Testland.
             (c) A file with the continent XX and an empty text: invalidCty with line
             1. A number, and a text of 1048577 bytes: refused. cty.dat is unchanged.
             (d) After a station start: uploaded, HB9BLA: Testland.
             (e) An absent text: bundled, cty.dat gone, HB9BLA: Switzerland.
             (f) cty.dat holding "not a country file", then a station start: bundled,
             uploadUnreadable; cty.dat unchanged. */
        subject log : LogService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-055-03'; }
        @TestedBy {
            test = "server/src/logbook_http_tests.rs::"
                + "cty_upload_replaces_the_country_table_and_refusals_change_nothing";
        }
    }
}

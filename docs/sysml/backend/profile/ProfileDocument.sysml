package WstxProfileDocument {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-001';
    private import WstxRequirements::'FR-016';
    private import WstxRequirements::'FR-022';
    private import WstxClubLog::MostWantedQuery;
    private import WstxClubLog::MostWantedDownload;
    private import WstxCountryFiles::CtyQuery;
    private import WstxCountryFiles::CtyDownload;
    private import WstxCountryFile::CountryFile;
    private import WstxProfileAccess::*;
    private import WstxStrategies::StrategyForm;
    private import WstxStrategies::StrategyReading;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxProfilePart::PersistedProfile;

    doc /* The profile's functions: one station process for a profile, the start, the
         saved document and its save, the hidden store, the shack's folder and
         settings, the collections of settings, the creation of a profile, the
         endpoint ids and the profile of a radio's native connection. */

    requirement 'CL-005-01' {
        subject profile : PersistedProfile;
        doc /* Profile MUST hold a profile and its folder for one station process at a
             time, so that profiles run side by side, each in a process of its own
             (ProfileOwnership). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-022'; end #derive ::> 'CL-005-01'; }

    attribute def ProfileOwnership {
        doc /* The folder of a profile and who may use it.
             The folder is the one named when the station is started; a name that is
             not absolute counts from the working directory. The folder is taken by its
             real place, so that every other name of it is the same folder.
             The folder holds profile.json, which is ProfileDocument, the hidden store
             (StationMemory), the folder recordings, and the definition files and data
             files the other functions of the station keep there.
             The profile writes profile.json, a temporary file beside it while it
             saves, the hidden store, its lock file and the files of the folder
             recordings; every other file of the folder it leaves as it is.
             When the profile is opened it takes two locks and holds them until the
             station process ends, however it ends: one on the file .profile.lock of
             the folder, and one on the file named by the profileId and .lock in the
             folder wstx-rust-profile-locks of the account's local application data
             (LOCALAPPDATA), or of the temporary folder when the account has none.
             A lock that another process holds refuses the OpenRequest with
             OpenRefusal::profileInUse: the same folder under any name, and a copy
             of the folder with the same profileId.
             A lock that cannot be taken for another reason refuses it with
             OpenRefusal::resourceUnavailable.
             A lock file that a process left behind holds nothing: the profile can be
             opened again as soon as that process has ended.
             A station process has one profile, and a profile shares no file, no lock
             and no state with another profile but the shack's folder
             (ShackFolder). */
        @DiffersFromSource {
            what = "WSJT-X at the behaviour baseline keeps one lock file in the temporary "
                + "folder, named by the application and its rig name, and offers to "
                + "remove a lock that is left behind; the profile locks its folder and "
                + "its identity, and a lock left behind needs no removal.";
        }
    }

    requirement 'CL-005-04' {
        subject profile : PersistedProfile;
        doc /* Profile MUST refuse an OpenRequest or a CreateRequest it cannot carry out
             with its reason and leave the saved profile as it is (OpenProfile). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/main.rs"; }
    }
    #derivation connection { end #original ::> 'FR-022'; end #derive ::> 'CL-005-04'; }

    attribute def OpenProfile {
        doc /* How the profile answers an OpenRequest. The first of these that holds
             refuses it (OpenRefused, OpenRefusal); a refused request changes no file.
             resourceUnavailable: the folder does not exist, or profile.json cannot be
             opened or read.
             invalidProfile: profile.json is larger than
             ProfileLimits::profileFileMaxBytes or is not the JSON object ProfileDocument
             describes.
             unsupportedConnectionType: schemaVersion 1 with the connection type
             nativeFlex.
             unsupportedSchema: schemaVersion 2 without native, and every
             schemaVersion other than 1 and 2.
             invalidProfile: any other pairing of schemaVersion, connection type and
             native than the two of ProfileDocument, or a NativeIntent outside its rules.
             invalidProfile: a profileId that is no UUID of version 4 in lower case,
             a value of StationConfig
             outside the rule its definition gives, or an Endpoint outside its rules.
             profileInUse, resourceUnavailable: the locks of ProfileOwnership.
             invalidProfile: the largest ProfileSnapshot the profile could ever give
             is over ProfileLimits::profileHttpMaxBytes. The largest is taken with the
             origin of this station and the values of StationConfig at their longest, where each
             byte of the name, of
             the two devices and of the control endpoint takes two bytes.
             A device entry of AudioConfig that is no endpoint id ends no start
             (EndpointIds).
             A document of a managed radio without radio is read with RadioConfig::agc
             slow; the file changes with the next save.
             Only profile.json is read: a temporary file left beside it is not used. */
    }

    requirement 'CL-005-02' {
        subject profile : PersistedProfile;
        doc /* Profile MUST keep the identity and the station config of a profile
             across every stop of its station, and answer a save as done only
             when the new document is durable (SaveSettings). */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/main.rs"; }
    }
    #derivation connection { end #original ::> 'FR-016'; end #derive ::> 'CL-005-02'; }

    attribute def SaveSettings {
        doc /* What the profile does with a SaveProfile. The first of these that holds
             refuses it (SaveRefused).
             invalidSettings with the field: the first value of StationConfig outside
             the rule its definition gives. The values are looked at in the order
             displayName, audio.inputDevice, audio.outputDevice, control.mode,
             control.rig, control.endpoint, control.ptt, radio, then the values of
             transmit and receive in the order of their definitions; a value is named by its key in
             the file,
             one under a part as the part's key, a dot and the value's name
             (transmit.tuneSeconds). radio is named when RadioConfig::agc is present for
             a radio that is not managed.
             invalidSettings with the field: on a profile of the native connection, a
             value NativeProfile does not allow.
             audioDeviceNotEndpoint with the field: EndpointIds.
             storageUnavailable: the file cannot be written.
             A StationConfig without RadioConfig::agc for a managed radio takes the
             saved one, or slow when none is saved.
             A save that is not refused writes the document with the new station
             config: the whole file anew beside
             profile.json, made durable, and put in its place in one step. Only then
             is the save answered, with the new ProfileSnapshot.
             Until the file is in its place the saved profile is the one before, in the
             file and in every ProfileSnapshot; a save that fails there leaves no file
             behind. A station process that stops while it saves leaves the whole
             document of before or the whole new one.
             profileId, endpoint, connectionType and native are the same after every
             save.
             The station config has one maintainer, the browser of its station: saves
             are carried out one after the other, and the later one stands. */
        @DiffersFromSource {
            what = "WSJT-X at the behaviour baseline writes each setting to its "
                + "configuration file as it changes; the profile saves all settings of "
                + "the station together.";
        }
    }

    requirement 'CL-005-06' {
        subject profile : PersistedProfile;
        doc /* Profile MUST keep the records the parts of its station hand over across
             every stop of the station, and show them in no menu (KeepMemory). */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-016'; end #derive ::> 'CL-005-06'; }

    attribute def KeepMemory {
        doc /* What the profile does with the hidden store (StationMemory).
             When the profile is opened it reads the store and gives it as
             MemorySnapshot. A store that was never kept gives every record as its
             definition gives it.
             A SaveMemory is kept whole and made durable before it is answered with
             the new MemorySnapshot. A store that cannot be kept is answered with the
             MemorySnapshot of before, and the kept store stays as it was.
             Keeping the hidden store changes neither the document nor its
             revision.
             The profile reads no record: what a record means is its part's.
             The store is the file memory.json beside profile.json: one JSON object of
             UTF-8 with the key schemaVersion, 1, and one key for each part that has
             records (radio for RadioRecords, audio for AudioRecords, station for
             StartupRecords). It is written as
             the document is: the whole file anew, made durable, and put in its place
             in one step.
             A file that cannot be read, or is of another schema, gives every record
             as its definition gives it, and MemorySnapshot::unreadable is true; the
             file is left as it is until the next SaveMemory is kept in its place. */
    }

    verification 'TC-022-001' {
        doc /* The settings of a profile: what is taken, what is refused, and that a save of one
             profile touches no other. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-005-02'; verify 'CL-005-05'; verify 'CL-044-05'; }
        @TestedBy {
            test = "tests/profiles.test.cjs; "
                + "server/src/profile_tests.rs::"
                + "exact_nullable_schema_rejects_omission_duplicates_and_unknown_keys; "
                + "server/src/profile_tests.rs::"
                + "settings_validation_uses_utf8_bytes_and_independent_audio_control_domains";
        }
    }

    verification 'TC-022-002' {
        doc /* A saved profile outlasts its station, and a file that is no profile is refused and
             left as it is. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-005-02'; verify 'CL-005-04'; verify 'CL-005-05'; }
        @TestedBy {
            test = "tests/profiles.test.cjs; "
                + "server/src/profile_tests.rs::"
                + "storage_commit_point_and_os_ownership_survive_reopen; "
                + "server/src/profile_tests.rs::"
                + "save_failures_and_interruptions_preserve_the_defined_commit_point";
        }
    }

    verification 'TC-022-003' {
        doc /* One station process for a profile, and what a start that cannot be carried out leaves
             behind. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-005-01'; verify 'CL-005-04'; }
        @TestedBy {
            test = "tests/profiles.test.cjs; "
                + "server/src/profile_tests.rs::"
                + "storage_commit_point_and_os_ownership_survive_reopen";
        }
    }

    requirement 'CL-005-07' {
        subject profile : PersistedProfile;
        doc /* Profile MUST keep the settings and files the shack's stations share in
             one folder of the shack, change a shared file only under its lock and
             from its revision, and give its station a change another station has made
             (ShackFolder, SaveShackSettings). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-016'; end #derive ::> 'CL-005-07'; }

    attribute def ShackFolder {
        doc /* The folder the shack's stations share, and how a station uses it.
             It is the folder WSTX-Rust\shack in the account's local application
             data (LOCALAPPDATA), or the folder OpenRequest::shackFolder names;
             a name that is not absolute counts from the working directory. A folder
             that does not exist is made at station start; one that cannot be made or
             used refuses the OpenRequest with OpenRefusal::resourceUnavailable.
             It holds shack.json (ShackDocument), the strategies file
             (StrategiesFile), and the files the functions of the stations keep there:
             the logbook and the operator's country file (the log's) and the Most
             Wanted list (ranking's).
             A station changes a file of the folder only while it holds that file's
             lock, for the change alone; a station waits while another holds it. A
             shared file with a revision is changed only from its revision
             (SaveShackSettings, CollectionRule).
             When another station has changed shack.json or the strategies file,
             the profile reads it anew and gives its snapshot (ShackSnapshot,
             DefinitionsSnapshot); how soon is a value of the code. */
    }

    attribute def SaveShackSettings {
        doc /* What the profile does with a SaveShack, and how shack.json is read.
             The first of these that holds refuses it (SaveRefused).
             invalidSettings with the field: the first value of ShackSettings
             outside the rule its definition gives, by its key in the file: callsign,
             locator, continent, cqWords, then the values of spots, udp, auto, qso,
             frequencies and log, each named
             as the part's key, a dot and the value's name.
             revisionConflict: expectedRevision is not the revision of shack.json.
             storageUnavailable: the file cannot be written.
             A save that is not refused writes shack.json with the new settings and
             the revision one higher, under the file's lock: the whole file anew, made
             durable, and put in its place in one step. Only then is it answered, with
             the new ShackSnapshot. A refused save changes nothing.
             At station start the profile reads shack.json. Without the file the
             settings are as their definitions give them, at revision 0. A file that
             cannot be used gives those settings with ShackSnapshot::unusable true,
             and is left as it is until the next save is written in its place. */
    }

    verification 'TC-022-011' {
        doc /* The shack's settings, shared by the shack's stations. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-005-07'; }
        @TestedBy {
            test = "tests/profiles.test.cjs; "
                + "server/src/profile_tests.rs::"
                + "settings_validation_uses_utf8_bytes_and_independent_audio_control_domains";
        }
    }

    requirement 'CL-039-01' {
        subject profile : PersistedProfile;
        doc /* Profile MUST create, change and delete a member of a settings collection only
             by its key and within the rules of the member's part, and keep the saved
             strategies across every stop of the station (CollectionRule,
             StrategiesFile). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-016'; end #derive ::> 'CL-039-01'; }

    attribute def CollectionRule {
        doc /* What the profile does with a CreateEntry, an UpdateEntry, a DeleteEntry
             (SettingsCollection) and a ResetFrequencies, after which
             workingFrequencies holds WSJT-X's default list alone.
             The member is held to the rules its part states for it and for its
             collection; the profile applies them and has no rules of its own for a
             member. A member outside them is refused with invalidSettings and one
             value that is outside (SaveRefused::field).
             A CreateEntry is refused with entryExists when its key is held, and with
             collectionFull when the collection holds as many members as its rules
             allow. An UpdateEntry is refused with entryUnknown when its key is not
             held, and with entryExists when the member's own key is another
             member's. A DeleteEntry is refused with entryUnknown when its key is not
             held.
             A command made from another revision than that of the collection's file
             is refused with revisionConflict: the collections are shared by the
             stations of the shack, and a change made from an older state would undo
             another's. A command that is not refused writes the file of its
             collection with the change and the revision one higher: the whole file
             anew, made durable, and put in its place in one step. A file that cannot
             be written refuses it with storageUnavailable.
             Only then is the command answered, with the snapshot of the collection:
             DefinitionsSnapshot for strategies and wantedList, ShackSnapshot for
             udpTargets, txMacros and workingFrequencies. A created wanted entry takes as
             addedUtcMs the moment the profile carries the command out.
             A refused command changes nothing. A member keeps its place in its
             collection; a new one is added at the end.
             A rule that needs a fact of another part takes it from the last RuleFacts:
             the entity names for a country entry of a strategy, the names of the
             built-ins for the name of a strategy. */
    }

    attribute def StrategiesFile {
        doc /* The definition file in which the profile keeps the saved strategies: the
             file strategy.json in the shack's folder (ShackFolder), one JSON
             object of UTF-8 with exactly the keys schemaVersion, revision and
             configuration. schemaVersion is 4. revision counts the changes
             (DefinitionsSnapshot::revision).
             configuration holds the saved strategies by
             WstxStrategies::ConfigurationKeys, with active null and without contest.
             The profile reads the file at station start, by
             WstxStrategies::StrategyReading, and gives the strategies as
             DefinitionsSnapshot. Without a file there is no saved strategy.
             A file is used when it has this form; one that also holds profileId is
             read without it. A file
             of an older schema version is written in the present form with the next
             change of the strategies.
             Every other file cannot be used: there is no saved strategy,
             DefinitionsSnapshot::unusable is true, and the file is left as it is until
             the next change of the strategies is written in its place. */
        attribute reading : StrategyReading;
    }

    attribute def WantedFile {
        doc /* The definition file in which the profile keeps the wanted list: the file
             wanted.json in the shack's folder (ShackFolder), one JSON object of
             UTF-8 with exactly the keys schemaVersion, revision and entries.
             schemaVersion is 1. revision counts the changes
             (DefinitionsSnapshot::wantedRevision). entries is the list in the order of
             adding, each an object with the keys call and addedUtcMs.
             Without a file the list is empty. A file that cannot be used gives an
             empty list and is left as it is until the next change is written in its
             place. */
    }

    requirement 'CL-039-30' {
        subject profile : PersistedProfile;
        doc /* Profile MUST fetch the Most Wanted list of Club Log when the supervisor
             asks for it and keep the last good list for the operator (MostWantedFetch). */
        @Status { build = ImplementationState::partial; }
        @ImplementedIn { module = "server/src/most_wanted.rs"; }
    }
    #derivation connection { end #original ::> 'FR-016'; end #derive ::> 'CL-039-30'; }

    action def MostWantedFetch {
        out item query : MostWantedQuery;
        in item download : MostWantedDownload;
        doc /* An UpdateMostWanted sends one MostWantedQuery. The MostWantedDownload is
             taken as a list when it is what that item says, each row with its limits.
             Everything else is refused with downloadFailed and a detail: for an answer
             with another status than 200 "status" and that status, for an answer that
             is no list "the reply is not a Most Wanted list". A list that is taken is
             written to MostWantedFile with the UTC date of the download, and the
             DefinitionsSnapshot gives it; a list that cannot be written is refused with
             storageUnavailable. A refused update leaves the kept list as it is. */
    }

    attribute def MostWantedFile {
        doc /* The file in which the profile keeps the list: mostWanted.json in the
             shack's folder (ShackFolder), under the file's lock, one JSON object of
             UTF-8 with exactly the keys schemaVersion, date and list. schemaVersion is
             1; list is the download's object from rank to number. Without the file there
             is no list. A file that cannot be read or holds no list gives no list, and
             DefinitionsSnapshot::mostWantedUnusable is true. */
    }

    requirement 'CL-055-06' {
        subject profile : PersistedProfile;
        doc /* Profile MUST fetch the newest country file when the supervisor asks for
             it and keep the last good one for the operator (CountryFileFetch). */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-016'; end #derive ::> 'CL-055-06'; }

    action def CountryFileFetch {
        out item query : CtyQuery;
        in item download : CtyDownload;
        doc /* An UpdateCountryFile sends one CtyQuery. An answer that is no file is refused
             with downloadFailed and a detail ("status" and the status, or "the reply is
             too large"). A text that does not read as a country file (CountryFileStore) is
             refused with invalidCountryFile and its line. A text that reads is written
             to CountryFileStore, and the DefinitionsSnapshot gives it; a file that cannot
             be written is refused with storageUnavailable. A refused update leaves the
             kept file as it is. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Download Latest CTY.dat in "
                + "Settings; the downloaded file in place of the installed one";
        }
    }

    attribute def CountryFileStore {
        doc /* The file in which the profile keeps the country file: cty.dat in the
             shack's folder (ShackFolder), under the file's lock, written anew and put
             in place in one step. A text is kept only when it reads by format. Without the
             file none is kept. At station start a file that does not read by format is
             left as it is, none is given, and DefinitionsSnapshot::countryFileUnusable is
             true. */
        attribute format : CountryFile;
    }

    verification 'TC-039-055' {
        doc /* What is a Most Wanted list, and the answer of the service. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-30'; }
        @TestedBy {
            test = "server/src/most_wanted.rs::"
                + "tc_039_031_parser_refuses_all_but_the_exact_list; "
                + "server/src/most_wanted.rs::tc_039_031_response_body";
        }
    }

    verification 'TC-039-001' {
        doc /* A strategy is created, changed and deleted by its name. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-01'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::tc_039_001_configuration_is_exact";
        }
    }

    verification 'TC-039-003' {
        doc /* The strategies file. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-01'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::tc_039_003_store_routes_and_evaluate";
        }
    }

    verification 'TC-097-002' {
        doc /* The strategies files of the older versions. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-01'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_002_a_schema_3_file_upgrades_key_by_key_and_renames_built_in_names; "
                + "server/src/strategy97_tests.rs::"
                + "tc_097_002_schema_2_and_4_files_and_the_cq_wait_default; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_030_an_old_file_upgrades_and_active_never_survives_a_restart; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_032_a_builtin_is_selected_like_any_strategy_and_never_stored";
        }
    }

    requirement 'CL-097-01' {
        subject profile : PersistedProfile;
        doc /* Profile MUST take a strategy only when it lies within the rules of a
             strategy, and name a value that does not (StrategyCheck). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-016'; end #derive ::> 'CL-097-01'; }

    attribute def StrategyCheck {
        doc /* How the profile holds the strategy of a CreateEntry or an UpdateEntry to
             its rules. The rules are operating's: form. The profile applies them as
             CollectionRule says; the value it names is named as
             WstxStrategies::ConfigurationKeys says, from the strategy down. */
        attribute form : StrategyForm;
    }

    verification 'TC-097-001' {
        doc /* The bounds of a strategy and the value each refusal names. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-097-01'; }
        @TestedBy {
            test = "server/src/strategy97_tests.rs::"
                + "tc_097_001_schema_4_every_key_at_its_bounds_and_one_refusal_per_field; "
                + "server/src/strategy97_tests.rs::"
                + "tc_097_001_a_put_is_read_back_and_an_oversized_body_is_refused; "
                + "server/src/strategy_tests.rs::"
                + "tc_039_032_the_builtin_table_and_what_a_configuration_may_say";
        }
    }

    requirement 'CL-005-05' {
        subject profile : PersistedProfile;
        doc /* Profile MUST store the audio devices and the radio control of a profile
             each by itself, and make a profile with no device and no radio control
             (CreateProfile). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/main.rs"; }
    }
    #derivation connection { end #original ::> 'FR-001'; end #derive ::> 'CL-005-05'; }

    attribute def CreateProfile {
        doc /* How a CreateRequest is carried out: the profile is made and the request
             answered by ProfileCreated; no station runs (WstxStartup::LaunchRule).
             The folder is made new, and profile.json is written into it with the
             values each feature of ProfileDocument, of Endpoint and of the
             configurations of StationConfig is given in its definition, a new
             profileId, no radio and no native.
             A folder that exists, also an empty one, a folder whose parent does not
             exist, and a file that cannot be written end the creation with
             resourceUnavailable; what exists is left as it is.
             An OpenRequest makes no profile.
             StationConfig::audio and RadioConfig::control are saved as SaveSettings
             says: each of the two devices and the radio control can be set and taken
             away without the others. */
        @DiffersFromSource {
            what = "WSJT-X at the behaviour baseline makes its settings at the first "
                + "start and keeps further configurations inside one settings file; a "
                + "profile is made by a command of its own, in a folder of its own.";
        }
    }

    requirement 'CL-044-05' {
        subject profile : PersistedProfile;
        doc /* Profile MUST save an audio device only as the endpoint id of its
             direction (EndpointIds). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/radio_control/setup.rs; server/src/radio_setup.rs";
        }
    }
    #derivation connection { end #original ::> 'FR-001'; end #derive ::> 'CL-044-05'; }

    attribute def EndpointIds {
        doc /* How the two audio devices of AudioConfig are saved.
             A SaveProfile whose input or output is present and has not the form of an
             endpoint id of its direction, as AudioConfig gives it, is refused with
             SaveRefusal::audioDeviceNotEndpoint and the field.
             A document that is opened may hold another text of 1 to 256 bytes without
             a control character in the place of a device: it is taken as it is and
             not changed; audio finds no endpoint of that id, and the operator chooses
             the device again. */
    }

    requirement 'CL-013-08' {
        subject profile : PersistedProfile;
        doc /* Profile MUST store, for a profile of the native connection, the station's
             identity toward the radio, the receive antenna and at most an address, and
             neither a device nor a radio control (NativeProfile). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/main.rs"; }
    }
    #derivation connection { end #original ::> 'FR-001'; end #derive ::> 'CL-013-08'; }

    attribute def NativeProfile {
        doc /* The profile of a station that uses a FlexRadio through its native
             interface.
             It is made by a CreateRequest with a NativeIntent: as CreateProfile, with
             schemaVersion 2, the connection type nativeFlex and a NativeIntent of a
             new clientId and the request's antenna and address.
             An antenna or an address outside the rules of NativeIntent refuses the
             request with invalidRuntimeConfiguration, and no folder is made.
             Its document has no inputDevice, no outputDevice, the control mode
             disabled without an endpoint, and ptt disabled. A SaveProfile with another
             value in one of these is refused with SaveRefusal::invalidSettings and
             the field, the first of audio.inputDevice, audio.outputDevice,
             control.mode, control.endpoint and control.ptt.
             No save changes the NativeIntent. */
    }

    verification 'TC-023-007' {
        doc /* What a profile of the native connection stores. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-013-08'; }
        @TestedBy {
            test = "server/src/profile_tests.rs::"
                + "native_schema_two_document_is_exact_and_standard_schema_one_is_unchanged; "
                + "server/src/profile_tests.rs::"
                + "native_profile_creation_persists_intent_without_runtime_handles";
        }
    }
}

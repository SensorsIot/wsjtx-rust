package WstxProfileDocument {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-001';
    private import WstxRequirements::'FR-016';
    private import WstxRequirements::'FR-022';
    private import WstxProfileAccess::*;
    private import WstxStrategies::StrategyForm;
    private import WstxStrategies::StrategyReading;
    private import ModelNotes::DiffersFromSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import WstxProfilePart::PersistedProfile;

    doc /* The profile's functions: one station process for a profile, the start, the
         saved document and its save, the hidden store, the operator's folder and
         settings, the collections of settings, the creation of a profile, the
         endpoint ids and the profile of a radio's native connection. */

    // ---- One station process for a profile ------------------------------------------------

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
             the folder, and one on the file named by the profile_id and .lock in the
             folder wstx-rust-profile-locks of the account's local application data
             (LOCALAPPDATA), or of the temporary folder when the account has none.
             A lock that another process holds refuses the start with
             StartupOutcome::profile_in_use: the same folder under any name, and a copy
             of the folder with the same profile_id.
             A lock that cannot be taken for another reason refuses the start with
             StartupOutcome::resource_unavailable.
             A lock file that a process left behind holds nothing: the profile can be
             opened again as soon as that process has ended.
             A station process has one profile, and a profile shares no file, no lock
             and no state with another profile but the operator's folder
             (OperatorFolder). */
        @DiffersFromSource {
            what = "WSJT-X at the behaviour baseline keeps one lock file in the temporary "
                + "folder, named by the application and its rig name, and offers to "
                + "remove a lock that is left behind; the profile locks its folder and "
                + "its identity, and a lock left behind needs no removal.";
        }
    }

    // ---- Starting with a profile ------------------------------------------------------------

    requirement 'CL-005-04' {
        subject profile : PersistedProfile;
        doc /* Profile MUST end a start or a creation it cannot carry out with its
             reason and leave the saved profile as it is (OpenProfile, StartupOutcome). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn { module = "server/src/main.rs"; }
    }
    #derivation connection { end #original ::> 'FR-022'; end #derive ::> 'CL-005-04'; }

    enum def StartupOutcome {
        doc /* How a start of the station with a profile, or a creation, ends.
             ready: the station runs with the profile.
             created: the profile is made.
             invalid_runtime_configuration: the arguments or the environment of the
             process are not ones the station takes.
             resource_unavailable: the folder, a file or a lock cannot be had.
             invalid_profile: profile.json is not a ProfileDocument.
             unsupported_schema: the schema_version is none the station knows.
             unsupported_connection_type: the connection type does not go with the
             schema_version.
             profile_in_use: another station process holds the profile.
             endpoint_in_use: another process listens where the profile says.
             ready is the one outcome with which the process goes on; created ends it
             with the exit code 0. Every other outcome is written to the output of the
             process, beginning with its name and a colon, and ends the process with
             another exit code, before the station listens. A start that named a folder
             writes the words selected profile and the folder as it was named after the
             colon. */
        enum ready;
        enum created;
        enum invalid_runtime_configuration;
        enum resource_unavailable;
        enum invalid_profile;
        enum unsupported_schema;
        enum unsupported_connection_type;
        enum profile_in_use;
        enum endpoint_in_use;
    }

    attribute def OpenProfile {
        doc /* How the profile is opened when the station starts with --profile and a
             folder. The first of these that holds ends the start; a start that ends so
             changes no file.
             invalid_runtime_configuration: the arguments are not exactly one of
             --profile with a folder, --create-profile with a folder, and
             --create-native-flex-profile with a folder, a receive antenna and at most
             an address, with at most one --operator and a folder beside --profile; or
             the environment holds WSTX_BIND or WSTX_ORIGIN.
             resource_unavailable: the folder does not exist, or profile.json cannot be
             opened or read.
             invalid_profile: profile.json is larger than
             ProfileLimits::profileFileMaxBytes or is not the JSON object ProfileDocument
             describes.
             unsupported_connection_type: schema_version 1 with the connection type
             native_flex.
             unsupported_schema: schema_version 2 without native, and every
             schema_version other than 1 and 2.
             invalid_profile: any other pairing of schema_version, connection type and
             native than the two of ProfileDocument, or a NativeIntent outside its rules.
             invalid_profile: a profile_id that is no UUID of version 4 in lower case,
             a value of StationConfig
             outside the rule its definition gives, or an Endpoint outside its rules.
             profile_in_use, resource_unavailable: the locks of ProfileOwnership.
             invalid_profile: the largest ProfileSnapshot the profile could ever give
             is over ProfileLimits::profileHttpMaxBytes. The largest is taken with the
             origin of this station and the values of StationConfig at their longest, where each
             byte of the name, of
             the two devices and of the control endpoint takes two bytes.
             A device entry of AudioConfig that is no endpoint id ends no start
             (EndpointIds).
             A document of a managed radio without radio is read with RadioConfig::agc
             slow; the file changes with the next save.
             Only profile.json is read: a temporary file left beside it is not used.
             The web adapter and the station service add their own reasons to end a
             start, with the outcomes of StartupOutcome. */
    }

    // ---- Saving -------------------------------------------------------------------------------

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
             invalid_settings without a field: a profileId that is no UUID.
             invalid_settings with the field: the first value of StationConfig outside
             the rule its definition gives. The values are looked at in the order
             display_name, audio.input_device, audio.output_device, control.mode,
             control.rig, control.endpoint, control.ptt, radio, then the values of
             transmit and receive in the order of their definitions; a value is named by its key in
             the file,
             one under a part as the part's key, a dot and the value's name
             (transmit.tuneSeconds). radio is named when RadioConfig::agc is present for
             a radio that is not managed.
             invalid_settings with the field: on a profile of the native connection, a
             value NativeProfile does not allow.
             audio_device_not_endpoint with the field: EndpointIds.
             wrong_profile: profileId is not the profile_id of the document.
             storage_unavailable: the file cannot be written.
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
             profile_id, endpoint, connection_type and native are the same after every
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
             UTF-8 with the key schema_version, 1, and one key for each part that has
             records (radio for RadioRecords, audio for AudioRecords). It is written as
             the document is: the whole file anew, made durable, and put in its place
             in one step.
             A file that cannot be read, or is of another schema, gives every record
             as its definition gives it, and MemorySnapshot::unreadable is true; the
             file is left as it is until the next SaveMemory is kept in its place. */
    }

    verification 'TC-022-001' {
        doc /* The settings of a profile: what is taken, what is refused, and that a
             save of one profile touches no other.
             Setup: four profiles in folders of their own, with the ids
             00000000-0000-4000-8000-000000000001 to -000000000004, the names Station 1
             to 4, the callsigns TEST1 to TEST4, the locator JN47AA, an input and an
             output endpoint id each and no radio control; four stations on the
             loopback interface; the profile is asked through the station service.
             For (b), (i) and (k) the profile alone.
             (a) Each station gives its own profile_id and settings.
             (b) A document whose endpoint has a key the profile does not know, whose
             revision is given twice, or that lacks control.mode, control.endpoint or
             audio.input_device: not a ProfileDocument.
             (c) A save of profile 1 with the name Edited station 1, another input
             endpoint id and the control cat with the endpoint fixture-cat-1: taken;
             the files of the other three profiles are byte for byte as before.
             (d) Refused with invalid_settings, the file unchanged. Names: empty, 65
             characters, a space at the beginning, a space at the end, a line break.
             An input device that is empty, has 257 characters or holds
             U+0085. The control disabled with ptt cat; cat without an endpoint; the
             mode native_flex. A profileId that is no UUID.
             (e) Refused with audio_device_not_endpoint: the input Microphone (USB
             Audio CODEC ); the output Speakers (USB Audio CODEC ); an output endpoint
             id as input; an input endpoint id as output.
             (f) The profileId of profile 2: wrong_profile.
             (g) Taken, each: a name of 64 characters; the name X with no device; an
             output endpoint id alone; the control cat with an endpoint of 256
             characters and ptt cat.
             (i) A name of 32 times the letter e with an accent, 64 bytes:
             taken; one character more: refused. No device with the control disabled:
             taken. The control cat with an endpoint and ptt cat, without a device:
             taken.
             (j) The name <img src=x onerror=alert(1)>: saved and given back as it is.
             An input device <script>alert(1)</script> written into the file by hand:
             the station starts and gives it as it is.
             (k) Planned, no test yet: a document whose output is Speakers (USB Audio
             CODEC ): it stays as it is, also with a present output of that name. */
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
        doc /* A saved profile outlasts its station, and a file that is no profile is
             refused and left as it is.
             Setup: as TC-022-001; for (h) and (i) the profile alone on a folder of its
             own, with a fault set at one step of its writing.
             (a) --create-profile with a folder that does not exist: the exit code 0,
             no station; profile.json holds schema_version 1, a UUID of version 4 in
             lower case, revision 0, the name New station, an empty callsign and
             locator, the endpoint 127.0.0.1:8080 without an origin, the connection type
             'standard', no device, the control disabled, and neither radio nor native.
             (b) One save for each of the four profiles and a second one for profile
             1, then every station stopped and started: each with its last saved name;
             the four files byte for byte as before the stop.
             (c) With a temporary file left in the folder, profile.json holding in
             turn: {; one byte 0xFF; the schema_version -1, 0 and 2; the profile_id bad;
             one more key; the connection type native_flex; the ports 0 and 65536 in
             bind; revision given twice; one byte more than
             ProfileLimits::profileFileMaxBytes. The start ends with unsupported_schema
             for the three schema versions, with unsupported_connection_type for
             native_flex and with invalid_profile for the others; the file is byte for
             byte as it was written each time.
             (d) Without profile.json: resource_unavailable. With the saved file filled
             up with spaces to exactly ProfileLimits::profileFileMaxBytes: the station
             starts.
             (e) The folder named from another working directory, not absolute: the
             station starts.
             (g) --create-profile on the folder made in (a), on an empty folder that
             exists, and on a folder whose parent does not exist:
             resource_unavailable. The arguments --unknown, --profile twice, and
             --create-profile beside --profile: invalid_runtime_configuration. WSTX_BIND
             or WSTX_ORIGIN in the environment of a start with --profile:
             invalid_runtime_configuration.
             (h) A save that fails while the file is written, made durable or put in
             place: refused; the document has its settings of before, and the profile
             opened anew finds the file byte for byte as before. The process stopped
             before the file is put in place: opened anew, the file as before. Stopped
             after it: opened anew, the new settings.
             (i) A whole other document left beside profile.json as a temporary file:
             opened anew, profile.json unchanged. Then a save, and the profile opened
             anew: the saved settings.
             (j) A file with every value of ProfileConfig, AudioConfig and
             RadioConfig at its longest and an origin of the length with which
             the largest ProfileSnapshot has exactly
             ProfileLimits::profileHttpMaxBytes: the station starts and gives a snapshot
             of that size. With an origin one byte longer, and with a host of 9000
             characters: invalid_profile before the station listens, the file
             unchanged, the other three stations in use as before.
             (k) Planned, no test yet: the configurations of transmit and receive
             saved in the document and the same after the station is stopped and
             started; a record of radio
             control and of audio kept in the hidden store and the same after the
             station is stopped and started. */
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
        doc /* One station process for a profile, and what a start that cannot be
             carried out leaves behind.
             Setup: as TC-022-001; each fault alone. A start counts as ended when its
             process has ended within 10 s with an exit code other than 0, the name of
             the outcome in its output and no line that says it listens.
             (a) Station 1 stopped: the other three answer as before. Station 1
             started again: it runs.
             (b) While station 1 runs, a second start with the same folder, with
             another name of that folder, and with a copy of the folder:
             profile_in_use.
             (c) The profile opened twice in one process: the second is refused with
             profile_in_use; once the first is given up, it opens.
             (d) Two stations whose documents have the same profile_id, each with its
             own local application data: both run.
             (e) profile.json that the account may not read: resource_unavailable; the
             file is byte for byte as before.
             (f) An origin whose port is one above the port of bind: invalid_profile.
             (g) While station 1 runs and profile.json cannot be written: a save is
             refused with storage_unavailable, and the four files are byte for byte
             as before. */
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

    // ---- The operator's folder and settings ------------------------------------------------

    requirement 'CL-005-07' {
        subject profile : PersistedProfile;
        doc /* Profile MUST keep the settings and files the operator's stations share in
             one folder of the operator, change a shared file only under its lock and
             from its revision, and give its station a change another station has made
             (OperatorFolder, SaveOperatorSettings). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-016'; end #derive ::> 'CL-005-07'; }

    attribute def OperatorFolder {
        doc /* The folder the operator's stations share, and how a station uses it.
             It is the folder WSTX-Rust\operator in the account's local application
             data (LOCALAPPDATA), or the folder the launch argument --operator names;
             a name that is not absolute counts from the working directory. A folder
             that does not exist is made at station start; one that cannot be made or
             used ends the start with StartupOutcome::resource_unavailable.
             It holds operator.json (OperatorDocument), the strategies file
             (StrategiesFile), and the files the functions of the stations keep there:
             the logbook and the operator's country file (the log's) and the Most
             Wanted list (ranking's).
             A station changes a file of the folder only while it holds that file's
             lock, for the change alone; a station waits while another holds it. A
             shared file with a revision is changed only from its revision
             (SaveOperatorSettings, CollectionRule).
             When another station has changed operator.json or the strategies file,
             the profile reads it anew and gives its snapshot (OperatorSnapshot,
             DefinitionsSnapshot); how soon is a value of the code. */
    }

    attribute def SaveOperatorSettings {
        doc /* What the profile does with a SaveOperator, and how operator.json is read.
             The first of these that holds refuses it (SaveRefused).
             invalid_settings with the field: the first value of OperatorSettings
             outside the rule its definition gives, by its key in the file: callsign,
             locator, continent, cq_words, then the values of spots and udp, each named
             as the part's key, a dot and the value's name.
             revision_conflict: expectedRevision is not the revision of operator.json.
             storage_unavailable: the file cannot be written.
             A save that is not refused writes operator.json with the new settings and
             the revision one higher, under the file's lock: the whole file anew, made
             durable, and put in its place in one step. Only then is it answered, with
             the new OperatorSnapshot. A refused save changes nothing.
             At station start the profile reads operator.json. Without the file the
             settings are as their definitions give them, at revision 0. A file that
             cannot be used gives those settings with OperatorSnapshot::unusable true,
             and is left as it is until the next save is written in its place. */
    }

    verification 'TC-022-011' {
        doc /* The operator's settings, shared by the operator's stations.
             Setup: as TC-022-001.
             (a) Refused with invalid_settings, the file unchanged: the callsigns AB,
             13 characters, abc1, ABC and 123; the locators JN4, SN47, JN47YY,
             JN47AA9, jn47 and A000.
             (b) Taken: the callsign A12345678901 with the locator RR99XX99; an empty
             callsign and an empty locator; the callsign A1B with the locator JN47;
             the locators AA00AA and RR99XX99.
             (c) Planned, no test yet: two stations of one operator's folder. A save of
             the operator's settings on one: the other gives the new settings. A save
             on the other made from the revision before: revision_conflict, the file
             unchanged. A QSO logged on one is in the worked set of the other. Without
             the folder, a station start makes it; --operator names another, and the
             strategies file, the logbook, the country file and the Most Wanted list
             lie there. */
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

    // ---- The collections of settings -----------------------------------------------------

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
        doc /* What the profile does with a CreateEntry, an UpdateEntry and a DeleteEntry
             (SettingsCollection).
             The member is held to the rules its part states for it and for its
             collection; the profile applies them and has no rules of its own for a
             member. A member outside them is refused with invalid_settings and one
             value that is outside (SaveRefused::field).
             A CreateEntry is refused with entry_exists when its key is held, and with
             collection_full when the collection holds as many members as its rules
             allow. An UpdateEntry is refused with entry_unknown when its key is not
             held, and with entry_exists when the member's own key is another
             member's. A DeleteEntry is refused with entry_unknown when its key is not
             held.
             A command made from another revision than that of the collection's file
             is refused with revision_conflict: the collections are shared by the
             stations of the operator, and a change made from an older state would undo
             another's. A command that is not refused writes the file of its
             collection with the change and the revision one higher: the whole file
             anew, made durable, and put in its place in one step. A file that cannot
             be written refuses it with storage_unavailable.
             Only then is the command answered, with the snapshot of the collection:
             DefinitionsSnapshot for strategies and wantedList, OperatorSnapshot for
             udpTargets. A created wanted entry takes as addedUtcMs the moment the
             profile carries the command out.
             A refused command changes nothing. A member keeps its place in its
             collection; a new one is added at the end.
             A rule that needs a fact of another part takes it from the last RuleFacts:
             the entity names for a country entry of a strategy, the names of the
             built-ins for the name of a strategy. */
    }

    attribute def StrategiesFile {
        doc /* The definition file in which the profile keeps the saved strategies: the
             file strategy.json in the operator's folder (OperatorFolder), one JSON
             object of UTF-8 with exactly the keys schema_version, revision and
             configuration. schema_version is 4. revision counts the changes
             (DefinitionsSnapshot::revision).
             configuration holds the saved strategies by
             WstxStrategies::ConfigurationKeys, with active null and without contest.
             The profile reads the file at station start, by
             WstxStrategies::StrategyReading, and gives the strategies as
             DefinitionsSnapshot. Without a file there is no saved strategy.
             A file is used when it has this form; one that also holds profile_id is
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
             wanted.json in the operator's folder (OperatorFolder), one JSON object of
             UTF-8 with exactly the keys schema_version, revision and entries.
             schema_version is 1. revision counts the changes
             (DefinitionsSnapshot::wantedRevision). entries is the list in the order of
             adding, each an object with the keys call and added_utc_ms.
             Without a file the list is empty. A file that cannot be used gives an
             empty list and is left as it is until the next change is written in its
             place. */
    }

    verification 'TC-039-001' {
        doc /* A strategy is created, changed and deleted by its name.
             Setup: the profile alone on a throw-away folder.
             (a) A create of the strategy Test calls: taken, and given back value for
             value.
             (b) A create of a strategy with one key more: refused, naming the strategy
             as a whole.
             (c) A create of a after A: entry_exists.
             (d) A 17th create: collection_full. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-01'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::tc_039_001_configuration_is_exact";
        }
    }

    verification 'TC-039-003' {
        doc /* The strategies file.
             Setup: the station on a throw-away profile of HB9BLA in JN47 without a
             strategies file.
             (a) Read: no saved strategy.
             (b) A create of the one strategy Test calls: the strategies file holds
             schema_version 4 and that strategy. A profile opened with the same
             operator's folder holds the same strategy.
             (d) A create of a strategy of the class award: refused, naming class.
             (h) Planned, no test yet: an update of Test calls with leaving after 5
             calls: the file holds the new value; a delete of Test calls: the file
             holds no strategy; an update or delete of Other: entry_unknown. */
        subject profile : PersistedProfile;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-039-01'; }
        @TestedBy {
            test = "server/src/strategy_tests.rs::tc_039_003_store_routes_and_evaluate";
        }
    }

    verification 'TC-097-002' {
        doc /* The strategies files of the older versions.
             Setup: the station on a throw-away profile, with strategies files written
             by hand.
             (a) Version 3 with Mine (goals dxcc_band and new_call, needed
             not_confirmed, region dx, value new_dxcc_slot and snr, cq_when_no_target
             on, 5 repetitions, 15 quiet minutes, Treat 73 as CQ off, window today),
             Grid (goal grid), DXCC all, dxcc all copy and Casual: read. Mine is of
             class strategy for every band: new dxcc and call per band, not_confirmed,
             region dx, worked since today, Treat 73 as CQ off, empty lists, order
             new_dxcc_band_mode and snr, calling stations answered, leaving after 5
             calls and 10 while heard, the frequency moved never, at every call and at
             every 2nd call, the busy pause on, CQ when idle with a CQ wait of 2, a
             retry pause of 15. Grid is new grid per ever. The names read are Mine,
             Grid, DXCC all copy 2, dxcc all copy and Casual copy; renamed lists DXCC
             all as DXCC all copy 2 and Casual as Casual copy.
             (b) A change of the strategies after that: the file has schema_version 4,
             and renamed is empty.
             (c) Version 3 with a strategy whose value names the criterion rarest:
             unusable, with no saved strategy.
             (d) The eight goals, each alone: dxcc gives dxcc per ever, dxcc_band dxcc
             per band, dxcc_slot dxcc per band_mode, waz cq_zone per ever, wpx prefix
             per ever, grid grid per ever, new_call call per ever, new_call_band call
             per band.
             (e) Version 2 with Mine (goal new_call, needed not_worked, region all,
             5 calls_per_station, Treat 73 as CQ on, window all): read as new call per
             ever, not_worked, order most_wanted, calling stations answered, leaving
             after 4 calls and 8 while heard, the frequency moved never, at every call
             and at every 2nd call, the busy pause on, no CQ when idle, a CQ wait of 2,
             a retry pause of 10. A change after that writes schema_version 4.
             (f) Version 2 with 0 or 21 calls_per_station, without it, with the region
             east, or with a key value: unusable. Version 3 with that strategy of
             version 2: unusable.
             (g) Version 4 with a strategy without cq_wait_periods and one with 5: read
             with 2 and with 5. Version 4 with the saved strategies New calls and
             Casual: usable, and read as New calls and Casual copy.
             (h) Version 1 with one strategy, an active name, the continent AS, the
             ignore list K1ABC and 45 session minutes: read with no saved strategy. A
             file of version 5: unusable. Version 4 with an active name: read, and the
             name is not taken over.
             (i) Planned, no test yet: of that file of version 1, and of one of
             version 4 with the keys continent, ignore_calls and
             session_ignore_minutes, neither the continent nor the ignore list is
             taken over; a file of version 1 with the continent XX is usable. */
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
        doc /* The bounds of a strategy and the value each refusal names.
             Setup: the rules alone, with strategies written by hand; for (f) the
             station on a throw-away profile. A refused value is named below from the
             strategy down.
             (a) A strategy of class strategy with every value at its upper bound, and
             a strategy of class contest for ww_digi: 32 bands; all seven of new, per
             band_mode, not_confirmed; region selected with the seven continents; a
             minimum SNR of -50; worked since 1 January 1930 to 31 December 2099; 64
             entries in each country list, one a prefix of 13 characters and one with
             32 bands; the 51 states; 32 CQ targets of 8 characters in each list; the
             16 criteria; leaving after 20 calls and 40 while heard; the frequency
             moved at every 20th call while heard; a CQ wait of 20; a retry pause of
             120: taken, and given back value for value.
             (b) Leaving after 1 call and 1 while heard; until_logged with 1 and with
             60 minutes; contest with 1 and with 20 Tx changes; a retry pause of 1;
             a CQ wait of 1; the frequency never moved: taken.
             (c) The band 11m: bands[0]. 20m twice: bands[1]. 33 bands: bands. No new:
             filters.new. dxcc twice: filters.new[1]. The scope slot: filters.new_per.
             A country entry of the kind call: filters.countries.include[0].kind; the
             prefix VK-9, a prefix of 14 characters and the country Atlantis: its
             value; with 33 bands: its bands. 65 entries:
             filters.countries.include. The states XX and PR:
             filters.states.include[0]. 52 states: filters.states.include. A CQ
             target of 9 characters and PO-TA: filters.cq_targets.include[0]. 33 CQ
             targets: filters.cq_targets.include. snr twice: order[1]. 17 criteria:
             order.
             (d) 0 and 21 calls: leave.calls. 3 calls while heard after 4 calls, and
             41: leave.calls_heard. 0 and 61 minutes: leave.gone_minutes. 0 and 21 Tx
             changes: leave.tx_changes. The mode never: leave.mode. A move at every
             -1st and 21st call: tx_move_every.heard; a move without one of its three
             cases: tx_move_every. A retry pause of 0 and of 121: retry_minutes. A CQ
             wait of 0, of 21, as a text, null and left out: cq_wait_periods.
             (e) Class contest with a criterion in its order: order; with new among
             its filters: filters; with no contest and with an unknown one: contest.
             Class strategy with the contest ww_digi: contest. The classes award and
             casual: class. The names DXCC all and casual: name. A strategy with one
             key more: the strategy as a whole.
             (f) A create of one strategy of each class: given back value for value.
             An update of one with the country Atlantis: refused with its value, and
             the strategies file as before.
             (g) A strategy named New DXCC or new dxcc, and one named Casual: name. A
             strategy with the key builtin: the strategy as a whole. One named New
             DXCC copy: taken. */
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

    // ---- A new profile, its devices and its radio control ----------------------------------

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
        doc /* How a profile is made: the station is started with --create-profile and
             a folder, makes the profile and ends (StartupOutcome::created) without
             running a station.
             The folder is made new, and profile.json is written into it with the
             values each feature of ProfileDocument, of Endpoint and of the
             configurations of StationConfig is given in its definition, a new
             profile_id, no radio and no native.
             A folder that exists, also an empty one, a folder whose parent does not
             exist, and a file that cannot be written end the creation with
             resource_unavailable; what exists is left as it is.
             Other arguments end it with invalid_runtime_configuration (OpenProfile).
             A start with --profile makes no profile.
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
             SaveRefusal::audio_device_not_endpoint and the field.
             A document that is opened may hold another text of 1 to 256 bytes without
             a control character in the place of a device: it is taken as it is and
             not changed; audio finds no endpoint of that id, and the operator chooses
             the device again. */
    }

    // ---- The profile of the native connection -----------------------------------------------

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
             It is made by --create-native-flex-profile with a folder, a receive
             antenna and at most an address: as CreateProfile, with schema_version 2,
             the connection type native_flex and a NativeIntent of a new client_id, that
             antenna and that address.
             An antenna or an address outside the rules of NativeIntent ends the
             creation with invalid_runtime_configuration, and no folder is made.
             Its document has no input_device, no output_device, the control mode
             disabled without an endpoint, and ptt disabled. A SaveProfile with another
             value in one of these is refused with SaveRefusal::invalid_settings and
             the field, the first of audio.input_device, audio.output_device,
             control.mode, control.endpoint and control.ptt.
             No save changes the NativeIntent. */
    }

    verification 'TC-023-007' {
        doc /* What a profile of the native connection stores.
             Setup: the profile alone, on documents written by hand and on folders of
             its own.
             (a) A document with schema_version 2, native_flex, no device, the control
             disabled and the native client_id 72e8c7f3-5766-4ade-9286-ebf2f525c77a
             with rx_antenna ANT1: taken, and written back key for key. With
             radio_address 192.0.2.10:4992: taken and written back with it. A document
             of the connection type 'standard' is written without native.
             (b) invalid_profile: native null; in native a key radio_serial,
             slice_index or stream_id; a client_id with a capital letter; the antenna
             ant1; the input device X; radio_address null, radio.local:4992,
             192.0.2.10, 192.0.2.10:0 and [::1]:4992; the control mode cat; the
             connection type 'standard'; a document of schema_version 1 with native.
             (c) unsupported_connection_type: schema_version 1 with native_flex, with
             and without native. unsupported_schema: schema_version 3; schema_version
             2 without native.
             (d) Created with the antenna "ant 1", and with ANT1 and the address
             radio.local:4992: invalid_runtime_configuration, and no folder.
             (e) Created with ANT1: profile.json holds rx_antenna ANT1 and a client_id
             that is a UUID, and none of the words serial, slice, stream, handle, dax
             and frequency. A save with an output device X is refused, and the file is
             byte for byte as before.
             (f) Created with ANT1 and 192.0.2.10:4992: the address is stored and read
             back. */
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

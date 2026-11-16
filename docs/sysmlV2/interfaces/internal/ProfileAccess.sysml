package WstxProfileAccess {
    private import ScalarValues::*;
    private import WstxRadioControl::RadioConfig;
    private import WstxRadioControl::RadioRecords;
    private import WstxAudioControl::AudioConfig;
    private import WstxAudioControl::AudioRecords;
    private import WstxTransmitControl::TransmitConfig;
    private import WstxReceiveControl::ReceiveConfig;
    private import WstxHearing::SpotsConfig;
    private import WstxUdpControl::UdpConfiguration;
    private import WstxUdpControl::UdpTarget;
    private import WstxStrategies::Strategy;
    private import WstxRankingControl::WantedEntry;
    private import WstxLogControl::Continent;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::NotStated;

    doc /* What the profile stores and what crosses between the profile and the
         functions of the station: the settings of the station and of its operator,
         the hidden store and the places of the two folders from the profile, and the
         changes to them.
         The settings have two levels. The station config holds what the operator sets
         of this station, in the profile's folder. The operator's settings hold what
         the operator's stations share, in the operator's folder (up to six stations
         of one operator, for example the slices of one FlexRadio, share it). The
         hidden store holds what the software keeps of this station across sessions
         and no menu shows. The display choices of a frontend are that frontend's own
         config. Beside them stand files of their own: the definition files, which a
         settings dialog opens, and the data files, each in the folder of its level.
         A setting and a record are defined by the part that uses them, in that part's
         control interface, with their rules. The profile manages the settings: it
         creates, reads, changes and deletes them, keeps their files and applies the
         rules of their parts. This file refers to each by its type and defines the
         profile's own. */

    // ---- The profile's own configuration ----------------------------------------------------

    enum def ConnectionType {
        doc /* How the station reaches its radio.
             'standard': through a sound device, and CAT where it is set.
             native_flex: through the native interface of a FlexRadio. */
        enum 'standard';
        enum native_flex;
    }
    attribute def ProfileLimits {
        doc /* The bounds of a saved profile. */
        attribute profileFileMaxBytes : Integer = 16384 {
            doc /* The largest file of the saved document. A larger file is no valid
                 profile. */
        }
        attribute profileHttpMaxBytes : Integer = 8192 {
            doc /* The largest ProfileSnapshot, written as compact JSON with the origin
                 of the station as its endpoint and without schema_version. */
        }
        attribute displayNameMaxBytes : Integer = 64;
    }
    attribute def Endpoint {
        doc /* Where the station listens and under which origin a browser reaches it.
             The two are written into the file by hand; no save changes them. */
        attribute 'bind' : String = "127.0.0.1:8080" {
            doc /* The listener address: an IP address and a port from 1 to 65535. */
        }
        attribute origin : String[0..1] = null {
            doc /* The origin of the station page. Absent, or scheme, host and port with
                 the scheme http or https and without credentials, path, query,
                 fragment or a slash at the end. Its port, or the port of its scheme
                 when it names none, is the port of bind. */
        }
    }
    attribute def ProfileConfig {
        doc /* The profile's own configuration: what is set of this station itself. No
             value is altered on the way in: a value outside its rule is refused. */
        attribute display_name : String = "No radio" {
            doc /* The station's name, shown wherever the station is named: in the
                 browser, as the UDP instance name and to an agent. The operator chooses
                 it when the radio is defined, as WSJT-X's rig name: the station offers
                 the name of the chosen rig (IC-7300), for a FlexRadio its model and
                 slice A to F (FLEX-6600 A), and without a radio No radio; the operator
                 takes it or types another. It stays until the operator changes it, and
                 does not depend on the radio answering. No two stations of the PC have
                 the same name. 1 to ProfileLimits::displayNameMaxBytes bytes of UTF-8,
                 without a control character and without white space at its beginning
                 or end. */
        }
        attribute endpoint : Endpoint;
        attribute connection_type : ConnectionType = ConnectionType::'standard' {
            doc /* Chosen when the profile is created. No save changes it. */
        }
    }
    attribute def OperatorConfig {
        doc /* What the operator sets of the operator's own station identity, shared by
             all the operator's stations. No value is altered on the way in: a value
             outside its rule is refused. */
        attribute callsign : String = "" {
            doc /* The call the station transmits and logs under. Empty, or 3 to 12
                 characters of A to Z, 0 to 9 and "/" with at least one letter and one
                 digit. */
        }
        attribute locator : String = "" {
            doc /* The place of the station, which it sends in its messages and
                 measures distances from. Empty, or a Maidenhead locator of 4, 6 or 8
                 characters: two letters A to R, two digits, then two letters A to X,
                 then two digits; all letters in upper case. */
        }
        attribute continent : Continent[0..1] {
            doc /* The continent of the station as the operator has set it. Absent:
                 ranking derives it (WstxValueOrder::MyContinent). While the station
                 has no continent, neither set nor derived, the operator is shown an
                 error message that asks the operator to set it. */
        }
        attribute cq_words : String[0..*] {
            doc /* The CQ words for this station: a CQ that carries one of them after CQ
                 is for the station (WstxValueOrder::DirectedCqRule). Each is a word of
                 1 to 8 characters of A to Z and 0 to 9, and stands once. Settings
                 proposes two words, which the operator takes or changes: the code of
                 the station's continent, and the word of its country, which is the
                 primary prefix of the entity of the profile's call as the country file
                 gives it (WstxLogControl::CallEntity::primaryPrefix: HB for Switzerland,
                 DL for Germany, JA for Japan), when that prefix is such a word. They
                 are also words the station may put after CQ in its own CQ; how a CQ to
                 send is chosen is the contact's and Auto's. */
            @NotStated { what = "how many words the list holds"; }
        }
    }
    attribute def NativeIntent {
        doc /* The configuration of the adapter of a FlexRadio's native connection:
             what a profile of the native connection stores about its radio. It holds
             no serial number, slice, stream or handle of a radio. */
        @NotStated {
            what = "the control interface of the adapter that defines this "
                + "configuration: WstxRadioControl::NativeControlPort names no item "
                + "that carries it, so its three values are defined here";
        }
        attribute client_id : String {
            doc /* The identity under which this station registers with the radio: a
                 UUID of version 4 in lower case, made when the profile is created. */
        }
        attribute rx_antenna : String {
            doc /* The receive antenna: 1 to 16 characters of A to Z, 0 to 9 and "_". */
        }
        attribute radio_address : String[0..1] {
            doc /* Where the radio is reached when it cannot be found by itself: an IPv4
                 address and a port other than 0. Absent: the radio is looked for. */
        }
    }

    // ---- The stores ---------------------------------------------------------------------------

    attribute def StationConfig {
        doc /* The config of one station: every value the operator sets of this
             station, as the collection of the configurations of the station's parts.
             The profile keeps it and defines none of the values of another part. */
        attribute station : ProfileConfig;
        attribute radio : RadioConfig;
        attribute audio : AudioConfig;
        attribute transmit : TransmitConfig;
        attribute receive : ReceiveConfig;
        attribute native : NativeIntent[0..1] {
            doc /* Present exactly with ConnectionType::native_flex. */
        }
    }
    attribute def OperatorSettings {
        doc /* The settings the operator's stations share, as the collection of the
             configurations of their parts. The profile keeps them in the operator's
             folder and defines none of the values of another part. */
        attribute operator : OperatorConfig;
        attribute spots : SpotsConfig;
        attribute udp : UdpConfiguration;
    }
    attribute def OperatorDocument {
        doc /* The saved operator's settings: the content of the file operator.json in
             the operator's folder, one JSON object of UTF-8 with the keys
             schema_version, revision, callsign, locator, continent and cq_words of
             OperatorConfig, and spots and udp for the configurations of these parts,
             each an object with the names of its values as keys. continent is left out
             when absent. A key that is absent, given twice or not named, a value of
             another type and a value outside its rule make the file unusable. */
        attribute schema_version : Integer = 1;
        attribute revision : Integer = 0 {
            doc /* The count of the saves of the file. */ }
        attribute settings : OperatorSettings;
    }
    attribute def StationMemory {
        doc /* The hidden store of one station: the records its parts want kept across
             the sessions of the station, as the collection of the records of each
             part. No menu shows it. The profile keeps it and defines no record. */
        attribute radio : RadioRecords;
        attribute audio : AudioRecords;
    }
    attribute def StrategyDefinitions {
        doc /* The saved strategies of the station. The profile keeps them in a
             definition file of their own (WstxProfileDocument::StrategiesFile). */
        attribute strategies : Strategy[0..*] ordered;
    }
    attribute def ProfileDocument {
        doc /* The saved profile of one station: its identity and its station config. It is the
        content of the file profile.json: one JSON
             object of UTF-8.
             The object has the keys schema_version and profile_id; the keys
             display_name, endpoint and connection_type of ProfileConfig; audio for
             AudioConfig; control for RadioConfig::control and, for a managed radio,
             radio for RadioConfig::agc; transmit and receive for the configurations of
             these parts, each an object with the names of its values as keys; and
             native for the native connection. A file that also holds revision,
             callsign, locator, continent, cq_words, spots or udp is read without them:
             their values are not taken over.
             A key that is absent, given twice or not named, a value of another type
             and a value outside its rule make the file no valid profile. null is
             written for an absent input_device, output_device, control endpoint and
             origin; radio, native and radio_address are left out when absent, and a
             null in their place is not valid. */
        attribute schema_version : Integer = 1 {
            doc /* 1 with the connection type 'standard', 2 with native_flex. */
        }
        attribute profile_id : String {
            doc /* The identity of the profile: a UUID of version 4 in lower case, made
                 when the profile is created. No save changes it. */
        }
        attribute config : StationConfig;
        @FollowsSource { reference = "RFC 9562 section 5.4 (UUID version 4); RFC 8259 (JSON)"; }
    }

    // ---- What crosses ---------------------------------------------------------------------

    item def ProfileFolder {
        doc /* The two folders, in which a function of the station keeps its definition
             files and its data files by itself. The profile gives them once, at
             station start, to the station service, which gives each function the
             folder of its files with its context. */
        attribute path : String {
            doc /* The profile's folder. While the station runs, no other station
                 process uses it. */ }
        attribute operatorPath : String {
            doc /* The operator's folder (WstxProfileDocument::OperatorFolder), which the
                 operator's stations share. */ }
    }
    item def OperatorSnapshot {
        doc /* The operator's settings as they are saved. The profile gives it at station
             start, after every save of them, and when another station has saved them.
             The station service gives each part its configuration from it, over that
             part's control interface. */
        attribute document : OperatorDocument;
        attribute unusable : Boolean {
            doc /* operator.json cannot be used; document holds the settings as their
                 definitions give them. */ }
    }
    item def SaveOperator {
        doc /* Save these operator's settings in the place of the saved ones. It is the
             one way a change of a shared setting takes. */
        attribute expectedRevision : Integer {
            doc /* The revision of operator.json the save was made from. */ }
        attribute settings : OperatorSettings;
    }
    item def ProfileSnapshot {
        doc /* The profile as it is saved. The profile gives it at station start and
             after every change of the document. The station service gives each part
             its configuration from it, over that part's control interface. */
        attribute document : ProfileDocument;
    }
    item def MemorySnapshot {
        doc /* The hidden store as it is kept. The profile gives it at station start and
             in answer to every SaveMemory: the new store when it is durable, the one
             before when it could not be kept. The station service gives each part its
             records from it, over that part's control interface. */
        attribute memory : StationMemory;
        attribute unreadable : Boolean {
            doc /* True when the kept store could not be read at station start; its
                 records are then as their definitions give them. */ }
    }
    item def SaveProfile {
        doc /* Save this station config in the place of the saved one. It is the one way
             a change of a setting takes: the operator's change reaches the station
             service, which brings it here.
             ProfileConfig::endpoint, ProfileConfig::connection_type and
             StationConfig::native are not taken from it. Without RadioConfig::agc for
             a managed radio, the saved one stays. */
        attribute profileId : String {
            doc /* The profile the save was made for. */
        }
        attribute config : StationConfig;
    }
    enum def SettingsCollection {
        doc /* The collections of settings whose members the operator creates, changes
             and deletes one by one. A member is named by its key, which stands once
             in its collection.
             strategies: StrategyDefinitions::strategies, keyed by Strategy::name
             without regard to letter case; held to WstxStrategies::StrategyForm.
             udpTargets: UdpConfiguration::targets of the operator's settings, keyed by
             UdpTarget::address; held to the rules of UdpTarget and UdpConfiguration.
             wantedList: DefinitionsSnapshot::wanted, keyed by WantedEntry::call as it is
             written; held to the rules of WantedEntry. */
        enum strategies;
        enum udpTargets;
        enum wantedList;
    }
    item def CreateEntry {
        doc /* Add this member to a collection; a copy is a member made from another.
             Answered by the snapshot of the collection or by SaveRefused. */
        attribute collection : SettingsCollection;
        attribute expectedRevision : Integer {
            doc /* The revision of the collection's file the command was made from. */ }
        attribute strategy : Strategy[0..1] { doc /* For strategies. */ }
        attribute target : UdpTarget[0..1] { doc /* For udpTargets. */ }
        attribute wanted : WantedEntry[0..1] {
            doc /* For wantedList; its addedUtcMs is set by the profile. */ }
    }
    item def UpdateEntry {
        doc /* Put this member in the place of the member with the key; its own key may
             differ. Answered by the snapshot of the collection or by SaveRefused. */
        attribute collection : SettingsCollection;
        attribute expectedRevision : Integer {
            doc /* The revision of the collection's file the command was made from. */ }
        attribute key : String;
        attribute strategy : Strategy[0..1] { doc /* For strategies. */ }
        attribute target : UdpTarget[0..1] { doc /* For udpTargets. */ }
    }
    item def DeleteEntry {
        doc /* Remove the member with the key. Answered by the snapshot of the
             collection or by SaveRefused. */
        attribute collection : SettingsCollection;
        attribute expectedRevision : Integer {
            doc /* The revision of the collection's file the command was made from. */ }
        attribute key : String;
    }
    attribute def RenamedEntry {
        doc /* A member read under another key than its file gives it. */
        attribute savedName : String { doc /* The key in the file. */ }
        attribute readName : String { doc /* The key it is held under. */ }
    }
    item def DefinitionsSnapshot {
        doc /* The definition files as the profile keeps them. The profile gives it at
             station start and after every change of them. The station service gives
             each part its definitions from it, over that part's control interface. */
        attribute definitions : StrategyDefinitions;
        attribute revision : Integer {
            doc /* The count of the changes of the strategies file; 0 without a file that
                 can be used. */ }
        attribute wanted : WantedEntry[0..*] ordered {
            doc /* The wanted list (WstxProfileDocument::WantedFile). */ }
        attribute wantedRevision : Integer {
            doc /* The count of the changes of the wanted list's file; 0 without a file
                 that can be used. */ }
        attribute unusable : Boolean {
            doc /* The strategies file cannot be used; definitions holds no strategy. */ }
        attribute renamed : RenamedEntry[0..*] ordered {
            doc /* The strategies read under another name, in the order of the file.
                 Empty from the next change of the strategies. */ }
    }
    item def RuleFacts {
        doc /* The facts of other parts that the rules of a settings collection need when
             the profile applies them. The station service gives them at station start
             and whenever one changes. */
        attribute entityNames : String[0..*] {
            doc /* The names of the entities of the country file in use
                 (WstxLogControl::CountryFileState::entityNames). */ }
        attribute builtinNames : String[0..*] {
            doc /* The names of the built-in strategies
                 (WstxStrategies::StrategiesState::builtins). */ }
    }
    item def SaveMemory {
        doc /* Keep this hidden store in the place of the kept one. The station service
             brings it when a part has changed a record. */
        attribute memory : StationMemory;
    }
    enum def SaveRefusal {
        doc /* Why a save is refused. A refused save changes nothing.
             invalid_settings: a value of the settings is outside its rule.
             audio_device_not_endpoint: an audio device is no endpoint id of its
             direction.
             wrong_profile: the save names another profile.
             revision_conflict: a SaveOperator or a command for a collection was made
             from another revision than that of its shared file.
             storage_unavailable: the file cannot be written.
             entry_exists: a CreateEntry, or an UpdateEntry to another key, names a key
             the collection holds.
             entry_unknown: an UpdateEntry or a DeleteEntry names a key the collection
             does not hold.
             collection_full: a CreateEntry for a collection that holds as many members
             as its rules allow. */
        enum invalid_settings;
        enum audio_device_not_endpoint;
        enum wrong_profile;
        enum revision_conflict;
        enum storage_unavailable;
        enum entry_exists;
        enum entry_unknown;
        enum collection_full;
    }
    item def SaveRefused {
        doc /* The answer to a SaveProfile, a SaveOperator, a CreateEntry, an
             UpdateEntry or a DeleteEntry the profile does not carry out. */
        attribute reason : SaveRefusal;
        attribute field : String[0..1] {
            doc /* For invalid_settings and audio_device_not_endpoint, the value that
                 is outside its rule, by its key in the file: display_name, callsign,
                 locator, audio.input_device, audio.output_device, control.mode,
                 control.endpoint, control.ptt or radio; for a member, by its keys as
             its part names them. */
        }
    }

    port def ProfileAccess {
        doc /* Written from the side of the function that uses the profile; the profile
             uses the conjugate.
             Each SaveProfile is answered by one ProfileSnapshot with the saved document
             or by one SaveRefused, each SaveOperator by one OperatorSnapshot or one
             SaveRefused; each SaveMemory by one MemorySnapshot. The profile
             deals with one command after the other. */
        in item folder : ProfileFolder;
        in item saved : ProfileSnapshot;
        in item operatorSettings : OperatorSnapshot;
        in item definitions : DefinitionsSnapshot;
        in item memory : MemorySnapshot;
        out item save : SaveProfile;
        out item saveOperator : SaveOperator;
        out item create : CreateEntry;
        out item update : UpdateEntry;
        out item delete : DeleteEntry;
        out item facts : RuleFacts;
        out item keep : SaveMemory;
        in item refused : SaveRefused;
    }
    interface def ProfileAccessLink {
        doc /* A function of the station uses the profile. */
        end client : ProfileAccess;
        end profile : ~ProfileAccess;
    }
}

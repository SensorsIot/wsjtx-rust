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
    private import WstxAutoControl::AutoConfig;
    private import WstxClubLog::MostWantedRow;
    private import WstxQsoControl::QsoConfig;
    private import WstxQsoControl::QsoShared;
    private import WstxQsoControl::TxMacro;
    private import WstxLogControl::Continent;
    private import WstxStationCommands::StartupRecords;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::NotStated;
    private import WstxModelNotes::CodeDiffers;

    doc /* What the profile stores and what crosses between the profile and the
         functions of the station: the settings of the station and of its operator,
         the hidden store and the places of the two folders from the profile, and the
         changes to them.
         The settings have two levels. The station config holds what the operator sets
         of this station, in the profile's folder. The shack's settings hold what
         the shack's stations share, in the shack's folder (up to six stations
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

    enum def ConnectionType {
        doc /* How the station reaches its radio.
             'standard': through a sound device, and CAT where it is set.
             nativeFlex: through the native interface of a FlexRadio. */
        enum 'standard';
        enum nativeFlex;
    }
    attribute def ProfileLimits {
        doc /* The bounds of a saved profile. */
        attribute profileFileMaxBytes : Integer = 16384 {
            doc /* The largest file of the saved document. A larger file is no valid
                 profile. */
        }
        attribute profileHttpMaxBytes : Integer = 8192 {
            doc /* The largest ProfileSnapshot, written as compact JSON with the origin
                 of the station as its endpoint and without schemaVersion. */
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
        attribute displayName : String = "New station" {
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
        attribute connectionType : ConnectionType = ConnectionType::'standard' {
            doc /* Chosen when the profile is created. No save changes it. */
        }
    }
    attribute def ShackConfig {
        doc /* What the operator sets of the shack's identity, shared by all its
             stations. No value is altered on the way in: a value outside its rule is
             refused. */
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
        attribute cqWords : String[0..*] {
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
            @CodeDiffers {
                what = "The code keeps no CQ words: a CQ is for the station when it is plain, to "
                    + "its continent, or DX from another continent.";
            }
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
        attribute clientId : String {
            doc /* The identity under which this station registers with the radio: a
                 UUID of version 4 in lower case, made when the profile is created. */
        }
        attribute rxAntenna : String {
            doc /* The receive antenna: 1 to 16 characters of A to Z, 0 to 9 and "_". */
        }
        attribute radioAddress : String[0..1] {
            doc /* Where the radio is reached when it cannot be found by itself: an IPv4
                 address and a port other than 0. Absent: the radio is looked for. */
        }
    }

    attribute def StationConfig {
        doc /* The config of one station: every value the operator sets of this
             station, as the collection of the configurations of the station's parts.
             The profile keeps it and defines none of the values of another part. */
        attribute station : ProfileConfig;
        attribute radio : RadioConfig;
        attribute audio : AudioConfig;
        attribute transmit : TransmitConfig;
        attribute receive : ReceiveConfig;
        attribute qso : QsoConfig;
        attribute native : NativeIntent[0..1] {
            doc /* Present exactly with ConnectionType::nativeFlex. */
        }
    }
    attribute def ShackSettings {
        doc /* The settings the shack's stations share, as the collection of the
             configurations of their parts. The profile keeps them in the shack's
             folder and defines none of the values of another part. */
        attribute shack : ShackConfig {
            @CodeDiffers {
                what = "The code has no shack's settings; the call sign and the locator stand in "
                    + "profile.json.";
            }
        }
        attribute spots : SpotsConfig;
        attribute udp : UdpConfiguration;
        attribute auto : AutoConfig;
        attribute qso : QsoShared;
        attribute frequencies : WstxStationCommands::WorkingFrequencies;
        attribute log : WstxLogControl::LogShared;
    }
    attribute def ShackDocument {
        doc /* The shack's saved settings: the content of the file shack.json in
             the shack's folder, one JSON object of UTF-8 with the keys
             schemaVersion, revision, callsign, locator, continent and cqWords of
             ShackConfig, and spots, udp, auto, qso, frequencies and log for the
             configurations of these parts, each an object with the names of its values
             as keys; every name is written as WstxStationLink::WireNames says.
             continent is left out when absent. A key that is absent, given twice or not
             named, a value of another type and a value outside its rule make the file
             unusable. */
        @CodeDiffers {
            what = "The code has no shack document: the call sign and the locator stand in "
                + "profile.json.";
        }
        attribute schemaVersion : Integer = 1 {
            @CodeDiffers { what = "The code has no shack document."; }
        }
        attribute revision : Integer = 0 {
            doc /* The count of the saves of the file. */
            @CodeDiffers { what = "The code has no shack document."; }
        }
        attribute settings : ShackSettings;
    }
    attribute def StationMemory {
        doc /* The hidden store of one station: the records its parts want kept across
             the sessions of the station, as the collection of the records of each
             part. No menu shows it. The profile keeps it and defines no record. */
        attribute radio : RadioRecords;
        attribute audio : AudioRecords;
        attribute station : StartupRecords;
    }
    attribute def StrategyDefinitions {
        doc /* The saved strategies of the station. The profile keeps them in a
             definition file of their own (WstxProfileDocument::StrategiesFile). */
        attribute strategies : Strategy[0..*] ordered;
    }
    attribute def ProfileDocument {
        doc /* The saved profile of one station: its identity and its station config. It is
             the content of the file profile.json: one JSON object of UTF-8; every name
             in it is written as WstxStationLink::WireNames says.
             The object has the keys schemaVersion and profileId; the keys
             displayName, endpoint and connectionType of ProfileConfig; audio for
             AudioConfig; control for RadioConfig::control and, for a managed radio,
             radio for RadioConfig::agc; transmit, receive and qso for the configurations
             of these parts, each an object with the names of its values as keys; and
             native for the native connection. A file that also holds revision,
             callsign, locator, continent, cqWords, spots or udp is read without them:
             their values are not taken over.
             A key that is absent, given twice or not named, a value of another type
             and a value outside its rule make the file no valid profile. null is
             written for an absent inputDevice, outputDevice, control endpoint and
             origin; radio, native and radioAddress are left out when absent, and a
             null in their place is not valid. */
        attribute schemaVersion : Integer = 1 {
            doc /* 1 with the connection type 'standard', 2 with nativeFlex. */
        }
        attribute profileId : String {
            doc /* The identity of the profile: a UUID of version 4 in lower case, made
                 when the profile is created. No save changes it. */
        }
        attribute config : StationConfig;
        @FollowsSource { reference = "RFC 9562 section 5.4 (UUID version 4); RFC 8259 (JSON)"; }
    }

    item def OpenRequest {
        doc /* Open the profile of this folder, at station start
             (WstxProfileDocument::OpenProfile). Answered by ProfileFolder and the
             snapshots, or by OpenRefused. */
        attribute folder : String { doc /* The folder as the launch named it. */ }
        attribute shackFolder : String[0..1] {
            doc /* The shack's folder the launch named; absent: the default
                 (WstxProfileDocument::ShackFolder). */
            @CodeDiffers { what = "The code takes no shack's folder."; }
        }
    }
    item def CreateRequest {
        doc /* Make a profile in this folder (WstxProfileDocument::CreateProfile).
             Answered by ProfileCreated or OpenRefused. */
        attribute folder : String;
        attribute native : NativeIntent[0..1] {
            doc /* For a profile of the native connection: the receive antenna and at
                 most an address (WstxProfileDocument::NativeProfile); its clientId is
                 made by the profile. */ }
    }
    item def ProfileCreated { doc /* The profile is made. */ }
    enum def OpenRefusal {
        doc /* Why the profile cannot be opened or made. Nothing has been changed.
             resourceUnavailable: the folder, a file or a lock cannot be had.
             invalidProfile: profile.json is not a ProfileDocument.
             invalidRuntimeConfiguration: the NativeIntent of a CreateRequest is
             outside its rules.
             unsupportedSchema: the schemaVersion is none the station knows.
             unsupportedConnectionType: the connection type does not go with the
             schemaVersion.
             profileInUse: another station process holds the profile. */
        enum resourceUnavailable;
        enum invalidProfile;
        enum invalidRuntimeConfiguration;
        enum unsupportedSchema;
        enum unsupportedConnectionType;
        enum profileInUse;
    }
    item def OpenRefused { attribute reason : OpenRefusal; }
    item def ProfileFolder {
        doc /* The two folders, in which a function of the station keeps its definition
             files and its data files by itself. The profile gives them once, at
             station start, to the supervisor, which gives each function the
             folder of its files with its context. */
        attribute path : String {
            doc /* The profile's folder. While the station runs, no other station
                 process uses it. */ }
        attribute shackPath : String {
            doc /* The shack's folder (WstxProfileDocument::ShackFolder), which the
                 shack's stations share. */
            @CodeDiffers { what = "The code has no shack's folder."; }
        }
    }
    item def ShackSnapshot {
        doc /* The shack's settings as they are saved. The profile gives it at station
             start, after every save of them, and when another station has saved them.
             The supervisor gives each part its configuration from it, over that
             part's control interface. */
        attribute document : ShackDocument;
        attribute unusable : Boolean {
            doc /* shack.json cannot be used; document holds the settings as their
                 definitions give them. */
            @CodeDiffers { what = "The code has no shack's settings."; }
        }
    }
    item def SaveShack {
        doc /* Save these shack's settings in the place of the saved ones. It is the
             one way a change of a shared setting takes. */
        attribute expectedRevision : Integer {
            doc /* The revision of shack.json the save was made from. */ }
        attribute settings : ShackSettings;
    }
    item def ProfileSnapshot {
        doc /* The profile as it is saved. The profile gives it at station start and
             after every change of the document. The supervisor gives each part
             its configuration from it, over that part's control interface. */
        attribute document : ProfileDocument;
    }
    item def MemorySnapshot {
        doc /* The hidden store as it is kept. The profile gives it at station start and
             in answer to every SaveMemory: the new store when it is durable, the one
             before when it could not be kept. The supervisor gives each part its
             records from it, over that part's control interface. */
        attribute memory : StationMemory {
            @CodeDiffers {
                what = "The code keeps no hidden store: what it keeps of a station across "
                    + "sessions stands in files of their own, such as receive-startup.json.";
            }
        }
        attribute unreadable : Boolean {
            doc /* True when the kept store could not be read at station start; its
                 records are then as their definitions give them. */ }
    }
    item def SaveProfile {
        doc /* Save this station config in the place of the saved one. It is the one way
             a change of a setting takes: the operator's change reaches the supervisor,
             which brings it here.
             ProfileConfig::endpoint, ProfileConfig::connectionType and
             StationConfig::native are not taken from it. Without RadioConfig::agc for
             a managed radio, the saved one stays. */
        attribute config : StationConfig;
    }
    enum def SettingsCollection {
        doc /* The collections of settings whose members the operator creates, changes
             and deletes one by one. A member is named by its key, which stands once
             in its collection.
             strategies: StrategyDefinitions::strategies, keyed by Strategy::name
             without regard to letter case; held to WstxStrategies::StrategyForm.
             udpTargets: UdpConfiguration::targets of the shack's settings, keyed by
             UdpTarget::address; held to the rules of UdpTarget and UdpConfiguration.
             wantedList: DefinitionsSnapshot::wanted, keyed by WantedEntry::call as it is
             written; held to the rules of WantedEntry.
             txMacros: QsoShared::macros of the shack's settings, keyed by TxMacro::text;
             held to the rules of TxMacro.
             workingFrequencies: WorkingFrequencies::entries of the shack's settings,
             keyed by mode, band and frequency written as FT8 20m 14074000; held to the
             rules of WorkingFrequency and WorkingFrequencies. */
        enum strategies;
        enum udpTargets {
            @CodeDiffers {
                what = "The code has no collections of settings: it saves the UDP targets whole "
                    + "with the PUT of /udp.";
            }
        }
        enum wantedList {
            @CodeDiffers { what = "The code has no wanted list."; }
        }
        enum txMacros {
            @CodeDiffers { what = "The code has no Tx macros."; }
        }
        enum workingFrequencies {
            @CodeDiffers {
                what = "The code has no list of working frequencies: it holds one fixed table.";
            }
        }
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
        attribute macro : TxMacro[0..1] {
            doc /* For txMacros. */
            @CodeDiffers { what = "The code has no Tx macros."; }
        }
        attribute frequency : WstxStationCommands::WorkingFrequency[0..1] {
            doc /* For workingFrequencies. */ }
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
        attribute macro : TxMacro[0..1] {
            doc /* For txMacros. */
            @CodeDiffers { what = "The code has no Tx macros."; }
        }
        attribute frequency : WstxStationCommands::WorkingFrequency[0..1] {
            doc /* For workingFrequencies. */ }
    }
    item def DeleteEntry {
        doc /* Remove the member with the key. Answered by the snapshot of the
             collection or by SaveRefused. */
        attribute collection : SettingsCollection;
        attribute expectedRevision : Integer {
            doc /* The revision of the collection's file the command was made from. */ }
        attribute key : String;
    }
    item def ResetFrequencies {
        doc /* Put WSJT-X's default list in the place of the working frequencies.
             Answered by the snapshot of the collection or by SaveRefused. */
        attribute expectedRevision : Integer {
            doc /* The revision of the shack's file the command was made from. */ }
    }
    attribute def RenamedEntry {
        doc /* A member read under another key than its file gives it. */
        attribute savedName : String {
            doc /* The key in the file. */
            @CodeDiffers {
                what = "The code names it from, in configuration_note of the answers of "
                    + "/strategy.";
            }
        }
        attribute readName : String {
            doc /* The key it is held under. */
            @CodeDiffers {
                what = "The code names it to, in configuration_note of the answers of /strategy.";
            }
        }
    }
    item def DefinitionsSnapshot {
        doc /* The definition files as the profile keeps them. The profile gives it at
             station start and after every change of them. The supervisor gives
             each part its definitions from it, over that part's control interface. */
        attribute definitions : StrategyDefinitions {
            @CodeDiffers {
                what = "The code names no snapshot of the definition files: strategy.rs reads "
                    + "strategy.json itself.";
            }
        }
        attribute revision : Integer {
            doc /* The count of the changes of the strategies file; 0 without a file that
                 can be used. */ }
        attribute wanted : WantedEntry[0..*] ordered {
            doc /* The wanted list (WstxProfileDocument::WantedFile). */ }
        attribute wantedRevision : Integer {
            doc /* The count of the changes of the wanted list's file; 0 without a file
                 that can be used. */
            @CodeDiffers { what = "The code has no wanted list."; }
        }
        attribute unusable : Boolean {
            doc /* The strategies file cannot be used; definitions holds no strategy. */
            @CodeDiffers {
                what = "The code gives an unusable strategy.json as the error "
                    + "invalid_configuration.";
            }
        }
        attribute mostWanted : MostWantedList[0..1] {
            doc /* The Most Wanted list. Absent while the profile holds none. */ }
        attribute mostWantedUnusable : Boolean {
            doc /* The Most Wanted file cannot be used. */
            @CodeDiffers {
                what = "The code names it most_wanted_unreadable, in the answers of /strategy.";
            }
        }
        attribute countryFile : String[0..1] {
            doc /* The text of the country file the profile keeps
                 (WstxProfileDocument::CountryFileStore). Absent while it keeps none. */
            @CodeDiffers {
                what = "The code reads the country file from cty.dat in the profile's folder, "
                    + "else uses the one built in.";
            }
        }
        attribute countryFileUnusable : Boolean {
            doc /* The kept country file cannot be used. */
            @CodeDiffers {
                what = "The code names no unusable country file: without an uploaded one it uses "
                    + "the file built in.";
            }
        }
        attribute renamed : RenamedEntry[0..*] ordered {
            doc /* The strategies read under another name, in the order of the file.
                 Empty from the next change of the strategies. */ }
    }
    attribute def MostWantedList {
        doc /* The Most Wanted list the profile keeps (WstxProfileDocument::MostWantedFile). */
        attribute date : String { doc /* The UTC date of the download. */ }
        attribute rows : MostWantedRow[1..*] ordered;
    }
    item def UpdateCountryFile {
        doc /* Fetch the newest country file (WstxProfileDocument::CountryFileFetch).
             Answered by a DefinitionsSnapshot or a SaveRefused. */
    }
    item def UpdateMostWanted {
        doc /* Fetch the Most Wanted list anew (WstxProfileDocument::MostWantedFetch).
             Answered by a DefinitionsSnapshot or a SaveRefused. */
    }
    item def RuleFacts {
        doc /* The facts of other parts that the rules of a settings collection need when
             the profile applies them. The supervisor gives them at station start
             and whenever one changes. */
        attribute entityNames : String[0..*] {
            doc /* The names of the entities of the country file in use
                 (WstxLogControl::CountryFileState::entityNames). */ }
        attribute builtinNames : String[0..*] {
            doc /* The names of the built-in strategies
                 (WstxStrategies::StrategiesState::builtins). */
            @CodeDiffers {
                what = "The code passes no names: strategy.rs holds the built-in strategies "
                    + "itself.";
            }
        }
    }
    item def SaveMemory {
        doc /* Keep this hidden store in the place of the kept one. The supervisor
             brings it when a part has changed a record. */
        attribute memory : StationMemory {
            @CodeDiffers {
                what = "The code keeps no hidden store: what it keeps of a station across "
                    + "sessions stands in files of their own, such as receive-startup.json.";
            }
        }
    }
    enum def SaveRefusal {
        doc /* Why a save is refused. A refused save changes nothing.
             invalidSettings: a value of the settings is outside its rule.
             audioDeviceNotEndpoint: an audio device is no endpoint id of its
             direction.
             revisionConflict: a SaveShack or a command for a collection was made
             from another revision than that of its shared file.
             revisionExhausted: the profile's revision cannot count any further.
             storageUnavailable: the file cannot be written.
             entryExists: a CreateEntry, or an UpdateEntry to another key, names a key
             the collection holds.
             entryUnknown: an UpdateEntry or a DeleteEntry names a key the collection
             does not hold.
             collectionFull: a CreateEntry for a collection that holds as many members
             as its rules allow.
             downloadFailed: an UpdateMostWanted or an UpdateCountryFile got no list or
             no file.
             invalidCountryFile: the downloaded text does not read as a country file. */
        enum invalidSettings;
        enum audioDeviceNotEndpoint;
        enum revisionConflict;
        enum revisionExhausted;
        enum storageUnavailable;
        enum entryExists {
            @CodeDiffers {
                what = "The code has no settings collections and gives no such refusal.";
            }
        }
        enum entryUnknown {
            @CodeDiffers {
                what = "The code has no settings collections and gives no such refusal.";
            }
        }
        enum collectionFull {
            @CodeDiffers {
                what = "The code has no settings collections and gives no such refusal.";
            }
        }
        enum downloadFailed;
        enum invalidCountryFile {
            @CodeDiffers {
                what = "The code refuses a text that does not read as a country file with the "
                    + "code invalid_cty, the field text and the line.";
            }
        }
    }
    item def SaveRefused {
        doc /* The answer to a SaveProfile, a SaveShack, a CreateEntry, an
             UpdateEntry, a DeleteEntry, an UpdateMostWanted or an UpdateCountryFile the
             profile does not carry out. */
        attribute reason : SaveRefusal;
        attribute field : String[0..1] {
            doc /* For invalidSettings and audioDeviceNotEndpoint, the value that
                 is outside its rule, by its key in the file: displayName, callsign,
                 locator, audio.inputDevice, audio.outputDevice, control.mode,
                 control.endpoint, control.ptt or radio; for a member, by its keys as
             its part names them. */
        }
        attribute detail : String[0..1] {
            doc /* For downloadFailed: what failed; for invalidCountryFile: the line,
                 counted from 1. */ }
    }

    port def ProfileAccess {
        doc /* Written from the side of the function that uses the profile; the profile
             uses the conjugate.
             An OpenRequest is answered by ProfileFolder and then the snapshots, or by
             OpenRefused; a CreateRequest by ProfileCreated or OpenRefused.
             Each SaveProfile is answered by one ProfileSnapshot with the saved document
             or by one SaveRefused, each SaveShack by one ShackSnapshot or one
             SaveRefused; each SaveMemory by one MemorySnapshot; each UpdateMostWanted and
             each UpdateCountryFile by one DefinitionsSnapshot or one SaveRefused. The
             profile
             deals with one command after the other. */
        out item open : OpenRequest;
        out item make : CreateRequest;
        in item created : ProfileCreated;
        in item openRefused : OpenRefused {
            @CodeDiffers {
                what = "The code names no refusal: a profile it cannot open ends the start with "
                    + "the outcome's code.";
            }
        }
        in item folder : ProfileFolder;
        in item saved : ProfileSnapshot;
        in item shackSettings : ShackSnapshot {
            @CodeDiffers { what = "The code has no shack's settings."; }
        }
        in item definitions : DefinitionsSnapshot {
            @CodeDiffers {
                what = "The code names no snapshot of the definition files: strategy.rs reads "
                    + "strategy.json itself.";
            }
        }
        in item memory : MemorySnapshot {
            @CodeDiffers {
                what = "The code keeps no hidden store: what it keeps of a station across "
                    + "sessions stands in files of their own, such as receive-startup.json.";
            }
        }
        out item save : SaveProfile;
        out item saveShack : SaveShack {
            @CodeDiffers {
                what = "The code has no shack's settings; the call sign and the locator are saved "
                    + "with the PUT of /profile.";
            }
        }
        out item create : CreateEntry;
        out item update : UpdateEntry;
        out item delete : DeleteEntry;
        out item facts : RuleFacts;
        out item keep : SaveMemory;
        out item updateMostWanted : UpdateMostWanted {
            @CodeDiffers {
                what = "The code takes it as the POST of /strategy/most-wanted/download, which "
                    + "strategy.rs serves.";
            }
        }
        out item updateCountryFile : UpdateCountryFile {
            @CodeDiffers {
                what = "The code downloads no country file: it takes one the operator uploads "
                    + "with the PUT of /dxcc.";
            }
        }
        in item refused : SaveRefused;
    }
    interface def ProfileAccessLink {
        doc /* A function of the station uses the profile. */
        end client : ProfileAccess;
        end profile : ~ProfileAccess;
    }
}

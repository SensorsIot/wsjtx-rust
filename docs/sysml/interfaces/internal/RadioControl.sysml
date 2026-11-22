package WstxRadioControl {
    private import ScalarValues::*;
    private import WstxModelNotes::NotStated;
    private import WstxRadioProperties::Sideband;
    private import WstxRadioProperties::ModeValue;
    private import WstxRadioProperties::DataValue;
    private import WstxRadioProperties::Agc;
    private import WstxRadioProperties::Setting;
    private import WstxCat::CivFrame;
    private import WstxModelNotes::CodeDiffers;
    private import WstxModelNotes::FollowsSource;

    doc /* The configuration and the records of radio control; what the supervisor
        gives radio control and what radio control reports; the access of radio control
         to the serial port of a radio through the CAT adapter; and the control
         of a radio on its native network connection. */

    enum def ControlMode {
        enum disabled;
        enum cat;
    }
    enum def PttMode {
        enum disabled;
        enum cat;
    }
    attribute def RadioPlace {
        doc /* Where the serial port of the profile's radio is attached to the PC.
             An endpoint is at the same place when it has the same container, or the
             same USB hub and that hub is not a root hub. */
        attribute model : String { doc /* The model of the radio. */ }
        attribute container : String[0..1] {
            doc /* The device container Windows puts the port in. */ }
        attribute usbParent : String[0..1] {
            doc /* The USB hub the port's device hangs on. */ }
    }
    attribute def ControlSelection {
        doc /* How the operator wants the radio of the station controlled. It is intent:
             it says nothing of whether the radio is there.
             The rig and the endpoint are absent exactly when the mode is disabled. With
             the mode cat the endpoint is a text of 1 to 256 bytes without control
             characters.
             PTT by CAT needs the mode cat. */
        attribute mode : ControlMode = ControlMode::disabled {
            doc /* The control mode. disabled: the station controls no radio. cat: it
                 keeps a connection to the radio of the endpoint, reads it and sets
                 it. */ }
        attribute rig : RigModel[0..1] {
            doc /* The rig the operator has chosen, as in WSJT-X. */ }
        attribute endpoint : String[0..1] {
            doc /* The CAT port: the serial port, the rate and the address of the radio
                 the station connects to. */ }
        attribute ptt : PttMode = PttMode::disabled {
            doc /* The PTT method. disabled: the station cannot transmit. cat: transmit
                 keys the radio over the radio connection. */ }
    }
    attribute def RigModel {
        doc /* A rig of Hamlib's list (docs/sysml/data/hamlib-models.json). Radio control
             offers the rigs its catalogue has a connection for; each has its rules of
             connection in its own element (the IC-7300: RadioConnection). */
        attribute id : String { doc /* The catalogue's name of the rig: icom.ic7300. */ }
        attribute hamlibModel : Integer {
            doc /* Hamlib's number of the rig: 3073 for the IC-7300. */ }
        attribute abilities : RadioAbility[0..*] {
            doc /* What the rig can do over CAT, as its catalogue entry gives it from
                 Hamlib's capabilities of the rig. */
            @CodeDiffers {
                what = "The catalogue of server/src/radioControl/catalogue.rs states no abilities "
                    + "of a rig.";
            }
        }
        attribute txRanges : FrequencyRange[1..*] {
            doc /* The frequencies the rig transmits on, as its catalogue entry gives them
                 from Hamlib's transmit ranges of the rig. */
            @CodeDiffers {
                what = "The catalogue of server/src/radioControl/catalogue.rs states no transmit "
                    + "ranges of a rig.";
            }
        }
        attribute dialRange : FrequencyRange {
            doc /* The frequencies the station reads from the rig and sets on it, as its
                 catalogue entry gives them from Hamlib's receive ranges of the rig. A
                 frequency outside them is refused before anything is sent, and an answer
                 outside them is not a frequency. */
            @FollowsSource { reference = "Hamlib: the receive ranges of the rig's capabilities"; }
            @CodeDiffers {
                what = "The code holds 30000 to 74800000 Hz for every rig: Operation::validate in "
                    + "server/src/radioControl/mod.rs, the frequency codec of "
                    + "server/src/radioControl/codec.rs and Session::tune of "
                    + "server/src/flexAdapter/session.rs; the catalogue's frequency commands must "
                    + "state that range.";
            }
        }
    }
    attribute def FrequencyRange {
        doc /* The frequencies from lowHz to highHz, both included. */
        attribute lowHz : Integer {
            @CodeDiffers {
                what = "The code has no frequency range: a command of the catalogue gives its "
                    + "minimum, and the code holds 30000 Hz itself.";
            }
        }
        attribute highHz : Integer {
            @CodeDiffers {
                what = "The code has no frequency range: a command of the catalogue gives its "
                    + "maximum, and the code holds 74800000 Hz itself.";
            }
        }
    }
    enum def RadioAbility {
        doc /* A function of the radio that not every rig has over CAT.
             keyOverCat: key the transmitter. setPower: set the RF power.
             split: use a second VFO for transmit. setAgc: set the AGC.
             dataMode: switch the data mode. readAlc, readPower, readSwr: read the ALC,
             the output power and the SWR meter. */
        enum keyOverCat {
            @CodeDiffers {
                what = "The code names no ability of a rig: the catalogue of "
                    + "server/src/radioControl/catalogue.rs states none.";
            }
        }
        enum setPower {
            @CodeDiffers {
                what = "The code names no ability of a rig: the catalogue of "
                    + "server/src/radioControl/catalogue.rs states none.";
            }
        }
        enum split;
        enum setAgc {
            @CodeDiffers {
                what = "The code names no ability of a rig: the catalogue of "
                    + "server/src/radioControl/catalogue.rs states none.";
            }
        }
        enum dataMode {
            @CodeDiffers {
                what = "The code names no ability of a rig: the catalogue of "
                    + "server/src/radioControl/catalogue.rs states none.";
            }
        }
        enum readAlc {
            @CodeDiffers {
                what = "The code names no ability of a rig: the catalogue of "
                    + "server/src/radioControl/catalogue.rs states none.";
            }
        }
        enum readPower {
            @CodeDiffers {
                what = "The code names no ability of a rig: the catalogue of "
                    + "server/src/radioControl/catalogue.rs states none.";
            }
        }
        enum readSwr {
            @CodeDiffers {
                what = "The code names no ability of a rig: the catalogue of "
                    + "server/src/radioControl/catalogue.rs states none.";
            }
        }
    }
    attribute def RadioConfig {
        doc /* The configuration of radio control: what the operator sets of the radio
             of the station. A radio is managed when control.mode is cat, control.rig
             is a rig of radio control's catalogue and control.endpoint reads as a
             connection of that rig. */
        attribute control : ControlSelection;
        attribute agc : Agc[0..1] {
            doc /* The AGC radio control sets on the radio at every connection and
                 within a change of the operating selection. Present exactly for a
                 managed radio, and slow until the operator sets another. */ }
        attribute powers : BandPower[0..*] {
            doc /* The output power of each band that radio control sets on the radio
                 (WstxRadioSetup::ManagedPower), at most one entry for a band. A band
                 without one leaves the radio's power as it is. */ }
        attribute discoverAtStart : Boolean = true {
            doc /* Whether radio control makes sure at station start which radio is the
                 profile's (DiscoverRadio). False: the profile's control stays as saved,
                 whatever answers on its port. Kept in radio-discovery.json of the
                 profile's folder; a file that cannot be read, or one of another profile,
                 reads as false. */ }
    }
    attribute def BandPower {
        doc /* The output power of one band. */
        attribute band : String { doc /* An ADIF band name in lower case. */ }
        attribute powerPct : Integer {
            doc /* In percent of the radio's full power, from 1 to 100. */
            @CodeDiffers {
                what = "The code keeps no power of a band: Radio::power_limit_pct of "
                    + "server/src/profile/profile.rs is one limit of the Tx level for every band.";
            }
        }
    }
    attribute def RadioRecords {
        doc /* What radio control wants kept across the sessions of the station. No
             menu shows a record. */
        attribute keyingConfirmed : Boolean = false {
            doc /* The operator has confirmed once that opening a serial port of this
                 PC cannot key a transmitter. While it is false radio control opens no
                 port to look for a radio. */ }
    }
    item def ControlAssignment {
        doc /* The configuration of radio control, given at station start and whenever
             the station config changes. An assignment whose RadioConfig::control
             differs from the one before (the rig, the endpoint or the PTT method) is
             another radio connection; another AGC is set on the running connection
             (ManagedAgc), and a change elsewhere in the station config changes
             nothing. */
        attribute config : RadioConfig;
    }
    item def RadioMemory {
        doc /* The records of radio control. The supervisor gives them at station
             start, as the profile holds them. Radio control gives them whenever it
             has changed one, and the supervisor answers with the records as the
             profile holds them then: the changed ones when the profile has kept them,
             the ones before when it could not. A changed record counts only when it
             has come back. */
        attribute records : RadioRecords;
    }

    item def TransmitterActivity {
        doc /* What the transmitter does, given at every change. It is at rest when
             the three are false. */
        attribute armed : Boolean;
        attribute tuning : Boolean;
        attribute transmitting : Boolean;
    }

    enum def CatState {
        doc /* The state of the connection to the radio.
             closed: not open.
             connecting: the port is being opened and the radio asked for the first
             time.
             ready: the radio answered.
             closing: the connection is being closed, or its port did not close.
             unavailable: the connection failed and its port is closed. */
        enum closed;
        enum connecting;
        enum ready;
        enum closing;
        enum unavailable;
    }
    enum def ControlError {
        doc /* Why radio control did not do what was asked, or lost the radio.
             invalidConfiguration: the endpoint names no radio connection the station
             has.
             invalidRequest: a value of the request is outside its range.
             unsupported: the station has no such operation for this radio.
             staleContext: the request names another connection than the current
             one.
             busy: another exchange holds radio control, or the radio transmits.
             unavailable: no radio is connected, or the port cannot be opened.
             resourceInUse: another station or another program holds the port.
             cancelled: the request was withdrawn, or the connection is being closed.
             timeout: the radio did not answer in time.
             protocol: the radio answered with something the link's source does not
             allow.
             limit: more arrived on the link than an exchange takes.
             rejected: the radio refused the command.
             partialWrite: the port did not take a whole frame.
             readbackMismatch: the radio acknowledged a change and then reported
             another value.
             indeterminate: the radio acknowledged a change and the value could not be
             read.
             failedClose: the port did not close. */
        enum invalidConfiguration;
        enum invalidRequest;
        enum unsupported;
        enum staleContext;
        enum busy;
        enum unavailable;
        enum resourceInUse;
        enum cancelled;
        enum timeout;
        enum protocol;
        enum limit;
        enum rejected;
        enum partialWrite;
        enum readbackMismatch;
        enum indeterminate;
        enum failedClose;
    }
    attribute def Fact {
        doc /* One value the radio itself reported, and how far it can be relied on.
             Before the first answer every feature is absent and confirmed is false. */
        attribute querySequence : Integer[0..1] {
            doc /* The place of the answer among all answers of this connection, from
                 1. */ }
        attribute observedAtMs : Integer[0..1] {
            doc /* When the answer arrived, in milliseconds since station start. */ }
        attribute confirmed : Boolean {
            doc /* The value is what the radio last said and nothing has happened
                 since that could have changed it. */ }
    }
    attribute def FrequencyFact :> Fact { attribute hz : Integer[0..1]; }
    attribute def ModeFact :> Fact { attribute mode : ModeValue[0..1]; }
    attribute def DataFact :> Fact { attribute data : DataValue[0..1]; }
    attribute def TransmitFact :> Fact { attribute transmitting : Boolean[0..1]; }
    attribute def SplitFact :> Fact { attribute split : Boolean[0..1]; }
    attribute def RadioFacts {
        doc /* The five things radio control reads from the radio. */
        attribute frequency : FrequencyFact;
        attribute mode : ModeFact;
        attribute data : DataFact;
        attribute rxTx : TransmitFact;
        attribute split : SplitFact;
    }
    enum def AutomaticCatCondition {
        doc /* Where the keeping of the radio connection stands.
             disabled: the profile controls no radio by CAT.
             waitingForDevice: an attempt to connect is due or has not been made.
             connecting, ready, closing: as CatState.
             retryWaiting: the last attempt failed; the next one follows after a wait.
             quarantined: the port did not close; no attempt follows until the station
             is started again. */
        enum disabled;
        enum waitingForDevice;
        enum connecting;
        enum ready;
        enum retryWaiting;
        enum closing;
        enum quarantined;
    }
    attribute def AutomaticCatStatus {
        attribute condition : AutomaticCatCondition;
        attribute error : ControlError[0..1] {
            doc /* Why the last attempt failed; resourceInUse when the port is held by
                 another program or station. */ }
        attribute retryAfterMs : Integer[0..1] {
            doc /* The time to the next attempt, present in the condition
                 retryWaiting. */ }
    }
    item def RadioStatus {
        doc /* The radio connection at the moment it is read. */
        attribute connectionNumber : Integer {
            doc /* Counts the attempts to connect since station start; 0 before the
                 first. A request names the connection it is meant for. */
            @CodeDiffers {
                what = "The status gives it as connection_generation (Recording::radio_view in "
                    + "server/src/radioControl/radio_connection.rs).";
            }
        }
        attribute 'state' : CatState;
        attribute error : ControlError[0..1];
        attribute deviceId : String[0..1] {
            doc /* The name Windows gives the device of the port. */ }
        attribute effectiveBaud : Integer[0..1] {
            doc /* The rate the radio answered at. */ }
        attribute model : String[0..1] {
            doc /* The name of ControlSelection::rig; absent while the profile controls
                 none by CAT. */ }
        attribute abilities : RadioAbility[0..*] {
            doc /* RigModel::abilities of the rig; empty while the profile controls none
                 by CAT. */
            @CodeDiffers {
                what = "The status gives no abilities of the rig (Recording::radio_view in "
                    + "server/src/radioControl/radio_connection.rs).";
            }
        }
        attribute txRanges : FrequencyRange[0..*] {
            doc /* RigModel::txRanges of the rig; empty while the profile controls none
                 by CAT. */
            @CodeDiffers {
                what = "The status gives no transmit ranges of the rig (Recording::radio_view in "
                    + "server/src/radioControl/radio_connection.rs).";
            }
        }
        attribute facts : RadioFacts;
        attribute automatic : AutomaticCatStatus;
        attribute place : RadioPlace[0..1] {
            doc /* Where the profile's serial port is attached, for the sound endpoints
                 of the same radio; absent while the profile names no port that is
                 present. */ }
        attribute keyingConfirmed : Boolean {
            doc /* RadioRecords::keyingConfirmed. */ }
    }
    enum def SettingOutcome {
        doc /* What came of setting a value radio control keeps on the radio.
             unchanged: the radio already had the wanted value.
             written: it was set and read back.
             notApplied: it could not be read or set; the status's error says why. */
        enum unchanged;
        enum written;
        enum notApplied {
            @CodeDiffers {
                what = "The AGC status gives the radio's error code in place of notApplied "
                    + "(Owner::record in server/src/radioControl/radio_agc.rs).";
            }
        }
    }
    enum def SettingTrigger {
        doc /* connect: a connection became ready. selection: ApplyAgc or ApplyPower.
             band: the dial radio control confirmed lies on another band. */
        enum 'connect';
        enum selection;
        enum band;
    }
    item def AgcStatus {
        doc /* The AGC the station wants on the radio and what came of setting it. */
        attribute target : Agc[0..1] {
            doc /* RadioConfig::agc; absent while the configuration has none. */ }
        attribute connectionNumber : Integer[0..1] {
            @CodeDiffers {
                what = "The status gives it as connection_generation (event in "
                    + "server/src/radioControl/radio_agc.rs).";
            }
        }
        attribute value : Agc[0..1] { doc /* What the radio reported last. */ }
        attribute outcome : SettingOutcome[0..1] {
            doc /* Absent until the radio has been asked. */ }
        attribute error : ControlError[0..1];
        attribute trigger : SettingTrigger[0..1];
    }
    item def PowerStatus {
        doc /* The output power the station wants on the radio and what came of setting
             it. */
        attribute band : String[0..1] { doc /* The station's band. */ }
        attribute targetPct : Integer[0..1] {
            doc /* The band's entry of RadioConfig::powers; absent without one. */ }
        attribute connectionNumber : Integer[0..1];
        attribute valuePct : Integer[0..1] {
            doc /* What the radio reported last. */ }
        attribute outcome : SettingOutcome[0..1] {
            doc /* Absent until the radio has been asked. */ }
        attribute error : ControlError[0..1];
        attribute trigger : SettingTrigger[0..1];
    }

    enum def ControlOperation {
        doc /* What the supervisor can ask of the connected radio.
             The five reads ask the radio for one fact each.
             setFrequency, setMode and setData change one value.
             receiveSetup sets mode, data mode and frequency in this order. */
        enum readFrequency;
        enum readMode;
        enum readData;
        enum readRxTx;
        enum readSplit;
        enum setFrequency;
        enum setMode;
        enum setData;
        enum receiveSetup;
    }
    item def ReserveRadio {
        doc /* Keep radio control for a change of several steps: until ReleaseReservation
             only requests of this reservation are carried out, and the radio is not
             read in between. */
        attribute waitMs : Integer {
            doc /* How long to wait for a running exchange to end. */
            @CodeDiffers {
                what = "The reservation takes a deadline, an Instant, in place of a wait "
                    + "(Actor::reserve_transition in server/src/radioControl/actor.rs).";
            }
        }
    }
    item def RadioReserved { doc /* Radio control is kept for the change. */ }
    item def ReleaseReservation { doc /* The change is over. */ }
    item def OperationRequest {
        doc /* One operation. The values an operation does not use are absent. */
        attribute operation : ControlOperation;
        attribute connectionNumber : Integer {
            @CodeDiffers {
                what = "The request names it as Authority::connection_generation (Request in "
                    + "server/src/radioControl/mod.rs).";
            }
        }
        attribute withinMs : Integer {
            doc /* The time the supervisor gives the operation. */
            @CodeDiffers {
                what = "The request carries a deadline, an Instant (Request::deadline in "
                    + "server/src/radioControl/mod.rs).";
            }
        }
        attribute frequencyHz : Integer[0..1];
        attribute sideband : Sideband[0..1];
        attribute filterNumber : Integer[0..1] {
            @CodeDiffers {
                what = "The operation names it filter (Operation in "
                    + "server/src/radioControl/mod.rs).";
            }
        }
        attribute data : Boolean[0..1];
        attribute dataFilterNumber : Integer[0..1] {
            @CodeDiffers {
                what = "The operation names it data_filter (Operation::ReceiveSetup in "
                    + "server/src/radioControl/mod.rs).";
            }
        }
    }
    item def WithdrawRequest {
        doc /* Give up the OperationRequest in work; it ends with cancelled. */
    }
    item def OperationDone {
        attribute operation : ControlOperation;
        attribute facts : RadioFacts;
    }
    item def ControlRefused {
        doc /* A request was not carried out, or not to its end. */
        attribute error : ControlError;
    }
    item def ApplyAgc {
        doc /* Set RadioConfig::agc now, inside a reservation. The answer is the next
             AgcStatus. */
    }
    item def ApplyPower {
        doc /* Set the output power of the band now, inside a reservation. The answer is
             the next PowerStatus. */
        attribute band : String { doc /* An ADIF band name in lower case. */ }
    }

    enum def PortState {
        doc /* What detection found on one serial port.
             stationCat: the port of this station's own radio connection; it is not
             opened a second time.
             notRadioBridge: no serial adapter of a radio the station knows; not opened.
             notProbed: the time for detection had run out.
             inUse: another station or another program holds it.
             unavailable: it could not be opened.
             noReply: opened, and no radio answered.
             identified: a radio answered. */
        enum stationCat;
        enum notRadioBridge;
        enum notProbed;
        enum inUse;
        enum unavailable;
        enum noReply;
        enum identified;
    }
    attribute def IdentifiedRadio {
        attribute model : String[0..1] {
            doc /* Absent for an identity the station does not know. */ }
        attribute identity : String { doc /* Two hexadecimal digits. */ }
        attribute civAddress : String { doc /* Two hexadecimal digits. */ }
        attribute baud : Integer;
        attribute stationCat : Boolean {
            doc /* The station can control this model. */ }
    }
    attribute def PortReport {
        attribute comPort : Integer {
            doc /* The number of the COM port. */
            @CodeDiffers {
                what = "The report gives the port as port, the text COMn (detect in "
                    + "server/src/radioControl/radio_setup.rs).";
            }
        }
        attribute friendlyName : String[0..1];
        attribute vendorId : String[0..1] {
            @CodeDiffers {
                what = "The report gives it as vid (detect in "
                    + "server/src/radioControl/radio_setup.rs).";
            }
        }
        attribute productId : String[0..1] {
            @CodeDiffers {
                what = "The report gives it as pid (detect in "
                    + "server/src/radioControl/radio_setup.rs).";
            }
        }
        attribute instanceId : String;
        attribute 'state' : PortState;
        attribute radios : IdentifiedRadio[0..*];
        attribute place : RadioPlace[0..1] {
            doc /* Where the port is attached; present with a radio. */ }
    }
    enum def Severity {
        doc /* What a value of a menu item means for operating with this station. */
        enum ok;
        enum information;
        enum advice;
        enum blocking;
        enum unreadable;
    }
    attribute def SettingFinding {
        attribute setting : Setting;
        attribute value : Integer[0..1] { doc /* Absent when the radio did not give it. */ }
        attribute recommended : Integer[0..1] {
            doc /* The value the station would set; absent for an item it never
                 sets. */ }
        attribute severity : Severity;
    }
    attribute def RadioProposal {
        doc /* The control the station proposes for the one radio it can control. */
        attribute comPort : Integer {
            @CodeDiffers {
                what = "The proposal gives the port as port, the text COMn (detect in "
                    + "server/src/radioControl/radio_setup.rs).";
            }
        }
        attribute model : String;
        attribute control : ControlSelection;
        attribute agc : Agc;
        attribute place : RadioPlace[0..1];
    }
    item def DetectRadios {
        doc /* Look for radios on the serial ports of the PC. */
        attribute keyingInhibitConfirmed : Boolean;
    }
    item def DetectionReport {
        attribute ports : PortReport[0..*];
        attribute supportedRadios : Integer;
        attribute proposal : RadioProposal[0..1] {
            doc /* Present when exactly one radio was found that the station can
                 control. */ }
        attribute settingsPort : Integer[0..1] {
            @CodeDiffers {
                what = "The report gives it as port inside settings (detect in "
                    + "server/src/radioControl/radio_setup.rs).";
            }
        }
        attribute settings : SettingFinding[0..*] {
            doc /* The menu items of the first IC-7300 found. */ }
    }
    enum def DetectRefusal {
        doc /* confirmationRequired: keyingInhibitConfirmed is false.
             busy: a detection is running.
             invalidRequest: the profile uses a radio on its native network connection.
             radioUnavailable: the ports of the PC cannot be read. */
        enum confirmationRequired;
        enum busy;
        enum invalidRequest;
        enum radioUnavailable;
    }
    item def DetectRefused { attribute reason : DetectRefusal; }

    item def ApplyRecommended {
        doc /* Set the menu items of the radio to the values the station recommends. */
        attribute connectionNumber : Integer {
            @CodeDiffers {
                what = "The request names it connection_generation (apply_route in "
                    + "server/src/radioControl/radio_setup.rs).";
            }
        }
    }
    attribute def WrittenItem {
        attribute setting : Setting;
        attribute value : Integer;
    }
    item def SettingsOutcome {
        doc /* What an apply wrote. */
        attribute written : WrittenItem[0..*];
        attribute failedItem : Setting[0..1];
        attribute error : ControlError[0..1] { doc /* Present with failedItem. */ }
    }
    enum def SettingsRefusal {
        doc /* radioUnavailable: the radio is not connected and ready.
             stateConflict: the request names another connection.
             transmitArmed: the transmitter is armed.
             unsupportedRadio: the radio is no IC-7300.
             radioError: the radio did not answer the first reads. */
        enum radioUnavailable;
        enum stateConflict;
        enum transmitArmed;
        enum unsupportedRadio;
        enum radioError;
    }
    item def SettingsRefused {
        attribute reason : SettingsRefusal;
        attribute error : ControlError[0..1] { doc /* Present with radioError. */ }
    }
    item def DiscoverRadio {
        doc /* At station start, before the radio connection is first opened: make sure
             which radio is the profile's. */
    }
    item def RadioDiscovered {
        doc /* Another radio than the profile names is this station's. The supervisor
             saves it as the profile's control. */
        attribute control : ControlSelection;
        attribute model : String;
        attribute place : RadioPlace[0..1];
    }
    item def RadioKept {
        doc /* The profile's control stays as it is. */
    }

    port def RadioControl {
        doc /* Written from the supervisor's side; radio control uses the conjugate.
             ReserveRadio is answered by RadioReserved or ControlRefused; OperationRequest
             by OperationDone or ControlRefused; DetectRadios by DetectionReport or
             DetectRefused; ApplyRecommended by SettingsOutcome or
             SettingsRefused; DiscoverRadio by RadioDiscovered or RadioKept; a
             RadioMemory of radio control by a RadioMemory of the supervisor.
             RadioStatus, AgcStatus and PowerStatus are given at every change. */
        out item assignment : ControlAssignment {
            @CodeDiffers {
                what = "The supervisor gives no assignment: cat_tick in "
                    + "server/src/supervisor/authorization_http.rs reads the saved "
                    + "profile at every tick "
                    + "and hands its gate to Recording::cat_maintain.";
            }
        }
        out item kept : RadioMemory;
        out item transmitter : TransmitterActivity;
        out item reserve : ReserveRadio;
        out item release : ReleaseReservation;
        out item request : OperationRequest;
        out item withdraw : WithdrawRequest {
            @CodeDiffers {
                what = "The supervisor withdraws a request by setting its flag Request::cancelled "
                    + "(server/src/radioControl/mod.rs).";
            }
        }
        out item applyAgc : ApplyAgc {
            @CodeDiffers {
                what = "The supervisor calls on_selection of "
                    + "server/src/radioControl/radio_agc.rs inside its reservation.";
            }
        }
        out item applyPower : ApplyPower {
            @CodeDiffers {
                what = "The code has no such request: radio control sets no output power.";
            }
        }
        out item detect : DetectRadios;
        out item applyRecommended : ApplyRecommended {
            @CodeDiffers {
                what = "The supervisor calls apply of server/src/radioControl/radio_setup.rs.";
            }
        }
        out item discover : DiscoverRadio;
        in item reserved : RadioReserved;
        in item done : OperationDone;
        in item refused : ControlRefused;
        in item detection : DetectionReport;
        in item detectRefused : DetectRefused {
            @CodeDiffers {
                what = "A refusal is the Err text of detect in "
                    + "server/src/radioControl/radio_setup.rs.";
            }
        }
        in item settingsOutcome : SettingsOutcome {
            @CodeDiffers {
                what = "The outcome is the Ok value of apply in "
                    + "server/src/radioControl/radio_setup.rs.";
            }
        }
        in item settingsRefused : SettingsRefused {
            @CodeDiffers {
                what = "A refusal is the Err text of apply in "
                    + "server/src/radioControl/radio_setup.rs.";
            }
        }
        in item discovered : RadioDiscovered;
        in item radioKept : RadioKept {
            @CodeDiffers {
                what = "Discovery answers None when the profile's control stays "
                    + "(discover_within in server/src/radioControl/radio_setup.rs).";
            }
        }
        in item status : RadioStatus;
        in item agc : AgcStatus;
        in item power : PowerStatus;
        in item keep : RadioMemory;
    }
    interface def StationRadioControl {
        doc /* The supervisor commands radio control; radio control reports the
             radio. */
        end station : RadioControl;
        end radioControl : ~RadioControl;
    }

    item def OpenRadio {
        doc /* Open the serial port for this station alone. */
        attribute comPort : Integer {
            doc /* The number of the COM port, 1 to 256. */
            @CodeDiffers {
                what = "The CAT adapter takes the number as port (Hardware::open in "
                    + "server/src/radioControl/radio_setup.rs).";
            }
        }
    }
    item def RadioOpened {
        attribute deviceId : String {
            doc /* The name Windows gives the device of the port. Two ports of one
                 device have the same name. */ }
    }
    item def ReserveDevice {
        doc /* Keep the radio on this port for this station until the station process
             ends, also while its port is closed. */
        attribute comPort : Integer {
            @CodeDiffers {
                what = "The CAT adapter takes the number as port (Hardware::reserve in "
                    + "server/src/radioControl/radio_setup.rs).";
            }
        }
    }
    item def DeviceReserved { doc /* The radio is kept for this station. */ }
    item def AccessRefused {
        doc /* An OpenRadio or a ReserveDevice was not granted: resourceInUse when
             another station or another program has the radio, otherwise unavailable or
             invalidConfiguration. */
        attribute error : ControlError;
    }
    item def SetRate {
        doc /* Set the serial line to this rate (WstxCat::SerialLine). */
        attribute baud : Integer;
    }
    item def ReceivedBytes {
        doc /* What arrived on the port, as it arrived: not cut into frames. */
    }
    item def CloseRadio { doc /* Close the port and give the radio up. */ }
    item def RadioClosed { doc /* The port is closed. */ }
    item def CloseFailed {
        doc /* The port did not close. The radio stays with this station. */
    }
    port def RadioAccess {
        doc /* Written from radio control's side. OpenRadio is answered by RadioOpened or
             AccessRefused, ReserveDevice by DeviceReserved or AccessRefused, CloseRadio
             by RadioClosed or CloseFailed. */
        out item open : OpenRadio;
        out item reserve : ReserveDevice;
        out item rate : SetRate;
        out item sent : CivFrame;
        out item close : CloseRadio;
        in item opened : RadioOpened;
        in item reserved : DeviceReserved;
        in item refused : AccessRefused;
        in item received : ReceivedBytes;
        in item closed : RadioClosed;
        in item closeFailed : CloseFailed {
            @CodeDiffers {
                what = "A close that fails answers Err(Error::FailedClose) (Transport::close in "
                    + "server/src/radioControl/executor.rs).";
            }
        }
    }
    interface def RadioAccessLink {
        doc /* Between radio control and the CAT adapter of its station. */
        end radioControl : RadioAccess;
        end catAdapter : ~RadioAccess;
    }

    item def TuneRadio {
        doc /* Bring the radio's receiver to this frequency. */
        attribute frequencyHz : Integer;
        attribute withinMs : Integer {
            @CodeDiffers {
                what = "The tune takes a deadline, an Instant (Session::tune in "
                    + "server/src/flexAdapter/session.rs).";
            }
        }
    }
    item def WithdrawTune { doc /* Give up the TuneRadio that is in work. */ }
    item def RadioTuned {
        attribute frequencyHz : Integer { doc /* What the radio confirmed. */ }
    }
    item def TuneRefused { attribute error : ControlError; }
    port def NativeControlPort {
        doc /* Written from radio control's side; the adapter of the native connection
             uses the conjugate. TuneRadio is answered by RadioTuned or TuneRefused. */
        @NotStated {
            what = "the items that carry the profile's intent for the native "
                + "connection to the adapter and the state of its session back; "
                + "their data stand in the adapter's function file";
        }
        out item tune : TuneRadio;
        out item withdraw : WithdrawTune {
            @CodeDiffers {
                what = "Radio control withdraws a tune by setting the cancelled flag it gave "
                    + "Session::tune (server/src/flexAdapter/session.rs).";
            }
        }
        in item tuned : RadioTuned;
        in item refused : TuneRefused;
    }
    interface def NativeControl {
        doc /* Radio control and the adapter of a radio's native network connection. */
        end radioControl : NativeControlPort;
        end adapter : ~NativeControlPort;
    }
}

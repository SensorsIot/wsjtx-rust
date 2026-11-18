package WstxTransmitControl {
    private import ScalarValues::*;
    private import WstxModeProcessing::Mode;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModelNotes::NotStated;

    doc /* The configuration of the transmit function, its commands, their answers, and
         what transmit reports: the transmit state with its causes, the outcome of every
         request, and the audio drive. The supervisor gives the configuration, Halt
         and the station's facts over TransmitControlPort. Arm,
         Disarm, Abort, SetTune and StepBegins come from qso
         alone, over the operating chain (MessageToSend); the operator's starts and Tune
         reach transmit that way too. */

    attribute def TransmitConfig {
        doc /* The configuration of the transmit function: what the operator sets of
             transmitting. */
        attribute levelMode : LevelMode = LevelMode::automatic {
            doc /* How the audio drive is set. */ }
        attribute levels : BandLevel[0..*] {
            doc /* The audio drive of each band, at most one entry for a band. A band has
                 none until the operator has set one or transmit has found one. */ }
        attribute tuneSeconds : Integer = 90 {
            doc /* The Tune limit: how long a Tune tone may last. From 1 to 300. */ }
        attribute split : WstxKeying::SplitOperation = WstxKeying::SplitOperation::none {
            doc /* Split operation (WstxTransmitState::SplitRule). */ }
    }
    enum def LevelMode {
        doc /* How the audio drive is set.
             manual: the operator sets it, with a slider as WSJT-X's Pwr.
             automatic: transmit finds it when the Tune tone is switched on and corrects
             it in each transmission; the operator sets none. */
        enum manual;
        enum automatic;
    }
    attribute def BandLevel {
        doc /* The audio drive of one band. */
        attribute band : String { doc /* An ADIF band name in lower case. */ }
        attribute levelDb : Integer {
            doc /* How far transmit turns its audio down, in whole dB, within the range
                 of the audio drive. */ }
    }

    enum def ArmState {
        doc /* The transmit state of the station.
             disarmed: off; no request is admitted.
             armed: on. */
        enum disarmed;
        enum armed;
    }
    enum def ArmCause {
        doc /* Who switched the transmit state on.
             operator: a start of the operator or of an agent.
             auto: a start of Auto. */
        enum operator;
        enum auto;
    }
    enum def DisarmCause {
        doc /* Why the transmit state went off.
             startup: the station started.
             halt: Halt.
             contactCompleted, contactCancelled, modeChanged, bandChanged,
             txWatchdog: the stop the contact gives with Disarm or Abort;
             txWatchdog is the contact's Tx watchdog, its repetition limit.
             refused: a request was refused.
             failed: a transmission failed at the radio's switch, or transmit itself
             failed.
             deviceLost: the radio, the output device or the transmit capability was
             lost. */
        enum halt;
        enum contactCompleted;
        enum contactCancelled;
        enum txWatchdog;
        enum refused;
        enum failed;
        enum deviceLost;
        enum startup;
        enum modeChanged;
        enum bandChanged;
    }
    enum def Capability {
        doc /* Whether the station can transmit.
             unsupported: the profile is not set up for it.
             unavailable: it is set up, and the radio is not ready.
             available: it can. */
        enum unsupported;
        enum unavailable;
        enum available;
    }
    enum def PttState {
        doc /* released: the radio's transmit switch is off, confirmed by the radio.
             keyed: it is on, confirmed.
             indeterminate: a key or a release was not confirmed; the radio may
             transmit. */
        enum released;
        enum keyed;
        enum indeterminate;
    }
    enum def HaltState {
        doc /* The result of the last Halt.
             idle: nothing was keyed.
             stopped: the release was confirmed.
             pending: the release is not confirmed. */
        enum idle;
        enum pending;
        enum stopped;
    }
    enum def StartupRelease {
        doc /* pending: the radio has not yet said whether it transmits.
             notNeeded: it did not transmit, or this run of the station had keyed before.
             released: it transmitted and the one release was confirmed.
             failed: the one release was not confirmed. */
        enum pending;
        enum notNeeded;
        enum released;
        enum failed;
    }

    enum def TransmitRefusal {
        doc /* Why transmit refuses a request or a command.
             transmitUnsupported, radioUnavailable: the Capability is not available; and
             radioUnavailable also while the switch is indeterminate.
             notArmed: the transmit state is off.
             busy: Tune is on, a request waits or plays, or the radio's switch is in use.
             staleRequest: another mode than the station's.
             clockNotSynchronized, misalignedPeriod, stalePeriod: the start cannot be
             planned (StartWindow).
             packRefused, frequencyOutOfRange: the modes part does not encode the
             message; and frequencyOutOfRange for a Tune offset outside its range.
             duplicateSequence: a sequence that is not higher than every one before.
             audioStarted: the audio of the request for the same period has started. */
        enum transmitUnsupported;
        enum notArmed;
        enum audioStarted;
        enum duplicateSequence;
        enum staleRequest;
        enum clockNotSynchronized;
        enum misalignedPeriod;
        enum stalePeriod;
        enum packRefused;
        enum frequencyOutOfRange;
        enum busy;
        enum radioUnavailable;
    }
    enum def TransmitFailure {
        doc /* Why a transmission that was begun has failed.
             pttTimeout, pttRejected, pttReadbackMismatch, pttIndeterminate: the key or
             the release was not confirmed, with the reason radio control gives.
             radioLost: the radio or the transmit capability went away.
             audioUnavailable: the output device did not open.
             audioDeviceLost: the output device failed.
             audioStalled: the output device did not report the end in time.
             ownerFault: transmit itself failed. */
        enum pttTimeout;
        enum pttRejected;
        enum pttReadbackMismatch;
        enum pttIndeterminate;
        enum radioLost;
        enum audioUnavailable;
        enum audioDeviceLost;
        enum audioStalled;
        enum ownerFault;
    }
    enum def OutcomeKind {
        doc /* accepted: the request waits for its period.
             replaced: a later request took its place.
             started: its audio has started.
             completed: its last sample was played and the release confirmed.
             halted: Halt ended it.
             aborted: Abort ended it.
             refused: it was not admitted, or was dropped before it was keyed.
             failed: it ended with a TransmitFailure. */
        enum accepted;
        enum replaced;
        enum started;
        enum completed;
        enum halted;
        enum refused;
        enum failed;
        enum aborted;
    }
    item def TransmitOutcome {
        doc /* One step in the life of a request. Transmit gives one for every change;
             no outcome is made from a lost answer or a wait that ran out. */
        attribute outcomeSequence : Integer {
            doc /* Counts the outcomes since station start, from 1. */ }
        attribute requestSequence : Integer;
        attribute kind : OutcomeKind;
        attribute refusal : TransmitRefusal[0..1] { doc /* Present for refused. */ }
        attribute failure : TransmitFailure[0..1] { doc /* Present for failed. */ }
        attribute audioStartUtcMs : Integer[0..1] {
            doc /* The station time at which the audio started. Present for started and
                 completed, and for failed when the audio had started. */ }
    }
    attribute def StartWindow {
        doc /* When a transmission of a period may start; qso chooses the period of a
             request by it.
             The audio of a transmission that starts on time begins the audio delay
             after the period start.
             The window of a period is open until the earlier of two moments: the
             latest share of the period has passed, or the audio of a whole frame that
             started on time would have ended (the audio delay plus the frame length of
             the mode).
             The next period of a parity is the earliest period of that parity whose
             window is open. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Modulator.cpp (delay_ms), "
                + "TxStartPolicy.hpp (TxStartLatestPeriodFraction)";
        }
        @DiffersFromSource {
            what = "WSJT-X starts a transmission up to 75 % of the period also when no "
                + "audio of the frame is left (FT4 between 5340 and 5625 ms); the "
                + "station closes the window when the frame's audio would have ended";
        }
        attribute ft8AudioDelayMs : Integer = 500;
        attribute ft4AudioDelayMs : Integer = 300 {
            doc /* Counted to the ramp symbol that leads the frame. */ }
        attribute latestStartPct : Integer = 75;
    }

    item def Arm {
        doc /* Switch the transmit state on. */
        attribute cause : ArmCause;
    }
    item def Disarm {
        doc /* Switch the transmit state off; a transmission that is keyed finishes. */
        attribute cause : DisarmCause;
    }
    item def Abort {
        doc /* End the transmission or the tone now and switch the transmit state off. */
        attribute cause : DisarmCause;
    }
    item def Halt {
        doc /* The emergency stop. */
    }
    item def HaltReceipt {
        doc /* The answer to Halt. */
        attribute haltState : HaltState;
    }
    item def SetTune {
        doc /* Switch the Tune tone on or off. */
        attribute enabled : Boolean;
        attribute txOffsetHz : Integer[0..1] {
            doc /* The audio frequency of the tone. Present to switch on. */ }
    }
    item def StepBegins {
        doc /* The contact begins a step: it has seen every stop before this moment. */
    }
    item def StationMode {
        doc /* The station's operating mode (WstxOperatingSelection::OperatingModeRule),
             given at station start and at every change. */
        attribute mode : Mode;
    }
    item def StationBand {
        doc /* The station's band (WstxOperatingSelection::StationBandRule), given at every
             change. */
        attribute band : String[0..1];
    }
    item def TransmitProfile {
        doc /* The configuration of transmit and what the configurations of radio
             control and audio mean for transmitting. The supervisor gives it at
             station start and whenever the station config changes. */
        attribute config : TransmitConfig;
        attribute configured : Boolean {
            doc /* True when the profile keys the radio over CAT and names an output
                 device. On a profile of a radio's native network connection it is
                 false. */ }
        attribute levelManaged : Boolean {
            doc /* True when the radio of the profile is one the station manages. */ }
        attribute powerPct : Integer[0..1] {
            doc /* The output power of the station's band
                 (WstxRadioControl::RadioConfig::powers); absent without one. */ }
    }
    item def LevelFound {
        doc /* Transmit has found an audio drive, with the Tune tone or by the supervision
             of a transmission, and gives it to be saved as the band's entry of
             TransmitConfig::levels. The supervisor answers with a
             TransmitProfile: with that level when the profile has saved it, with the
             level before when it could not. */
        attribute level : BandLevel;
    }
    item def ProcessEnds {
        doc /* The station process ends. */
    }
    item def CommandAnswer {
        doc /* The answer to Arm, Disarm, Abort and SetTune. */
        attribute accepted : Boolean;
        attribute refusal : TransmitRefusal[0..1] {
            doc /* Present when the command was not carried out. */ }
    }

    item def TransmitStatus {
        doc /* The state of transmit at the moment it is read. */
        attribute capability : Capability;
        attribute armState : ArmState;
        attribute lastDisarmCause : DisarmCause;
        attribute lastArmCause : ArmCause[0..1] {
            doc /* Absent until the state was first switched on. */ }
        attribute stoppedInStep : Boolean {
            doc /* True when the state was switched off since the last StepBegins. */ }
        attribute tune : Boolean { doc /* True while the tone is on. */ }
        attribute pendingSequence : Integer[0..1] {
            doc /* The request that waits: the one for a later period, else the one
                 whose audio has not started. Absent without one. */ }
        attribute lastText : String[0..1] {
            doc /* The message last put on the air, as a receiver shows it. */ }
        attribute lastTxOffsetHz : Integer[0..1] {
            doc /* The Tx offset of lastText. */ }
        attribute lastPeriodUtcMs : Integer[0..1] {
            doc /* The start, in station time, of the period of the transmission whose
                 audio started last. Absent before the first one. */ }
        attribute haltState : HaltState;
        attribute refusal : TransmitRefusal[0..1] {
            doc /* The latest refusal. Absent after a request, an Arm or a tone was
                 accepted. */ }
        attribute ptt : PttState;
        attribute transmitting : Boolean {
            doc /* True while the audio of a transmission runs or the tone is on. */ }
        attribute onAir : Boolean {
            doc /* True while ptt is not released, the audio of a transmission runs or
                 the tone is on. The supervisor gives it, with lastPeriodUtcMs,
                 to receive. */ }
        attribute tuneRemainingSeconds : Integer {
            doc /* What is left of the running tone before its limit, rounded up; 0
                 without one. */ }
        item outcomes : TransmitOutcome[0..*] ordered {
            doc /* The latest outcomes, the oldest first. */ }
        attribute startupRelease : StartupRelease;
    }

    enum def AlcKnown {
        doc /* Whether the radio reports its ALC.
             unknown: no meter has been read.
             available: the last reading held an ALC value.
             unavailable: the radio refused the ALC reading. */
        enum unknown;
        enum available;
        enum unavailable;
    }
    enum def LevelResult {
        doc /* How the last finding of the level with the Tune tone ended.
             stored: the ALC rose; the level one step below is stored.
             maxWithoutAlc: the highest level was reached without it; it is stored.
             noAlc: the radio refused the ALC reading.
             highSwr: the SWR reached the fault value.
             aborted: Halt, the tone's limit or another end of the tone.
             radioUnavailable: the meters could not be read.
             storageUnavailable: the level found did not come back as saved
             (LevelFound). */
        enum stored;
        enum maxWithoutAlc;
        enum noAlc;
        enum highSwr;
        enum aborted;
        enum radioUnavailable;
        enum storageUnavailable;
    }
    enum def LevelWarning {
        doc /* Trouble of the Tx signal that lasts (LevelMonitor in the transmit part).
             alcHigh: the ALC is high.
             poLow: the output power is far below the output power of the band.
             swrHigh: the SWR is high.
             swrFault: the SWR stopped the station. */
        enum alcHigh;
        enum poLow;
        enum swrHigh;
        enum swrFault;
    }
    item def TxLevelStatus {
        doc /* The audio drive and its supervision, at the moment it is read. */
        attribute managed : Boolean { doc /* TransmitProfile::levelManaged. */ }
        attribute mode : LevelMode { doc /* TransmitConfig::levelMode. */ }
        attribute levelDb : Integer {
            doc /* The audio drive that counts; while the level is found, the level of
                 the tone. */ }
        attribute stored : Boolean {
            doc /* True when the station's band has an entry in TransmitConfig::levels. */ }
        attribute alc : AlcKnown;
        attribute assistant : Boolean { doc /* True while the level is found. */ }
        attribute result : LevelResult[0..1] {
            doc /* Absent before the first finding, while the level is found and after a
                 level the operator has set. */
            @NotStated {
                what = "the result of a run whose meter reading fails in another way "
                    + "than by a missing radio: the code shows the name of the failure "
                    + "as radio control gives it, which is no LevelResult";
            }
        }
        attribute meters : WstxRadioProperties::MeterReadings[0..1] {
            doc /* The meters as last read; absent before the first reading. */ }
        attribute powerPct : Integer[0..1] { doc /* TransmitProfile::powerPct. */ }
        attribute warnings : LevelWarning[0..*];
    }

    port def TransmitControlPort {
        doc /* Written from the supervisor's side; transmit uses the conjugate.
             Halt is answered by HaltReceipt; a LevelFound of transmit by a
             TransmitProfile. StationMode, StationBand, TransmitProfile
             and ProcessEnds have no answer. */
        out item halt : Halt;
        out item stationMode : StationMode;
        out item stationBand : StationBand;
        out item profile : TransmitProfile;
        out item processEnds : ProcessEnds;
        in item receipt : HaltReceipt;
        in item outcome : TransmitOutcome;
        in item status : TransmitStatus;
        in item level : TxLevelStatus;
        in item levelFound : LevelFound;
    }
    interface def TransmitControl {
        doc /* The supervisor commands the transmit function; transmit reports its
             state. */
        end station : TransmitControlPort;
        end transmit : ~TransmitControlPort;
    }
}

package WstxRadioControl {
    private import ScalarValues::*;
    private import WstxRadioProperties::RadioCapabilities;
    private import WstxRadioProperties::RadioResultStatus;
    private import WstxRadioProperties::RadioState;
    private import WstxRadioProperties::RadioSettings;
    private import WstxRadioProperties::RadioMeters;
    port def RadioControl {
        out item request : ControlRequest;
        in item outcome : ControlOutcome;
        binding replyContext bind outcome.request = request;
    }
    item def ControlRequest { ref part resourceContext : WstxRadioControlPart::RadioBinding; }
    item def ControlOutcome { ref item request : ControlRequest; }
    item def ReadRadioCapabilities :> ControlRequest;
    item def RadioCapabilitiesOutcome :> ControlOutcome {
        attribute status : RadioResultStatus;
        attribute capabilities : RadioCapabilities[0..1];
        attribute explanation : String[0..1];
    }
    item def ReadRadioState :> ControlRequest;
    item def RadioStateOutcome :> ControlOutcome {
        attribute status : RadioResultStatus;
        attribute observedState : RadioState[0..1];
        attribute explanation : String[0..1];
    }
    item def ApplyRadioSettings :> ControlRequest {
        attribute requested : RadioSettings;
    }
    item def RadioSettingsOutcome :> ControlOutcome {
        attribute status : RadioResultStatus;
        attribute confirmedState : RadioState[0..1];
        attribute explanation : String[0..1];
    }
    item def ReadRadioMeters :> ControlRequest;
    item def RadioMetersOutcome :> ControlOutcome {
        attribute status : RadioResultStatus;
        attribute meters : RadioMeters[0..1];
        attribute explanation : String[0..1];
    }
    doc /* The operations the CAT driver makes the radio perform, carried by the control
         request and outcome items through the selected binding and the common authority:
         readCapabilities(ReadRadioCapabilities) -> RadioCapabilitiesOutcome;
         readState(ReadRadioState) -> RadioStateOutcome;
         applySettings(ApplyRadioSettings { requested : RadioSettings }) -> RadioSettingsOutcome;
         readMeters(ReadRadioMeters) -> RadioMetersOutcome.
         Each request inherits resourceContext : RadioBinding and every outcome inherits
         request : ControlRequest. Status distinguishes confirmed results from unavailable,
         unsupported, rejected and failed operations. Optional payload absence is never
         confirmation; a returned state contains only actual observations, never requested
         values copied into observations. A successful acknowledgement without observed
         state does not establish confirmedState. Concrete readback behaviour remains
         in the responsible radio contract. Existing CAT request refinements remain valid.
         These are semantic signatures, not new wire protocols or executable adapters. */
    enum def CatOperation { enum read_frequency; enum read_mode; enum read_data; enum read_rx_tx; enum read_split; enum set_frequency; enum set_mode; enum set_data; enum receive_setup; }
    attribute def RadioObservation {
        attribute frequencyHz : Integer[0..1];
        attribute mode : String[0..1];
        attribute 'filter' : Integer[0..1];
        attribute data : Boolean[0..1];
        attribute dataFilter : Integer[0..1];
        attribute split : Boolean[0..1];
        attribute rxTx : String[0..1];
        attribute observedAtMs : Integer;
        doc /* Only measured values, unknown is absent/null. Closed/stale observations
             are never current readiness. Unknown mode code is preserved explicitly. */
    }
    item def CatRequest :> WstxRadioControl::ControlRequest {
        attribute operation : CatOperation;
        attribute connectionGeneration : Integer;
        attribute frequencyHz : Integer[0..1];
        attribute mode : String[0..1];
        attribute 'filter' : Integer[0..1];
        attribute data : Boolean[0..1];
        attribute dataFilter : Integer[0..1];
        doc /* Compiled typed union exact per contract 12.8, not arbitrary optional combinations.
             Frequency30000..74800000; settersUSB/LSB/FIL1..3; DATAOFF00/00.
             No raw command, PTT/TX setter, VOX or tuner operation. */
    }
    item def CatResult :> WstxRadioControl::ControlOutcome {
        attribute connectionGeneration : Integer;
        attribute observation : RadioObservation;
        attribute error : String[0..1];
        doc /* ACK requires independent matching readback; mismatch/failure indeterminate.
             No retry, replay or invented rollback. Independent from receive generation. */
    }
    enum def ControlMode { enum disabled; enum cat; }
    enum def PttMode { enum disabled; enum cat; }
    attribute def ControlSelection {
        doc /* Exactly the keys mode, endpoint and ptt. The endpoint is null exactly when mode
             is disabled; with mode cat it is opaque nonempty UTF-8 of at most 256 bytes
             without control characters. PTT cat requires mode cat. The selection is intent:
             no driver and no evidence that the device is available. */
        attribute mode : ControlMode = ControlMode::disabled;
        attribute endpoint : String[0..1] = null;
        attribute ptt : PttMode = PttMode::disabled;
        assert constraint noCatPttWithoutCat {
            ptt == PttMode::cat implies mode == ControlMode::cat
        }
    }

    enum def AutomaticCatCondition { enum disabled; enum unauthorized; enum commissioningRequired; enum waitingForDevice; enum connecting; enum ready; enum retryWaiting; enum closing; enum quarantined; }
    attribute def AutomaticCatStatus {
        doc /* Target current condition, not behavioral states or another actor. One
             authority-owned observation per selected radio; boot/connection generation
             and query sequence still fence every fact. A retained frequency is not
             fresh in any condition except ready with its matching observation proof.
             Existing strict version1 status objects remain unchanged; expose this
             additive target status via POST /authorization/v1/status with
             AuthStatusRequest; same-origin browser POST supplies actual Origin, not a
             script-forged header. Preserve exact Origin/TLS before auth, active scoped
             grant (401 otherwise), no CORS and Cache-Control:no-store. Missing/wrong
             Origin on accepted POST403; legacy GET/profile absence policy is unchanged.
             Read-only snapshot: no identity/grant/session/receipt/native effects or
             CAT retry scheduling. GET on this new path405/no effects; no fallback.
             Strict response version1,scope (AuthWireScope projection),condition,
             error,retry_after_ms,commissioned,receive_state. Error is bounded mapped
             code/null, retry_after_ms safe integer0..8000/null, commissioned Boolean;
             receive_state is existing authoritative audio/decoder summary, no copied
             numerical/result state. Logical response<=1024bytes, reuse existing status
             publication/heartbeat and accounting; no parallel timer/poll stream. */
        attribute scope : WstxStationLink::SelectedRadioAuthorizationScope;
        attribute condition : AutomaticCatCondition;
        attribute retryAfterMilliseconds : Integer[0..1];
        attribute errorCode : String[0..1];
    }
}

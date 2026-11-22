package WstxAutoControl {
    private import ScalarValues::*;
    private import WstxModeProcessing::Mode;
    private import WstxModeProcessing::PeriodParity;
    private import WstxModelNotes::CodeDiffers;

    doc /* What the supervisor commands the auto function and tells it of the station,
         and what auto reports: its state and the open Tx slots. */

    enum def SwitchKind {
        doc /* switchOn: the Auto on of the operator or of an agent.
             switchOff: their Auto off.
             halt: Halt, from any source. */
        enum switchOn;
        enum switchOff {
            @CodeDiffers {
                what = "The code switches Auto off by auto false (auto_request in "
                    + "server/src/operating/strategy.rs).";
            }
        }
        enum halt;
    }
    item def SwitchAuto {
        doc /* Switch Auto on or off. A switchOn that is not carried out is answered by
             AutoRefused; every other is answered by AutoActivity. */
        attribute kind : SwitchKind;
    }
    enum def AutoRefusal {
        doc /* Why a switchOn is not carried out.
             noStrategy: Default is active.
             notConfirmed: the contest in force forbids automatic operation and the
             operator has not acknowledged Auto there (AutoConfig::forbiddenContests). */
        enum noStrategy {
            @CodeDiffers {
                what = "The code refuses with not_configured and the field strategy (auto_request "
                    + "in server/src/operating/strategy.rs).";
            }
        }
        enum notConfirmed;
    }
    item def AutoRefused {
        doc /* The answer to a switchOn that is not carried out. It changes nothing. */
        attribute refusal : AutoRefusal;
    }
    attribute def AutoConfig {
        doc /* Auto's configuration: a setting of the shack, shared by its stations
             (WstxProfileAccess::ShackSettings::auto). */
        attribute forbiddenContests : Boolean = false {
            doc /* The operator, as the licensed person, has acknowledged once that Auto
                 may run under a contest whose rules forbid automatic operation
                 (WstxStrategies::AutomationClause::forbidden). Nobody is asked again
                 while it holds; nothing else confirms it. */
            @CodeDiffers {
                what = "The code keeps no acknowledgement: each switch on under a forbidding "
                    + "contest needs automation_confirmed (auto_request in "
                    + "server/src/operating/strategy.rs).";
            }
        }
    }
    item def AutoContext {
        doc /* What auto needs to know of the station. The supervisor gives it at
             station start and whenever one of its values changes. */
        attribute config : AutoConfig {
            doc /* Auto's configuration, from the shack's settings. */ }
        attribute present : Boolean {
            doc /* An operator or an agent is connected, by the station link's measure. */ }
        attribute receiving : Boolean {
            doc /* Receive runs live in FT8 or FT4, the station's operating mode. */ }
        attribute autoSeq : Boolean { doc /* The contact's Auto Seq is on. */ }
        attribute standardCall : Boolean { doc /* The profile's call is a standard call. */ }
        attribute specialActivity : Boolean {
            doc /* The operator has set a special activity for the contact, for example
                 Hound. */
            @CodeDiffers {
                what = "The code reads the contact's activity (StatusFacts::activity in "
                    + "server/src/operating/qso/contact_http.rs).";
            }
        }
        attribute band : String[0..1] {
            doc /* The station's band (WstxOperatingSelection::StationBandRule). */ }
        attribute mode : Mode { doc /* The station's operating mode. */ }
        attribute repetitionLimit : Integer {
            doc /* The contact's repetition limit: how often one message is sent. */
            @CodeDiffers {
                what = "The code reads tx_calls of the transmit view "
                    + "(server/src/operating/auto/automation.rs).";
            }
        }
        attribute contactParity : PeriodParity[0..1] {
            doc /* The parity the partner transmits in, while a contact or a CQ is in
                 progress, made by hand or by Auto; for a CQ the parity the station
                 does not transmit in. Absent while none is in progress. */
            @CodeDiffers {
                what = "The code reads the contact's Tx parity (StatusFacts::parity in "
                    + "server/src/operating/qso/contact_http.rs).";
            }
        }
        attribute operatorContact : Boolean {
            doc /* A contact or a CQ that Auto did not start is in progress. */
            @CodeDiffers {
                what = "The code sees an operator's contact on the engine and puts the run in its "
                    + "state manual (RunState::Manual in server/src/operating/auto/automation.rs).";
            }
        }
    }

    enum def AutoState {
        doc /* What Auto is doing.
             waiting: Auto is on and has no contact or CQ of its own.
             contactActive: Auto's contact is in progress.
             callingCq: Auto's CQ is in progress.
             stopped: Auto is off. */
        enum waiting;
        enum contactActive;
        enum callingCq;
        enum stopped;
    }
    enum def WaitReason {
        doc /* Why Auto, waiting, starts nothing (WstxTargetChoice::WaitRule). */
        enum noReceive;
        enum autoSeq;
        enum call;
        enum activity;
        enum band;
        enum outsidePeriod;
        enum contact;
        enum clock;
        enum tune;
    }
    enum def OffReason {
        doc /* Why Auto went off (WstxAutoMode::AutoStops). */
        enum halted;
        enum stopped;
        enum noClient;
        enum transmitRefused;
        enum transmitStopped;
    }
    enum def LeaveReason {
        doc /* Why Auto left a station (WstxLeave::LeaveRule). */
        enum repetitions;
        enum gone;
        enum txChanges;
    }
    attribute def Leaving {
        doc /* The station Auto left last, and why. */
        attribute call : String;
        attribute reason : LeaveReason;
    }
    attribute def RetryPause {
        doc /* A station in its retry pause (WstxLeave::LeaveRule). */
        attribute call : String;
        attribute band : String[0..1];
        attribute mode : Mode;
        attribute remainingSeconds : Integer;
    }
    attribute def LeaveCount {
        doc /* How far Auto's contact is from being left (WstxLeave::LeaveRule). */
        attribute remaining : Integer[0..1] {
            doc /* With calls: the calls left, at least 1. With untilLogged: the minutes
                 left while the station is not decoded. With contest: the Tx changes
                 left. Absent while the station is decoded under untilLogged, and while
                 it stays under contest. */ }
        attribute staying : Boolean {
            doc /* Under contest: the station stays while it hears the station and is
                 the most valuable one. */ }
    }
    item def AutoActivity {
        doc /* Auto's state, given whenever a value changes. */
        attribute 'state' : AutoState;
        attribute waitReason : WaitReason[0..1] {
            doc /* Present while Auto waits for a reason. */
            @CodeDiffers {
                what = "The code names it reason, a key that also holds why a run stopped "
                    + "(the run of server/src/operating/auto/automation.rs).";
            }
        }
        attribute offReason : OffReason[0..1] {
            doc /* Present while Auto is off after it was on. */
            @CodeDiffers {
                what = "The code names it reason, a key that also holds why a run waits "
                    + "(the run of server/src/operating/auto/automation.rs).";
            }
        }
        attribute left : Leaving[0..1] {
            doc /* Absent until Auto leaves a station after it was switched on. */ }
        attribute quiet : RetryPause[0..*] { doc /* The stations in their retry pause. */ }
        attribute leave : LeaveCount[0..1] { doc /* Present with contactActive. */ }
        attribute cqPauseLeft : Integer[0..1] {
            doc /* The periods left of the CQ pause (WstxCqWhenIdle::CqPause). Absent
                 while there is none. */
            @CodeDiffers {
                what = "The code gives no periods left; it counts empty_publications against "
                    + "cq_wait_periods (server/src/operating/auto/automation.rs).";
            }
        }
    }
    port def AutoControlPort {
        doc /* Written from the supervisor's side; auto uses the conjugate.
             AutoContext has no answer. AutoActivity is also given without a command,
             whenever it changes. */
        out item switchAuto : SwitchAuto;
        out item context : AutoContext;
        in item activity : AutoActivity;
        in item refused : AutoRefused;
    }
    interface def AutoControl {
        doc /* The supervisor switches Auto and tells it of the station; auto reports
             its state. */
        end station : AutoControlPort;
        end auto : ~AutoControlPort;
    }
}

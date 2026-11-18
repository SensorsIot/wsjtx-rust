package WstxStationAuthority {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-021';
    private import WstxSupervisorPart::Supervisor;
    private import WstxStationCommands::StationRequest;
    private import WstxStationCommands::StationRefused;
    private import WstxStationCommands::Requester;
    private import WstxStationCommands::AgentRefusal;
    private import WstxAutoControl::SwitchAuto;
    private import WstxTransmitControl::Halt;
    private import WstxTransmitControl::TransmitStatus;
    private import WstxTransmitControl::LevelWarning;
    private import WstxReceiveControl::StartLive;
    private import WstxProfileAccess::SaveProfile;
    private import WstxProfileAccess::SaveMemory;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    doc /* The supervisor as the one gate of the station: which commands it passes on
         and which it refuses, and how every function learns what it needs. */

    requirement 'CL-006-07' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST pass each command of the operator or an agent to
             the function it is for, answer a command sent again as ReceiptRule says, and
             refuse a command beforehand as GateRule says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-006-07'; }

    attribute def GateRule {
        doc /* A StationRequest that is a command of a function's control interface goes
             to that function over its port, and the function's answer is the outcome; one
             of the supervisor's own commands is carried out by the supervisor.
             The operator and an agent give the same commands with the same rights, but
             an agent gives none of the commands AgentRefusal names: its port to the
             supervisor has none of them (WstxStationCommands::AgentOperations). Apart
             from these only SwrBarrier tells them apart.
             Before a command goes on, a command that names another profile is refused
             with wrongProfile, and one that names another start of the station process
             with stateConflict (StationRefused). A Halt is passed on for the station's
             profile whatever start it names. A StartLive, and a selection, made from
             another profile revision than the saved one is refused with stateConflict.
             A StartLive on a profile without an input device is refused with
             audioUnconfigured, and on a profile of a radio's native connection whose
             session is not ready with radioUnavailable. A function checks nothing of
             this again.
             A Halt goes to transmit and, as SwitchAuto of the kind halt, to auto.
             A DetectRadios goes to radio control, and its answer is RadioDetection: the
             DetectionReport, with, for a proposed radio, the endpoints audio lists for
             that radio (WstxAudioControl::EndpointEntry::radio) in each direction. */
        attribute agentRefusal : AgentRefusal[0..*] {
            doc /* The commands an agent does not give. */ }
    }

    attribute def ReceiptRule {
        doc /* Before GateRule's checks, a command whose commandId is that of one of the
             latest answered commands, with the same content, is given that answer again
             and has no effect; with other content it is refused with stateConflict. How
             many answers are kept is a value of the code; the requester sends a command
             again only to learn its answer. */
    }

    requirement 'CL-119-09' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST refuse the operator's and the agents' commands for
             the contact while Auto is on, as AutoOnRule says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-119-09'; }

    attribute def AutoOnRule {
        doc /* While Auto is on (WstxAutoControl::AutoActivity), these commands of qso
             (WstxQsoControl) of the operator or an agent are refused with autoOn and
             change nothing: Reply, CallCq, CallDx, SendNext, ResetRepetitions, SelectRow,
             EnterDx, ChooseNext, CancelContact, EditMessage, SetReport, SetTx4,
             SetTx1Skip, SetParity, SetFrequency, and Tune on.
             Halt, Abort, SwitchAuto off, Tune off, SetHoldTx, a save of the
             settings, a selection of band or mode and a selection of the strategy or
             contest pass. Auto's own commands reach qso over the operating chain and
             are not commands of the gate. */
    }

    requirement 'CL-044-17' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST keep an agent from starting a transmission after an
             SWR fault until the operator has acted, as SwrBarrier says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-044-17'; }

    attribute def SwrBarrier {
        doc /* The barrier holds from transmit's SWR fault (TransmitStatus with the cause
             halt and LevelWarning::swrFault) until the next command of the operator
             (Requester::operator). While it holds, an agent's start of a contact
             (WstxQsoControl::Reply, CallCq, CallDx, SendNext and ResetRepetitions), its
             Tune on and its SwitchAuto on are refused with swrFault.
             The operator's commands and every Halt pass. It is the one barrier of its
             kind; it ends with the station process. */
    }

    requirement 'CL-005-08' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST give every function what it needs to know of the
             profile and of the other functions, and bring every change of a setting to
             the profile, as ContextRule says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-005-08'; }

    attribute def ContextRule {
        doc /* The supervisor gives each function the configuration, records and
             context items its control interface names, at the moments and with the
             values each item says: from the profile's snapshots, from its own state
             (WstxOperatingSelection::OperatingModeRule, StationBandRule, SelectionState)
             and from what the other functions report to it. A feature that is another
             part's fact is that fact as the supervisor last had it.
             A change of a setting by the operator or an agent goes to the profile
             (SaveProfile, SaveShack, CreateEntry, UpdateEntry, DeleteEntry,
             UpdateMostWanted, UpdateCountryFile) and reaches the functions only from the
             snapshot the profile answers with; a refusal of the profile is the outcome.
             A record a function hands back, and a level transmit finds, go to the profile
             (SaveMemory, SaveProfile), and the function is given the records as the
             profile then holds them. */
    }

    verification 'TC-006-004' {
        doc /* Commands for another profile, start or old revision, and the halt. */
        subject supervisor : Supervisor;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-006-07'; }
        @TestedBy {
            test = "server/src/recording_tests.rs::"
                + "selection_start_checks_independent_loaded_profile_revision_after_unlock; "
                + "server/src/transmit/transmit_http_tests.rs::"
                + "transmit_wire_is_exact_halt_is_always_admitted_and_plaintext_never_arms";
        }
    }
}

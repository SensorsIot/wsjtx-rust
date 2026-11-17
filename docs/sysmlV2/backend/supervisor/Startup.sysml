package WstxStartup {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-021';
    private import WstxSupervisorPart::Supervisor;
    private import WstxStationCommands::StartupRecords;
    private import WstxStationCommands::StartupState;
    private import WstxStationCommands::ResumeState;
    private import WstxProfileAccess::OpenRequest;
    private import WstxProfileAccess::CreateRequest;
    private import WstxProfileAccess::OpenRefusal;
    private import WstxProfileAccess::SaveMemory;
    private import WstxRadioControl::DiscoverRadio;
    private import WstxReceiveControl::StartLive;
    private import WstxReceiveControl::StopLive;
    private import WstxTransmitControl::ProcessEnds;
    private import WstxTransmitControl::TransmitStatus;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;

    doc /* How the station process starts and ends, and how receive is taken up again at
         the start. */

    requirement 'CL-005-09' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST start and end the station process as LaunchRule
             says, and end a start it cannot carry out with its StartupOutcome. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-005-09'; }

    attribute def LaunchRule {
        doc /* The arguments of the process are exactly one of: --profile and a folder,
             with at most one --shack and a folder; --create-profile and a folder;
             --create-native-flex-profile with a folder, a receive antenna and at most an
             address. Other arguments, also none, end the start with
             invalid_runtime_configuration: every station starts with its profile.
             A creation asks the profile to make the profile (CreateRequest) and ends
             with created, or with the profile's refusal (OpenRefusal).
             A start asks the profile to open the profile (OpenRequest); a refusal ends
             the start with its reason. The line WSTX profile, the profile's id and its
             display name is written to the output of the process. Then web is given its
             context and Listen (WstxWebControl); its ListenRefused ends the start with
             its reason.
             Then the functions start, transmit disarmed. On a profile of a radio's
             native connection the adapter of that connection starts with the profile's
             NativeIntent; an intent the adapter does not take ends the start with
             resource_unavailable, and an environment variable of the adapter
             (WstxFlexSession) that cannot be read with invalid_runtime_configuration. A
             profile of the sound device connection starts no such adapter.
             Radio control makes sure which radio is the profile's (DiscoverRadio) before
             the radio connection is first opened and before transmit takes its level,
             unless WSTX_RADIO_DISCOVERY is off. A RadioDiscovered is saved as the
             profile's control (SaveProfile), with the input and the output device audio
             lists for that radio when there is exactly one of each and none otherwise,
             and without Tx levels (WstxTransmitControl::TransmitConfig::levels); the line
             radio discovery:, the port, the model in brackets and is this station's radio
             is written to the output of the process.
             Every function is given its configuration and its records
             (WstxStationAuthority::ContextRule), the resume of receive begins
             (ResumeRule), and the station serves: the outcome ready.
             An outcome other than ready and created is written to the output of the
             process, beginning with its name and a colon, followed by the words
             selected profile and the folder as it was named when a folder was named;
             the process then ends with an exit code other than 0, before the station
             serves. created ends it with the exit code 0.
             However the process ends, the supervisor gives transmit, then udp, then
             web ProcessEnds. */
    }
    enum def StartupOutcome {
        doc /* How a start or a creation ends.
             ready: the station runs with the profile.
             created: the profile is made.
             invalid_runtime_configuration: the arguments or the environment of the
             process are not ones the station takes; also the profile's and web's.
             resource_unavailable, invalid_profile, unsupported_schema,
             unsupported_connection_type, profile_in_use: the profile's refusal
             (OpenRefusal); resource_unavailable also web's.
             endpoint_in_use: another process listens where the profile says. */
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

    requirement 'CL-045-01' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST remember the last receive it started until the
             operator or an agent stops receive, as ResumeRecord says. */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-045-01'; }

    attribute def ResumeRecord {
        doc /* Every live job started by a StartLive of the operator or an agent, or by a
             selection, becomes StartupRecords::lastReceive: its mode, the band of the
             selection at that moment and the input device it was started on. A StopLive
             of the operator or an agent clears it; a live job that ends by an error
             keeps it. The supervisor keeps it in the hidden store (SaveMemory). */
        attribute records : StartupRecords;
    }

    requirement 'CL-045-02' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST take up the remembered receive once at every
             station start, as ResumeRule says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-045-02'; }

    attribute def ResumeRule {
        doc /* The resume begins once radio control has begun to keep the radio connection,
             and needs no command.
             Without a remembered receive it is idle and nothing starts. Without an input
             device in the profile it fails with audio_unconfigured.
             Otherwise it waits: a remembered receive in FT4 or FT8 with a band is taken
             up by a selection of that band and mode (WstxOperatingSelection::
             SelectionRule). A selection refused with radio_unavailable, busy or
             state_conflict is made again until the radio is ready or a bounded wait
             ends; a selection that succeeds makes the resume started. When none
             succeeds, receive starts in the remembered mode on the radio's present dial
             (StartLive): started_untuned, and the remembered band is kept.
             A remembered receive in spectrum or without a band starts receive in its
             mode: started. On a profile of a radio's native connection it first waits,
             a bounded time, for the native session.
             A receive that cannot start fails the resume with receive's error.
             A live job, a selection or an import that a command started before the
             resume acts stays, and the resume is skipped.
             The resume never ends the process. Its state is given as StartupState. */
        attribute 'state' : ResumeState;
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Monitor is on at the start, on "
                + "the band and mode of the last session";
        }
        @DiffersFromSource {
            what = "WSJT-X has the setting Monitor off at startup; the station always "
                + "takes up the last receive.";
        }
    }

    requirement 'CL-045-03' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST leave the transmitter at rest while it resumes
             receive, as ResumeAtRest says. */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-021'; end #derive ::> 'CL-045-03'; }

    attribute def ResumeAtRest {
        doc /* The resume gives commands to receive and, through the selection, to radio
             control only. The transmitter stays disarmed and unkeyed throughout
             (TransmitStatus), and the only writes to the radio are those of the
             selection, which radio control refuses while the radio transmits. */
    }

    verification 'TC-045-001' {
        doc /* The resume at station start. */
        subject supervisor : Supervisor;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-045-02'; verify 'CL-045-03'; }
        @TestedBy {
            test = "server/src/receive/receive_startup_tests.rs::"
                + "startup_resume_starts_stored_band_and_mode; "
                + "server/src/receive/receive_startup_tests.rs::"
                + "startup_resume_retries_transient_selection_refusals; "
                + "server/src/receive/receive_startup_tests.rs::"
                + "startup_resume_cat_unavailable_falls_back_to_plain_receive; "
                + "server/src/receive/receive_startup_tests.rs::"
                + "startup_resume_never_arms_or_keys; "
                + "tests/flexAdapter/native-flex.test.cjs::"
                + "CL-045-02 a native station resumes its receive at startup, waiting a "
                + "bounded time for its session";
        }
    }
}

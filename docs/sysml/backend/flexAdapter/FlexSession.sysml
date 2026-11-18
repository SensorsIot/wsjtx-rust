package WstxFlexSession {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-023';
    private import WstxFlexAdapterPart::FlexAdapter;
    private import WstxFlexApi::*;
    private import WstxAudioStreams::NativeFormat;
    private import WstxAudioStreams::NativePacket;
    private import WstxSoundDevice::Encoding;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-013-01' {
        subject adapter : FlexAdapter;
        doc /* The Flex adapter MUST hold one session with the radio over the radio's own
             network API and report the state of that session (SessionLifecycle). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-023'; end #derive ::> 'CL-013-01'; }

    enum def SessionState {
        doc /* The state of the session.
             discovering: an attempt has begun and the adapter looks for a radio
             (RadioChoice); with a saved address this state is passed at once. The
             state at station start.
             connecting: a radio is chosen and the session is being set up
             (SessionSetup).
             ready: the slice and the stream are the adapter's; packets are given to
             audio and the slice can be tuned.
             unavailable: the last attempt or session failed with a SessionError that is
             no conflict.
             conflict: it failed with clientIdentityInUse, ownershipAmbiguous,
             sliceOwnership or daxChannelConflict.
             stopped: the station has ended. */
        enum discovering;
        enum connecting;
        enum ready;
        enum unavailable;
        enum conflict;
        enum stopped;
    }
    enum def SessionError {
        doc /* Why an attempt or a session failed.
             discoveryUnavailable: the adapter cannot listen for announcements.
             radioNotFound: no radio announced itself.
             capacityClients: every radio that announced itself takes no further client.
             incompatibleApi: the radio speaks another version than
             ProtocolVersion::admitted.
             clientIdentityInUse: another client of the radio carries the profile's
             client identity.
             ownershipAmbiguous: the radio attributes a slice to the adapter before the
             adapter has created one.
             capacitySlices: the radio has no slice to give.
             sliceOwnership: the radio reports the created slice as another client's.
             antennaUnavailable: the created slice has another antenna than the profile
             names.
             capacityDax: every DAX channel is in use.
             daxChannelConflict: a slice with a lower number uses the adapter's DAX
             channel.
             radioRefused: the radio refused a command; SessionStatus::radioCode holds
             the code of its Reply.
             transportLost: the control connection did not open, or it ended.
             protocolError: the radio sent what the adapter cannot follow.
             timeout: a Greeting, a Reply or an awaited StatusLine did not come within
             SessionLifecycle::stepSeconds.
             resourceLost: the radio does not report the slice or the stream as the
             adapter's any more. */
        enum discoveryUnavailable;
        enum radioNotFound;
        enum capacityClients;
        enum incompatibleApi;
        enum clientIdentityInUse;
        enum ownershipAmbiguous;
        enum capacitySlices;
        enum sliceOwnership;
        enum antennaUnavailable;
        enum capacityDax;
        enum daxChannelConflict;
        enum radioRefused;
        enum transportLost;
        enum protocolError;
        enum timeout;
        enum resourceLost;
    }

    attribute def SessionLifecycle {
        doc /* How the session is opened, lost and ended.
             A session is the control connection to one radio together with the client,
             the slice and the receive stream the adapter has on that radio.
             The state is one of SessionState and is reported at once (SessionStatus).
             From station start on the adapter chooses a radio (RadioChoice) and sets
             the session up (SessionSetup).
             A ready session ends with resourceLost, with daxChannelConflict or with
             transportLost when what that SessionError names happens.
             After a failure the state is unavailable or conflict, and the next attempt
             follows after a wait (SessionStatus::retryAfterMs).
             The adapter ends a session by closing the control connection and relies on
             the radio to release the client's slice and stream then.
             The end of the station ends the session: stopped. */
        attribute stepSeconds : Integer = 5 {
            doc /* The radio has this long to take the control connection, to answer a
                 command and to report what the adapter waits for. */ }
        attribute firstRetryMs : Integer = 1000 {
            doc /* The wait before the first new attempt, and before the first one after
                 a session that was ready. */ }
        attribute maxRetryMs : Integer = 4000 {
            doc /* Each further attempt waits twice as long as the one before, up to
                 this. */ }
    }

    attribute def RadioFacts {
        doc /* What the chosen radio says about itself: from its Announcement, or on a
             saved address from its answer to Command::info. The adapter shows these
             facts and compares them with nothing. */
        attribute serial : String;
        attribute model : String[0..1];
        attribute firmware : String[0..1];
        attribute protocol : String[0..1] {
            doc /* Greeting::version; absent until the radio has stated it. */ }
        attribute address : String;
    }
    attribute def SliceFacts {
        doc /* The adapter's slice as the radio last reported it. A field the radio has
             not reported is absent. */
        attribute index : Integer { doc /* The number the radio gave the slice. */ }
        attribute letter : String[0..1];
        attribute frequencyHz : Integer[0..1];
        attribute mode : String[0..1];
        attribute rxAntenna : String[0..1];
        attribute daxChannel : Integer[0..1];
        attribute streamId : Integer[0..1] {
            doc /* The identity of the adapter's stream. */ }
        attribute observedAt : Integer[0..1] {
            doc /* When the radio last reported the slice, on the PC's monotonic
                 clock. */ }
    }
    attribute def StreamDiagnosis {
        doc /* What the adapter has counted and measured on the stream of the current
             session, for the diagnosis of the path to the radio. It is read on request
             and is no part of SessionStatus. Every field starts over when a session
             becomes ready. */
        attribute accepted : Integer { doc /* StreamPackets given on to audio. */ }
        attribute foreign : Integer {
            doc /* Datagrams from another address than the radio's or under another
                 stream identity than the adapter's. */ }
        attribute invalid : Integer {
            doc /* Datagrams and lines of the radio that cannot be read, and
                 StreamPackets of another format or with a sample that is not finite. */ }
        attribute lost : Integer { doc /* Turns given up (StreamIntake). */ }
        attribute late : Integer { doc /* StreamPackets discarded (StreamIntake). */ }
        attribute lastPeak : Real[0..1] {
            doc /* The largest magnitude of channel 0 in the StreamPacket last given
                 on. */ }
        attribute timestampKind : Integer[0..1] {
            doc /* The kind of time stamp the radio put on its last StreamPacket, by the
                 source's number. */ }
        attribute hostMinusRadioMs : Integer[0..1] {
            doc /* The PC clock minus that time stamp. Measured only: see
                 StreamIntake. */ }
        attribute jitterMeanMs : Real[0..1] {
            doc /* How far the spacing of the StreamPackets is from their length,
                 smoothed. */ }
        attribute jitterMaxMs : Real[0..1] { doc /* The largest such distance. */ }
    }
    attribute def SessionStatus {
        doc /* The state of the session at the moment it is read. A change of any field
             is reported at once. */
        attribute 'state' : SessionState;
        attribute error : SessionError[0..1] {
            doc /* Present in the states unavailable and conflict. */ }
        attribute radioCode : Integer[0..1] {
            doc /* The code of the last Reply that refused a command in the current
                 attempt or session. */ }
        attribute session : Integer {
            doc /* The number of sessions that became ready. A higher number means that
                 every handle, slice number and stream identity read before is void. */ }
        attribute radio : RadioFacts[0..1] {
            doc /* Absent until a radio has been chosen. */ }
        attribute slice : SliceFacts[0..1] {
            doc /* Present in the state ready. */ }
        attribute retryAfterMs : Integer[0..1] {
            doc /* The wait before the next attempt; present in the states unavailable
                 and conflict. */ }
    }

    requirement 'CL-013-02' {
        subject adapter : FlexAdapter;
        doc /* The Flex adapter MUST take up a radio only when the radio speaks the
             version of the API the station speaks, whatever its model and firmware
             (ApiAdmission). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-023'; end #derive ::> 'CL-013-02'; }

    attribute def ApiAdmission {
        doc /* The check of the radio's version.
             Greeting::version is compared with ProtocolVersion::admitted before the
             first command.
             Another version ends the attempt with incompatibleApi; no command is sent,
             and RadioFacts::protocol shows the version the radio stated.
             A radio of any model and firmware that speaks the admitted version is taken
             up. */
    }

    requirement 'CL-013-03' {
        subject adapter : FlexAdapter;
        doc /* The Flex adapter MUST build every session from the profile's intent alone,
             and take up a radio, a client identity and a slice only when the radio shows
             them free or the adapter's own (RadioChoice, SessionSetup). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/flexAdapter/session.rs; server/src/flexAdapter/wire.rs; "
                + "server/src/main.rs";
        }
    }
    #derivation connection { end #original ::> 'FR-023'; end #derive ::> 'CL-013-03'; }

    attribute def NativeIntent {
        doc /* What the profile says about its FlexRadio. A session is built from it and
             from the frequency last confirmed (TuneSlice), and from nothing else. An
             intent outside the forms below starts no session. */
        attribute clientId : String {
            doc /* The identity under which the station is a client of the radio: 36
                 characters, each a hexadecimal digit or a hyphen. */ }
        attribute rxAntenna : String {
            doc /* The receive antenna of the slice, by the radio's name for it: 1 to 16
                 capital letters, digits and underscores. */ }
        attribute radioAddress : String[0..1] {
            doc /* The address and port of the one radio to connect to (a saved
                 address). Absent: the adapter finds a radio by its Announcement. */ }
    }

    attribute def RadioChoice {
        doc /* Which radio a session is opened with, and how its stream finds the PC.
             With NativeIntent::radioAddress the adapter connects to that radio alone and
             listens for no Announcement. RadioFacts then come from the radio's answer to
             Command::info, asked after ApiAdmission.
             Without it the adapter listens for Announcements, on every address of the PC
             unless the environment variable WSTX_FLEX_DISCOVERY names another address
             and port, and several stations of one PC listen at the same time.
             It takes the first radio whose Announcement::availableClients is not 0, at
             the address and port the Announcement names.
             An attempt listens for listenSeconds. One in which only radios without a
             free client were heard ends with capacityClients, one in which none was
             heard with radioNotFound, and one in which the adapter could not listen
             with discoveryUnavailable.
             The adapter tells the radio the UDP port of its stream
             (Command::clientUdpport) and no address: the radio sends to the address the
             control connection comes from.
             On a saved address the adapter sends a Registration from that port right
             after, and again every keepAliveSeconds; the environment variable
             WSTX_FLEX_REGISTER_PORT names one port of the radio in place of the
             source's two. */
        attribute listenSeconds : Integer = 3;
        attribute keepAliveSeconds : Integer = 5;
    }

    action def SessionSetup {
        doc /* How a session is set up with the chosen radio. The steps follow in this
             order; a failure ends the attempt with the SessionError named, a Reply that
             refuses a command with radioRefused where no other is named, and a wait
             beyond SessionLifecycle::stepSeconds with timeout.
             1. The control connection is opened (transportLost) and the Greeting read.
             2. ApiAdmission.
             3. Command::subClientAll, then Command::clientStartPersistenceOff, whose
             Reply shows that the list of clients has arrived. A client that carries
             NativeIntent::clientId, compared without regard to capitals, ends the
             attempt with clientIdentityInUse before Command::clientGui is sent.
             4. Command::clientGui with the client identity, Command::subSliceAll and
             Command::subDaxAll. A slice in use that the radio attributes to
             Greeting::handle at this point ends the attempt with ownershipAmbiguous;
             the slice is left as it is.
             5. Command::clientUdpport (RadioChoice).
             6. Command::sliceCreate with NativeIntent::rxAntenna and the mode DIGU,
             without a frequency. A Reply with the code 50000001, 50000003 or 5000001D
             is capacitySlices. The slice is created when a StatusLine shows it in use
             under a handle; another handle than Greeting::handle is sliceOwnership.
             A slice with another antenna is removed (Command::sliceRemove):
             antennaUnavailable.
             7. The DAX channel is the lowest of the source's eight that no slice the
             radio reports uses; with none free the slice is removed: capacityDax.
             Command::sliceSet gives the slice that channel unless it has it, and a
             StatusLine must show it.
             8. Command::streamCreate for that channel; when it is refused the slice is
             removed: radioRefused. The stream is the adapter's when a StatusLine shows a
             DAX receive stream of that channel under Greeting::handle; a Reply that
             names another stream is protocolError.
             9. With a frequency confirmed before, the slice is brought to it as
             TuneSlice does, and a failure ends the attempt.
             10. The state is ready, and SessionStatus::session is one higher. */
        in intent : NativeIntent;
        out status : SessionStatus;
    }

    requirement 'CL-013-04' {
        subject adapter : FlexAdapter;
        doc /* The Flex adapter MUST change only the slice it created and take samples
             only from the stream it created, each as long as the radio reports it under
             the adapter's handle of the current session (OwnResources). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-023'; end #derive ::> 'CL-013-04'; }

    attribute def OwnResources {
        doc /* What counts as the adapter's on a radio that several clients share.
             The adapter's handle is Greeting::handle of the current session. A handle,
             a slice number and a stream identity of an earlier session count for
             nothing.
             Every Command::sliceSet, Command::sliceTune and Command::sliceRemove names
             the adapter's own slice.
             A StreamPacket is taken when it comes from the address of the session's
             radio and carries the identity of the adapter's stream. Every other
             datagram is counted (StreamDiagnosis::foreign) and discarded.
             What the radio cannot give is reported as capacityClients, capacitySlices
             or capacityDax, and what another client holds stays as it is.
             Of two sessions that chose one DAX channel at the same time, the one with
             the higher slice number ends with daxChannelConflict and chooses again. */
    }

    requirement 'CL-013-05' {
        subject adapter : FlexAdapter;
        doc /* The Flex adapter MUST send the radio the commands of its receive session
             and no other, so that nothing it sends keys the radio or reaches another
             client (ReceiveOnly). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-023'; end #derive ::> 'CL-013-05'; }

    attribute def ReceiveOnly {
        doc /* What the adapter sends on the control connection.
             Every CommandLine carries one of commands, which are all of Command.
             With them the adapter asks for a receiver and a receive stream, tunes that
             receiver and gives it up. */
        attribute commands : Command[1..*];
    }

    requirement 'CL-013-06' {
        subject adapter : FlexAdapter;
        doc /* The Flex adapter MUST give audio the radio's receive stream as packets of
             the form audio takes from any radio connection, with every loss it knows of
             filled or flagged (StreamIntake). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-023'; end #derive ::> 'CL-013-06'; }

    attribute def StreamIntake {
        doc /* How the StreamPackets of the adapter's stream (OwnResources) become the
             NativePackets of audio.
             The NativeFormat is outputRateHz, two channels and Encoding::float32: each
             frame of a StreamPacket stands twice, one after the other.
             A StreamPacket of another format, or with a sample that is not finite, is
             discarded and counted (StreamDiagnosis::invalid).
             StreamPackets are given on in the order of StreamPacket::count. One that is
             ahead of its turn waits. A turn whose packet is missing is given up when
             reorderPackets packets wait behind it.
             A turn given up is filled with zeros of one StreamPacket's length, so that
             the frame count keeps step with time, and is counted
             (StreamDiagnosis::lost). Audio takes these zeros as samples.
             The packet of a turn given up that arrives later, and a packet that arrives
             twice, is discarded and counted (StreamDiagnosis::late).
             After eight or more StreamPackets lost in a row the count cannot tell the
             next ones from late ones: they are discarded as late until the count has
             come round.
             A pause of more than unknownGapMs between two StreamPackets is a loss of
             unknown length: what waits is given on first, the count starts over with
             the next StreamPacket, and the NativePacket that holds it has
             NativePacket::discontinuity.
             The first NativePacket of a session that follows a lost one has
             NativePacket::discontinuity too.
             NativePacket::firstFrame counts every frame given to audio, the zeros of the
             turns given up among them, and runs on from one session to the next.
             NativePacket::arrivalTime is the time at which the first StreamPacket of the
             NativePacket arrived at the PC, less the length of that packet and of the
             turns given up before it. The time stamp the radio puts on a StreamPacket
             is measured (StreamDiagnosis::hostMinusRadioMs) and not used for it.
             When the PC's clock cannot be read, the time runs on from the packet
             before; without one, NativePacket::arrivalTime is absent.
             The adapter gathers StreamPackets until a NativePacket holds groupMs or
             more; a StreamPacket that brings NativePacket::discontinuity, or has no
             arrival time, ends the NativePacket before it early and starts a new one.
             NativePacket::silent is false in every packet.
             Outside the state ready no NativePacket is given. */
        attribute outputRateHz : Integer = 48000;
        attribute reorderPackets : Integer = 5;
        attribute unknownGapMs : Integer = 200;
        attribute groupMs : Integer = 10;
    }

    requirement 'CL-013-07' {
        subject adapter : FlexAdapter;
        doc /* The Flex adapter MUST tune its own slice on request and give a frequency
             as confirmed only when the radio's own report of that slice shows it
             (TuneSlice). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-023'; end #derive ::> 'CL-013-07'; }

    enum def TuneRefusal {
        doc /* Why a tune confirmed nothing.
             radioTimeout: the radio did not answer or did not report the frequency in
             time.
             radioRejected: the radio refused a command.
             radioUnavailable: the session is not ready, is lost during the tune, or
             serves another tune.
             cancelled: the request was withdrawn before or while it was served. */
        enum radioTimeout;
        enum radioRejected;
        enum radioUnavailable;
        enum cancelled;
    }

    action def TuneSlice {
        doc /* One tune of the adapter's slice.
             Read first: the mode and the frequency of the slice as the radio last
             reported them are compared with DIGU and frequencyHz, and
             Command::sliceSet and Command::sliceTune are sent only for what differs.
             After a write the adapter asks for the state of the slices again
             (Command::subSliceAll), since a radio may answer a tune and report nothing.
             The frequency is confirmed when a StatusLine of the slice shows it together
             with DIGU; with nothing to write no command is sent.
             That StatusLine must come by the deadline of the request, and at most
             SessionLifecycle::stepSeconds after the tune began.
             SliceFacts shows the slice as the radio reports it before the answer is
             given, after a confirmation and after a refusal.
             The frequency last confirmed is kept until the station ends, and every
             later session brings its slice to it (SessionSetup). */
        in frequencyHz : Integer;
        out confirmedHz : Integer[0..1];
        out refusal : TuneRefusal[0..1];
    }

    verification 'TC-023-001' {
        doc /* The session, the stream and the tuning on a radio that several stations share. */
        subject adapter : FlexAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-013-01'; verify 'CL-013-02'; verify 'CL-013-04'; verify 'CL-013-05';
            verify 'CL-013-06'; verify 'CL-013-07';
        }
        @TestedBy {
            test = "tests/flexAdapter/native-flex.test.cjs; "
                + "server/src/flexAdapter/session_tests.rs::"
                + "reorder_restores_the_order_and_counts_nothing_lost; "
                + "server/src/flexAdapter/session_tests.rs::"
                + "reorder_gives_up_a_turn_at_its_depth; "
                + "server/src/flexAdapter/session_tests.rs::"
                + "reorder_counts_a_burst_of_lost_packets_up_to_half_the_count; "
                + "server/src/flexAdapter/session_tests.rs::reorder_drops_duplicates; "
                + "server/src/flexAdapter/session_tests.rs::"
                + "reorder_starts_over_after_a_stall; "
                + "server/src/flexAdapter/session_tests.rs::"
                + "a_confirmed_tune_is_published_before_the_caller_hears_of_it; "
                + "server/src/flexAdapter/session_tests.rs::"
                + "a_refused_tune_confirms_nothing_and_keeps_the_reported_slice; "
                + "server/src/flexAdapter/session_tests.rs::"
                + "a_ready_session_starts_its_packet_counters_and_measurements_over; "
                + "server/src/flexAdapter/wire_tests.rs::"
                + "dax_packet_of_a_real_radio_decodes; "
                + "server/src/flexAdapter/wire_tests.rs::"
                + "independent_negative_vectors_are_refused";
        }
    }

    verification 'TC-023-002' {
        doc /* A session from the profile's intent alone. */
        subject adapter : FlexAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-013-01'; verify 'CL-013-03'; verify 'CL-013-04'; verify 'CL-013-07';
        }
        @TestedBy {
            test = "tests/flexAdapter/native-flex.test.cjs; "
                + "server/src/flexAdapter/session_tests.rs::intent_domains";
        }
    }

    verification 'TC-023-003' {
        doc /* What the radio cannot give. */
        subject adapter : FlexAdapter;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-013-01'; verify 'CL-013-02'; verify 'CL-013-03'; verify 'CL-013-04';
        }
        @TestedBy { test = "tests/flexAdapter/native-flex.test.cjs"; }
    }
}

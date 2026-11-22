package WstxRadioSetup {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-009';
    private import WstxRadioControlPart::RadioControlInterface;
    private import WstxRadioControl::*;
    private import WstxRadioProperties::Setting;
    private import WstxRadioProperties::Agc;
    private import WstxKeying::SplitOperation;
    private import WstxModelNotes::CodeDiffers;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-044-01' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST find the radios on the serial ports of the PC by
             reading only, and only after the operator has confirmed that opening a
             port cannot key a transmitter (RadioDetection). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-01'; }

    attribute def KeyingConfirmation {
        doc /* The operator's word, given once, that the radios of this PC do not key
             from a serial line or stand on a dummy load. It is needed because opening
             a port can raise a line for a moment (WstxCat::SerialLine).
             It is RadioRecords::keyingConfirmed. The first DetectRadios that carries
             the confirmation sets it, and radio control hands the record over to be
             kept (RadioMemory). It counts when it has come back as kept; until then,
             and without a record, the keying is not confirmed.
             RadioStatus::keyingConfirmed reports it. */
    }
    attribute def RadioDetection {
        doc /* How DetectRadios is carried out.
             Without keyingInhibitConfirmed it is refused with confirmationRequired
             and no port is opened. One detection runs at a time; a second is refused
             with busy.
             Every serial port present gets a PortReport, the first maxPorts of them.
             The port of the station's own radio connection is not opened a second
             time (PortState::stationCat); while that connection is ready, the radio's
             identity and its menu items are read through it.
             Of the other ports only those on a serial adapter of a known radio are
             opened: the Silicon Labs CP210x with the USB vendor 10C4 and product
             EA60. A port is opened as for the radio connection (OpenRadio).
             On an opened port the radio is asked for its transceiver identity at
             9600, 19200, 38400 and 115200 bits per second in this order: first every
             radio on the link at once, and when none answers, the address of each
             known model. The asking ends at the first rate at which a radio answered.
             An answer is an identity from a radio's address to the controller's; the
             echo, a collision, other frames and noise are not.
             The known models are the IC-7300 at 94, which the station can control,
             and the IC-705 at A4, the IC-9700 at A2 and the IC-7610 at 98, which it
             names only. An identity it does not know is reported as it is.
             The frames sent while detecting are the read of the identity and the
             reads of the menu items of SettingsCheck, and no other.
             Detection changes nothing on a radio and nothing in the profile.
             Detection and the asking of one port are bounded in time; a port not
             reached in time is PortState::notProbed. */
        attribute maxPorts : Integer = 64;
    }

    requirement 'CL-044-02' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST report where the port of each radio it identifies is
             attached, and propose the control of the one radio found that the station
             can control (DetectionProposal). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-02'; }

    attribute def DetectionProposal {
        doc /* What a DetectionReport says beyond the ports.
             PortReport::place is the RadioPlace of the port: the model of its radio,
             the container Windows puts the port in, and the USB hub its device hangs
             on. By it the sound endpoints of the same radio are found.
             RadioStatus::place is the same for the port the profile's endpoint names,
             read from the list of the PC's ports without opening one.
             A proposal is made when exactly one radio among all ports is one the
             station can control. Its control is the mode cat, the endpoint
             "icom7300://COMn?baud=<rate>&radio=<address>&controller=e0" with the port,
             the rate and the address the radio answered at, and PTT by CAT; its AGC
             is slow. With none or several such radios there is no proposal. */
    }

    requirement 'CL-044-03' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST read the menu items of an identified IC-7300 that
             decide whether the station can transmit through it, and say what each
             value means for that (SettingsCheck). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-03'; }

    attribute def SettingsCheck {
        doc /* The SettingFinding of each of the seven items of Setting. The items are
             read and not set.
             usbSend, usbKeyingCw, usbKeyingRtty: OFF is ok; DTR and RTS are blocking,
             because a serial line could key the transmitter. Recommended: OFF.
             dataMod: USB is ok; MIC/USB is advice; every other value is blocking,
             because the transmit audio would not come from the station. Recommended:
             USB.
             usbModLevel: 0 is blocking; every other value is ok. Not set by the
             station.
             civTransceive: OFF is ok; ON is advice. Recommended: OFF.
             dataOffMod: information. Not set by the station.
             An item the radio does not give is unreadable.
             The rate of the link is not an item the radio gives; it is reported as
             the rate the radio answered at. */
    }

    verification 'TC-044-001' {
        doc /* Detection reads and does not write. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-01';
            verify 'CL-044-03';
        }
        @TestedBy {
            test = "server/src/radioControl/setup_tests.rs::"
                + "ic7300_answers_broadcast_at_19200_with_echo; "
                + "server/src/radioControl/setup_tests.rs::"
                + "ic705_answers_only_addressed_read_at_115200; "
                + "server/src/radioControl/setup_tests.rs::"
                + "collisions_and_garbage_before_reply_are_not_replies; "
                + "server/src/radioControl/setup_tests.rs::"
                + "silent_and_timing_out_ports_report_no_reply_after_all_rates; "
                + "server/src/radioControl/setup_tests.rs::unknown_id_is_reported_with_its_id; "
                + "server/src/radioControl/setup_tests.rs::ic7300_menu_read_and_guidance; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "detection_never_opens_station_port_and_proposes_the_station_radio";
        }
    }

    verification 'TC-044-002' {
        doc /* The place of a radio's port, the proposal and the refusals. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-01';
            verify 'CL-044-02';
        }
        @TestedBy {
            test = "server/src/radioControl/setup_tests.rs::"
                + "audio_endpoints_match_by_shared_usb_parent; "
                + "server/src/radioControl/setup_tests.rs::"
                + "endpoint_id_syntax_and_friendly_name_migration; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "detection_never_opens_station_port_and_proposes_the_station_radio; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "detection_of_an_unconfigured_ic7300_probes_it_and_proposes_it; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "http_detect_and_settings_routes_refuse_like_operating_mutations; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "profile_put_refuses_friendly_names_and_accepts_endpoint_ids; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "startup_migration_replaces_unique_friendly_names_only; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "detect_without_the_keying_confirmation_opens_no_port";
        }
    }

    requirement 'CL-044-04' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST set the recommended menu items of the connected IC-7300
             only on the operator's request (RecommendedSettings). */
        @Status { build = ImplementationState::partial; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-04'; }

    attribute def RecommendedSettings {
        doc /* How ApplyRecommended is carried out.
             It is refused: with stateConflict for another connection than the
             current one; with radioUnavailable unless the state is ready; with
             transmitArmed while the transmitter is armed (TransmitterActivity);
             with unsupportedRadio unless the radio answers with the identity of an
             IC-7300.
             Apply reads usbSend, usbKeyingCw, usbKeyingRtty, dataMod and
             civTransceive and sets, in this order, each one that differs from its
             recommended value (SettingsCheck). An item the radio does not give is
             not set. With nothing to set, nothing is written.
             Every item is set by ReadCompareWriteVerify. The first item that fails
             ends the request; SettingsOutcome names it and the error.
             The values before the Apply are not kept. */
        @CodeDiffers {
            what = "server/src/radioControl/radio_setup.rs keeps the values before an Apply in "
                + "radio-settings-undo.json, offers an Undo that writes them back, and "
                + "refuses an Apply with undo_pending while that file names another radio "
                + "address.";
        }
    }

    verification 'TC-044-003' {
        doc /* The recommended menu items are set. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-04'; }
        @TestedBy {
            test = "server/src/radioControl/radio_setup_tests.rs::"
                + "apply_writes_recommended_items_with_undo_record_then_undo_restores; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "apply_refusals_and_failures_stop_without_keying; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "http_detect_and_settings_routes_refuse_like_operating_mutations; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "apply_without_a_ready_connection_is_radio_unavailable";
        }
    }

    requirement 'CL-044-19' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST hold the menu items of the last completed Apply, VOX and
             split on the radio, and set back and show an item changed there
             (HeldSettings). */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-19'; }

    attribute def HeldSettings {
        doc /* What radio control holds on the radio of a ready connection.
             The menu items the last completed ApplyRecommended set, with their values,
             are one record of the station's memory (records); a later completed Apply
             takes its place.
             VOX is held off.
             Split is held on for the split mode rig and off for every other split mode
             (splitMode).
             An item found changed on the radio is set back, and the operator is shown
             that it was changed. */
        attribute records : RadioRecords;
        attribute splitMode : WstxKeying::SplitOperation {
            doc /* The station's split setting. */ }
    }

    requirement 'CL-044-10' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST set the AGC of its configuration on the radio whenever
             a connection becomes ready and whenever the supervisor asks for it
             within a change of the operating selection (ManagedAgc). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-10'; }

    attribute def ManagedAgc {
        doc /* When RadioConfig::agc is set on the radio, each time by
             ReadCompareWriteVerify.
             Once for every connection that becomes ready, and once more on that
             connection when the assignment names another AGC. It waits while the
             transmitter is not at rest (TransmitterActivity). An attempt that ends with
             busy is made again after retrySeconds; every other end is final for that
             connection. An attempt the radio does not answer in time ends with timeout.
             On ApplyAgc, inside the reservation of the supervisor, at once.
             Nothing is sent while the transmitter is not at rest. What comes of it
             is reported and does not fail the change it belongs to.
             Without an AGC in the configuration nothing is read or set. */
        attribute retrySeconds : Integer = 2;
    }

    requirement 'CL-044-11' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST report the AGC it wants on the radio, what the radio
             answered and what came of it, at every change (AgcReport). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-11'; }

    attribute def AgcReport {
        doc /* What AgcStatus holds.
             Without a wanted AGC every feature is absent. With one, and before the
             radio has been asked, the target alone is present.
             After an attempt: the connection it was made on, the value the radio
             reported, the outcome, and the trigger: connect for a connection that
             became ready, selection for ApplyAgc.
             An attempt that failed keeps the value last reported on the same
             connection and gives the error. */
        ref item status : AgcStatus;
    }

    requirement 'CL-044-18' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST set the output power of the station's band on the
             radio and report what came of it, as ManagedPower says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-18'; }

    attribute def ManagedPower {
        doc /* The band's entry of RadioConfig::powers is set on the radio's RF power
             (Hamlib's level RFPOWER), each time by ReadCompareWriteVerify: once for
             every connection that becomes ready, once more when the assignment names
             another power for the band, when the dial radio control confirms lies on
             another band, and on ApplyPower inside the reservation of the supervisor at
             once. It waits while the transmitter is not at rest (TransmitterActivity);
             an attempt that ends with busy is made again after
             ManagedAgc::retrySeconds. A band without an entry, and a radio whose RF
             power cannot be set, leave the power to the radio. What comes of it is
             reported as PowerStatus, as AgcReport says for the AGC, and does not fail
             the change it belongs to. */
        ref item status : PowerStatus;
    }

    verification 'TC-044-009' {
        doc /* The wanted AGC is set at a connection and a change of selection, and reported. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective {
            verify 'CL-044-10';
            verify 'CL-044-11';
        }
        @TestedBy {
            test = "server/src/radioControl/radio_agc_tests.rs::"
                + "connect_applies_the_saved_agc_once_and_pushes_the_read_back; "
                + "server/src/radioControl/radio_agc_tests.rs::"
                + "connect_apply_never_writes_while_transmitting_or_armed; "
                + "server/src/radioControl/radio_agc_tests.rs::"
                + "ft8_and_ft4_selections_apply_the_agc_inside_the_selection; "
                + "server/src/radioControl/radio_agc_tests.rs::"
                + "profile_radio_settings_default_and_validate; "
                + "server/src/radioControl/radio_agc_tests.rs::"
                + "profile_put_keeps_saves_and_refuses_radio_settings; "
                + "server/src/radioControl/radio_agc_tests.rs::"
                + "without_a_wanted_agc_nothing_is_read_or_set; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "detection_never_opens_station_port_and_proposes_the_station_radio";
        }
    }

    requirement 'CL-044-15' {
        subject radioControl : RadioControlInterface;
        doc /* Radio control MUST make sure at station start, by reading only, which
             radio is the profile's, and take the next free radio the station can
             control when the profile's own does not answer (StartDiscovery). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-009'; end #derive ::> 'CL-044-15'; }

    attribute def StartDiscovery {
        doc /* How DiscoverRadio is answered.
             Without the KeyingConfirmation no port is opened and the answer is
             RadioKept. So it is on a profile whose radio is on its native network
             connection.
             A profile with the mode cat and an endpoint RadioConnection takes keeps
             its radio when the port is present, answers with a radio the station can
             control and is granted to this station (ReserveDevice); no other port is
             opened.
             When it does not, and on a profile that was never saved, the other ports
             on a serial adapter of a known radio (RadioDetection) are tried in the
             order of the list of ports. The first that can be opened, answers with a
             radio the station can control and is granted to this station is the
             station's radio: RadioDiscovered gives its control, with the mode cat,
             the endpoint as in DetectionProposal, and PTT as the profile had it with
             the mode cat and by CAT otherwise.
             A port that cannot be opened, and one reserved for another station, are
             passed over; so each station of a PC takes a radio of its own.
             A profile that was saved with the mode disabled, and one whose endpoint
             RadioConnection does not take, keep their control, and no port is
             opened.
             With no radio found the answer is RadioKept.
             The frames sent are reads of the transceiver identity.
             The reservation of the radio kept or discovered lasts as long as the
             station process.
             Discovery is bounded in time: no port is opened after its limit, and the
             asking of a port ends at it. */
    }

    verification 'TC-044-020' {
        doc /* The radio of the profile at station start. */
        subject radioControl : RadioControlInterface;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-044-15'; }
        @TestedBy {
            test = "server/src/radioControl/radio_setup_tests.rs::"
                + "discovery_keeps_a_saved_radio_that_answers; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "discovery_takes_the_next_free_radio_with_its_audio_when_the_saved_one_is_held; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "discovery_changes_nothing_without_a_free_radio_or_against_a_saved_disabled; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "discovery_sets_up_a_profile_never_saved; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "a_second_station_passes_over_a_radio_the_first_reserved; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "discovery_opens_nothing_until_detect_radio_stored_the_confirmation; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "silent_ports_stay_within_the_budget; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "the_reservation_lock_stays_held_and_is_per_port; "
                + "server/src/radioControl/radio_setup_tests.rs::"
                + "discovery_opens_nothing_on_a_native_profile_or_an_endpoint_not_taken";
        }
    }
}

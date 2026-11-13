package WstxAudioEndpoints {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxArchitecture::'FR-002';
    private import WstxArchitecture::'FR-019';
    private import WstxRequirements::AutomationState;
    requirement 'CL-044-07' {
        doc /* GET /audio/endpoints (operating read access as GET /audio/devices, empty query and body) lists the audio endpoints by name without opening any audio device or serial port: exactly {v 1, profile_id, boot_id, inputs, outputs}; inputs are the active capture endpoints, outputs the active render endpoints, at most 64 each (more: device_limit), each exactly {id, name, label, present, radio}. name is the Windows friendly name (PKEY_Device_FriendlyName) with whitespace runs collapsed, trimmed, and no space after "(" or before ")" ("Microphone (USB Audio CODEC )" is "Microphone (USB Audio CODEC)"); the names of POST /radio/detect (input_name, output_name, audio name) are the same names. label is name; when two or more present endpoints of one flow have the same name, each of them gets " #n" (n from 1 in the order of their endpoint IDs), never the ID; when the profile's control is CAT on COMn and exactly one endpoint of the flow shares that port's USB parent (CL-044-02, from the present-port list; no port is opened), radio is "IC-7300" and the label ends " — IC-7300", else radio is null. A saved settings.audio.input_device or output_device that is not present is one more entry of its flow with present false, radio null, name its last known name or null, and label "<last known name> · not present" ("Unknown device · not present" without one). The station remembers the last known name of each saved endpoint in the profile document audio-endpoint-names.json {schema_version 1, names {id: name}} (only the saved endpoints, written only when it changes), refreshed at station start and on each listing; GET /receive audio.device_name is the known name of device_id (the names seen in the latest listing or the remembered ones), else null. An enumeration failure is 409 audio_unavailable, as GET /audio/devices. Strings are literal data. */
        attribute coverage : ImplementationState = ImplementationState::implemented;
        attribute implementation : String = "server/src/radio_control/setup.rs; server/src/radio_setup.rs; server/src/recording.rs; server/src/main.rs";
    }
    dependency CL_044_07_to_FR_002 from 'CL-044-07' to 'FR-002';
    dependency CL_044_07_to_FR_019 from 'CL-044-07' to 'FR-019';
    verification 'TC-044-006' {
        doc /* TC-044-006 — Endpoint names, labels and remembered names
             CL-044-07
             Setup: hand-written endpoint and port lists (no audio device): the CODEC capture "Microphone (USB Audio CODEC )" and render "Speakers (USB Audio CODEC )" under the IC-7300's USB hub with COM3, two capture endpoints both named "Headset Microphone (Sennheiser Communication Audio)" elsewhere; the actual router on a disposable profile with the injected detection hardware double.
             Steps: (a) label the capture and render lists with the profile control on COM3; (b) the same with control disabled; (c) a saved input that is absent, with and without a remembered name; (d) GET /audio/endpoints with the saved CODEC input, then with the CODEC unplugged from the double; GET /receive audio.device_name for a live receive on that input; reopen the remembered names; (e) a query, an enumeration failure.
             Expected: (a) "Microphone (USB Audio CODEC) — IC-7300" radio IC-7300, "Speakers (USB Audio CODEC) — IC-7300", the two headsets "... #1" and "... #2" ordered by ID, no label containing "{"; (b) the same names without the radio suffix, radio null; (c) "Microphone (USB Audio CODEC) · not present" present false, and "Unknown device · not present"; (d) exact key sets, the remembered name file holding only the saved IDs, after unplugging the saved input listed not present with its last name, device_name "Microphone (USB Audio CODEC)", the name still known after reopening; (e) 400 invalid_request, 409 audio_unavailable.
             2 — Isolated automated tests; Windows development PC, no radio, audio or RF. */
        attribute automation : AutomationState = AutomationState::implemented;
        objective {
            verify 'CL-044-07';
        }
        attribute executable : String = "server/src/radio_control/setup_tests.rs; server/src/radio_setup_tests.rs";
    }
    dependency CL_044_07_verified_by_TC_044_006 from 'CL-044-07' to 'TC-044-006';
}

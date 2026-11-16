package WstxAudioControl {
    private import ScalarValues::*;
    private import WstxAudioStreams::SourceError;
    private import ModelNotes::FollowsSource;

    doc /* The configuration and the records of the audio function; what the station
         service gives audio (its configuration, its records, the request for the
         endpoint list) and the state audio reports. */

    enum def AudioState {
        doc /* The state of the capture.
             closed: not wanted and not open.
             opening: wanted; the connection is being opened.
             running: packets arrive.
             closing: the capture was stopped; the connection is being closed.
             unavailable: the connection is missing, failed or did not close. */
        enum closed;
        enum opening;
        enum running;
        enum closing;
        enum unavailable;
    }
    enum def CaptureWarning {
        doc /* What the operator should know about the capture clock. At most one holds.
             uncorrelated: the current epoch is not tied to station time.
             driftHigh: the capture clock drifts more than the limit of the capture
             clock allows. */
        enum uncorrelated;
        enum driftHigh;
    }

    attribute def AudioConfig {
        doc /* The configuration of the audio function: the two sound endpoints of the
             PC the operator chooses for the station, each by its id. Each of the two
             is set by itself: the one does not need the other, and neither needs a
             radio control. An entry names an endpoint; it does not say that the
             endpoint is present.
             An id is a text of 1 to 256 bytes of UTF-8 without a control character
             (U+0000 to U+001F and U+007F to U+009F): for an input
             {0.0.1.00000000}.{ and a GUID and }, for an output {0.0.0.00000000}.{ and
             a GUID and }. The GUID is 8, 4, 4, 4 and 12 hexadecimal digits with
             hyphens between, in either case. */
        @FollowsSource {
            reference = "Windows Core Audio: the endpoint ID string of an audio endpoint "
                + "device";
        }
        attribute input_device : String[0..1] = null {
            doc /* The input device: the capture endpoint audio makes the receive
                 stream from. Absent: none is chosen, and no capture is opened. */ }
        attribute output_device : String[0..1] = null {
            doc /* The output device: the render endpoint audio plays the transmit
                 program on. Absent: none is chosen, and nothing is played. */ }
    }
    attribute def NamedEndpoint {
        doc /* One audio endpoint: its id and the name its driver gives it. */
        attribute id : String;
        attribute name : String;
    }
    attribute def AudioRecords {
        doc /* What audio wants kept across the sessions of the station. No menu shows a
             record. */
        attribute lastNames : NamedEndpoint[0..2] {
            doc /* The last known name of each endpoint of AudioConfig, so that the
                 endpoint list can name an endpoint that is not present. Absent for an
                 endpoint whose name was never read. */ }
    }
    item def AudioDevices {
        doc /* The configuration of audio, given at station start and whenever the
             station config changes. Audio opens a capture and an output on the
             endpoints last given. */
        attribute config : AudioConfig;
    }
    item def AudioMemory {
        doc /* The records of audio. The station service gives them at station start,
             as the profile holds them. Audio gives them whenever it has changed one,
             and the station service answers with the records as the profile holds
             them then. */
        attribute records : AudioRecords;
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
    item def ListEndpoints {
        doc /* List the sound endpoints of the PC. */
        attribute radio : RadioPlace[0..1] {
            doc /* Absent while the profile controls no radio by CAT on a serial
                 port. */ }
    }

    attribute def EndpointEntry {
        doc /* One endpoint in the list. */
        attribute id : String;
        attribute name : String[0..1] {
            doc /* Its name; for an endpoint that is not present its last known name,
                 absent when none is known. */ }
        attribute label : String { doc /* What a list shows for it. */ }
        attribute present : Boolean;
        attribute radio : String[0..1] {
            doc /* The model of the radio the endpoint belongs to; absent when that is
                 not known. */ }
    }
    item def EndpointList {
        attribute inputs : EndpointEntry[0..*];
        attribute outputs : EndpointEntry[0..*];
    }
    item def AudioStatus {
        doc /* The state of the capture at the moment it is read. */
        attribute 'state' : AudioState;
        attribute error : SourceError[0..1] {
            doc /* Present in the state unavailable. */ }
        attribute retryAfterMs : Integer[0..1] {
            doc /* The time to the next attempt to open; absent when none is planned. */ }
        attribute captureDriftMs : Integer[0..1] {
            doc /* How far the capture clock has moved from its tie to station time;
                 absent until measured. */ }
        attribute captureDriftPpm : Real[0..1] {
            doc /* The rate of that movement; absent until it is known. */ }
        attribute warning : CaptureWarning[0..1] { doc /* Absent while none holds. */ }
    }

    port def AudioStatusPort {
        doc /* Written from audio's side; the station service uses the conjugate.
             ListEndpoints is answered by EndpointList or by a refusal; an AudioMemory
             of audio by an AudioMemory of the station service. */
        in item devices : AudioDevices;
        in item kept : AudioMemory;
        out item keep : AudioMemory;
        in item list : ListEndpoints;
        out item status : AudioStatus;
        out item endpoints : EndpointList;
        out item refused : ListRefused;
    }
    enum def ListRefusal {
        enum deviceLimit;
        enum audioUnavailable;
    }
    item def ListRefused {
        attribute reason : ListRefusal;
    }
    interface def AudioControl {
        doc /* The station service commands the audio function; audio reports its
             state. */
        end station : ~AudioStatusPort;
        end audio : AudioStatusPort;
    }
}

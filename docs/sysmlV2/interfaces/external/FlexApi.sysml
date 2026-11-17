package WstxFlexApi {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;

    doc /* The network API of a FlexRadio: the radio's announcements, its control connection
         and its receive stream. A radio on a sound device and a CAT link is not reached
         over it. Only what the station chooses is stated here; every layout, port and code
         is the source's. */

    attribute def ProtocolVersion {
        doc /* The version of the source the station speaks. */
        attribute admitted : String = "1.4.0.0";
    }

    item def Announcement {
        doc /* What a radio says about itself on the local network (the source's discovery
             packet). The station sends none and asks for none.
             It reads the serial, the model, the firmware version, the address, the port
             and availableClients, and no other field.
             An announcement without a serial is not used. */
        attribute availableClients : Integer[0..1] {
            doc /* How many more clients the radio takes. Absent when the radio does not
                 say. */ }
    }

    item def Greeting {
        doc /* What the radio states when the control connection opens. */
        attribute version : String {
            doc /* The version of the source the radio speaks. */ }
        attribute handle : Integer {
            doc /* The handle the radio gives this client for this connection. The radio
                 names the owner of a slice and of a stream by it. */ }
    }
    enum def Command {
        doc /* The commands of the source the station sends, each by the source's text.
             info: "info".
             subClientAll: "sub client all".
             clientStartPersistenceOff: "client start_persistence off".
             clientGui: "client gui", with a client identity.
             subSliceAll: "sub slice all".
             subDaxAll: "sub dax all".
             clientUdpport: "client udpport", with a UDP port of the PC.
             sliceCreate: "slice create", with rxant and mode.
             sliceSet: "slice set", with the number of a slice and dax or mode.
             streamCreate: "stream create type=dax_rx", with dax_channel.
             sliceTune: "slice tune", with the number of a slice and a frequency in MHz
             to the hertz.
             sliceRemove: "slice remove", with the number of a slice. */
        enum info;
        enum subClientAll;
        enum clientStartPersistenceOff;
        enum clientGui;
        enum subSliceAll;
        enum subDaxAll;
        enum clientUdpport;
        enum sliceCreate;
        enum sliceSet;
        enum streamCreate;
        enum sliceTune;
        enum sliceRemove;
    }
    item def CommandLine {
        doc /* One command to the radio. The station waits for its Reply before it sends
             the next. */
        attribute command : Command;
    }
    item def Reply {
        doc /* The radio's answer to one CommandLine, matched by the number the source
             puts on both. */
        attribute code : Integer {
            doc /* 0 when the radio has done what was asked; every other code is a
                 refusal. */ }
    }
    item def StatusLine {
        doc /* What the radio reports about one of its objects, unasked and after a
             subscription.
             Of a client the station reads its handle, its client identity and that it
             has disconnected.
             Of a slice it reads in_use, client_handle, RF_frequency, mode, rxant, dax
             and index_letter, and that it was removed.
             Of a stream it reads type, dax_channel and client_handle, and that it was
             removed.
             Every other object, field and line of the radio is passed over. */
    }

    item def Registration {
        doc /* A datagram from the UDP port the stream goes to, naming the client's handle
             (the source's "client udp_register"). It opens the way back for the stream
             on a path that carries no announcement. */
    }
    item def StreamPacket {
        doc /* One packet of the radio's DAX receive stream. The station takes one format:
             two channels of 32-bit float at 24 kHz. A packet of the stream in another
             format is not used. */
        attribute streamId : Integer {
            doc /* The identity the radio gave the stream. */ }
        attribute count : Integer {
            doc /* The packet's number in its stream, from 0 to 15 and round again. */ }
    }

    port def FlexApiPort {
        doc /* Written from the station's side; the radio uses the conjugate. */
        @FollowsSource {
            reference = "SmartSDR TCP/IP API (FlexRadio) at ProtocolVersion::admitted, with "
                + "FlexLib 4.3.16 as its reference implementation; discovery and stream "
                + "packets in the form of ANSI/VITA 49.0";
        }
        in item announcement : Announcement;
        in item greeting : Greeting;
        out item command : CommandLine;
        in item reply : Reply;
        in item status : StatusLine;
        out item registration : Registration;
        in item stream : StreamPacket;
    }
    interface def FlexApi {
        doc /* The Flex adapter and a FlexRadio's native API. */
        end flexAdapter : FlexApiPort;
        end radio : ~FlexApiPort;
    }
}

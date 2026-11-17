package WstxStationLink {
    private import ScalarValues::*;
    private import WstxStationCommands::StationOperations;
    private import WstxDisplayData::SpectrumFrame;
    private import WstxDisplayData::DetailedSpectrumFrame;
    private import WstxStationTime::StationTime;
    private import ModelNotes::FollowsSource;

    doc /* How the features of the station boundary (WstxStationCommands::StationOperations)
         travel between a station's browser clients and its web function, by HTTP and on
         the one WebSocket of each browser, with the display rows and what the connection
         holds of its own. */

    port def BrowserExchange :> StationOperations {
        doc /* Written from the browser's side; web uses the conjugate. */
        in item spectrum : SpectrumFrame;
        in item detailedSpectrum : DetailedSpectrumFrame;
        in item time : StationTime;
    }
    interface def StationLink {
        doc /* A browser client and the web function of its station. */
        end client : BrowserExchange;
        end web : ~BrowserExchange;
    }

    attribute def WireNames {
        doc /* Every name on the wire and in the station's JSON files is a model name in
             snake_case: each capital letter becomes an underscore and its small letter,
             digits stay with the word before them (setTx1Skip: set_tx1_skip). Three names
             give their number a word of its own: treat73AsCq, onePlusPer3000Km and
             onePlusPer500KmUp (treat_73_as_cq, one_plus_per_3000_km,
             one_plus_per_500_km_up). This holds for the keys of JSON objects, the values
             of enumerations, the route segments, the query parameters and the event
             types.
             The function of a feature of StationOperations is the part whose control
             interface defines the feature's item: supervisor for WstxStationCommands, qso
             for WstxQsoControl, auto for WstxAutoControl, ranking for WstxRankingControl,
             operating for WstxStrategies, receive for WstxReceiveControl, transmit for
             WstxTransmitControl, log for WstxLogControl, radio_control for
             WstxRadioControl, audio for WstxAudioControl, spots for WstxHearing, udp for
             WstxUdpControl, clock for WstxStationTime, profile for WstxProfileAccess and
             WstxRecordingTransfer.
             The route of a feature is /, its function, / and the feature's name; a feature
             named as its function has the route / and its function. */
    }

    attribute def JsonValues {
        doc /* A value travels as JSON: an Integer as a JSON integer from 0 up to
             safeIntegerMax, or a negative one where the attribute allows it; a Real as a
             JSON number; a Boolean as true or false; a String as a JSON string; an
             enumeration literal as its name (WireNames); an attribute or item typed by a definition
             as an object of its attributes; a multiplicity above one as an array, in the
             order of the attribute when it is ordered; an absent optional value as null.
             An object has exactly its keys: a key that is missing, unknown or given twice
             makes the request invalidRequest with that key as field. */
        @FollowsSource { reference = "RFC 8259 (JSON); UTF-8 (RFC 3629)"; }
        attribute safeIntegerMax : Integer = 900719925 * 10000000 + 4740991;
    }

    attribute def WireRule {
        doc /* A command is the POST of its route. Its body is one JSON object: v (1),
             profileId, bootId and commandId of the StationRequest, and the attributes
             of the command's item. The requester is operator for every request web
             passes on.
             A read is the GET of its route; the attributes of the read's item are its
             query parameters, an absent one left out.
             A view is the GET of its route; the answer is one JSON object: v, profileId,
             bootId and the view's attributes. On the socket the view is the event of
             type function, a dot and the feature's name, or function and .state for a
             view named as its function (SocketProtocol).
             An answer is 200 with one JSON object: v, profileId, bootId, commandId for
             a command, and the answer's attributes. A refusal answers with ErrorBody and
             the status of StatusRule: StationRefused, SelectionRefused, RankingRefused,
             StrategiesRefused, AutoRefused, Refused of receive, CursorExpired, LogRefused,
             SettingsRefused, DetectRefused, ListRefused, SaveRefused and ImportRefused,
             and every other answer whose refusal is present.
             The settings take the methods of HTTP for documents: saveConfig is the PUT of
             /profile/config and saveShack the PUT of /profile/shack, each with the body of
             a command; createEntry is the POST of /profile and the collection's name
             (WstxProfileAccess::SettingsCollection), updateEntry its PUT and deleteEntry
             its DELETE with a slash and the member's key after it, coded as a path
             segment; the item's collection and key stand in the route, not in the body.
             The transfers of files follow Transfers. */
        @FollowsSource { reference = "RFC 9110 (HTTP semantics); RFC 3986 (URI)"; }
    }

    enum def WireRefusal {
        doc /* The refusals of the connection itself, before the supervisor sees the
             request.
             forbiddenOrigin: a request that changes something, or a socket, without
             exactly the station's origin in Origin.
             requestTooLarge: a body above its limit (Limits).
             unsupportedMediaType: a body of another type than application/json, at
             most with charset=utf-8, where JSON is due.
             invalidRequest: a request that is not the form of its item.
             unsupportedVersion: v other than 1.
             notFound: no route, or no member with the key. */
        enum forbiddenOrigin;
        enum requestTooLarge;
        enum unsupportedMediaType;
        enum invalidRequest;
        enum unsupportedVersion;
        enum notFound;
    }
    attribute def ErrorBody {
        doc /* The body of every refusal: exactly {"error": {"code", "field"}}. code is the
             refusal's literal; field is the wire name of the value the refusal is about,
             or null. No text of the request is returned. */
        attribute code : String;
        attribute 'field' : String[0..1];
    }
    attribute def StatusRule {
        doc /* The HTTP status of a refusal, by its code: 400 for invalidRequest,
             unsupportedVersion and every code that begins with invalid_ or is
             outOfRange; 403 for forbiddenOrigin and wrongProfile; 404 for notFound;
             410 for cursorExpired; 413 for requestTooLarge; 415 for
             unsupportedMediaType; 422 for invalidRecording, unsupportedAudio,
             recordingLimit and importFailed; 502 for downloadFailed; 503 for
             storageUnavailable; 409 for every other code. */
        @FollowsSource { reference = "RFC 9110 section 15 (status codes)"; }
    }
    attribute def RequestOrder {
        doc /* The checks of a request, in this order; the first that fails answers:
             the route and its method (notFound; a method the route has not: 405 with
             Allow); Origin; the media type; the size of the body; the form of the item
             and v; then the supervisor (WstxStationAuthority::ReceiptRule, GateRule) and
             the function. A GET may come without Origin; one with an Origin that is not
             the station's is refused. */
    }

    attribute def Limits {
        doc /* The largest body web takes, in bytes of UTF-8. Every request not named
             below: controlBytes. */
        attribute controlBytes : Integer = 1024;
        attribute recordBytes : Integer = 8192 {
            doc /* saveRecord: a comment of 1024 characters fits with every character
                 escaped. */ }
        attribute settingsBytes : Integer = 32768 {
            doc /* saveConfig, saveShack, createEntry and updateEntry. */ }
        attribute logChunkBytes : Integer = 16384 { doc /* A part of a logbook file. */ }
        attribute recordingChunkBytes : Integer = 2048 {
            doc /* A part of a recording's file. */ }
    }

    attribute def Transfers {
        doc /* The features that carry a file, and the page.
             importChunk is the PUT of /log/import/ and the import's id, recordingChunk the
             PUT of /profile/recording/ and the import's id: the body is the part of the
             file as bytes (application/octet-stream for the logbook, audio/wav for a
             recording, without a content coding), with exactly one Content-Range of the
             form bytes start-end/total; its answer is the import's view.
             export is the GET of /log/export: the logbook as an ADIF file,
             application/octet-stream, as the attachment contacts.adi, sent in parts as the
             log gives them (ExportChunk), without a Content-Length.
             The page is the GET of /, its scripts and styles each the GET of its file
             name (WstxListener::ClientFiles). */
        @FollowsSource { reference = "RFC 9110 section 14.4 (Content-Range); ADIF 3"; }
    }

    enum def RequestError {
        doc /* The refusals of a message on the socket.
             invalidJson: not a JSON object. invalidRequest: not the form of its type.
             unsupportedVersion: v other than 1. unknownCommand: a type the socket does
             not take. */
        enum invalidJson;
        enum invalidRequest;
        enum unsupportedVersion;
        enum unknownCommand;
    }
    enum def DisplayProfile {
        doc /* What a socket receives of the display. off: no rows. thin: the thin rows.
             detail: the detailed rows. */
        enum off;
        enum thin;
        enum detail;
    }
    attribute def SocketProtocol {
        doc /* Each browser holds one WebSocket to its station: the GET of /ws with exactly
             the station's origin and the subprotocol wstx.v1. Its messages are text, each
             one JSON object of at most Limits::controlBytes from the browser; a binary
             message closes the socket with 1003.
             The browser sends {v, type, id}, id a JSON integer chosen by the browser:
             station.get, answered by station.status {v, type, id, data {version, build}}
             with the station's version and the client's build (WstxListener::ClientBuild);
             spectrum.off, spectrum.thin and spectrum.detail, answered by
             spectrum.subscription {v, type, id, data {profile}} with the DisplayProfile. A
             refused message is answered by error {v, type, id, data {code}} with a
             RequestError, id null when none could be read; the socket stays open.
             The station sends heartbeat {v, type} and a ping every heartbeatMs; the
             browser answers the ping.
             A socket starts at off. From its first subscription on it receives the event
             of each view: {v, type, data {profileId, bootId, changed}}, changed the
             attributes whose values differ from the last event of that view on this
             socket, all of them in the first. An event follows a change within
             eventDelayMs; a view changing faster is sent at most once per eventDelayMs,
             with its latest values. openSlots goes to thin and detail only. The rows go
             as DisplayRows says. Once a second the station sends clock.time {v, type,
             data {bootId, utcMs, timeState}} with station time (StationTime). */
        @FollowsSource { reference = "RFC 6455 (WebSocket)"; }
        attribute heartbeatMs : Integer = 5000;
        attribute eventDelayMs : Integer = 1000;
    }
    attribute def DisplayRows {
        doc /* A socket at thin receives each row of the job as spectrum.frame, one at
             detail each detailed row as spectrum.detail.frame: {v, type, data} with
             bootId and the attributes of the row; the job's identity as sourceId and
             jobId; the levels of a detailed row as levelsB64, the 1024 levels as bytes
             in standard base64 with padding (1368 characters); the key tx only when the
             row is of a transmitted period. A detailed row waits for a slow socket up to
             detailRecentRows rows; a socket that falls further behind loses the oldest.
             A new subscription begins at the newest row. */
        @FollowsSource { reference = "RFC 4648 section 4 (base64)"; }
        attribute detailRecentRows : Integer = 25;
    }

    attribute def ThinLinkBudget {
        doc /* The link the station is built to work on: two browsers share one link of
             bitsPerSecond in each direction with roundTripMs. Targets of normal operation,
             judged from the link byte log (WstxListener::LinkTrafficLog), each over
             measurementSeconds and per direction with the heartbeat: two browsers at thin
             during live receive on a busy band and one contact, at most thinBytesPerSecond;
             at off with the operator idle, at most idleBytesPerSecond; the station's state
             shown within statusShownMs of a refresh. The page and its files, a reconnection,
             a selection, a recording and an import carry no target, nor does detail. */
        attribute bitsPerSecond : Integer = 32000;
        attribute roundTripMs : Integer = 300;
        attribute measurementSeconds : Integer = 60;
        attribute thinBytesPerSecond : Integer = 3000;
        attribute idleBytesPerSecond : Integer = 1000;
        attribute statusShownMs : Integer = 2000;
    }
}

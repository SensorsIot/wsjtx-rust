package WstxProfileAccess {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;
    private import WstxRadioControl::ControlSelection;
    port def ProfileAccess {
        out item request : ProfileRequest;
        in item outcome : ProfileOutcome;
    }
    item def ProfileRequest;
    item def ProfileOutcome;

    enum def ConnectionType { enum 'standard'; enum native_flex; }
    enum def HttpOutcome {
        doc /* The outcome of GET or PUT /profile; HttpStatus gives its status and
             HttpProfileError its body. */
        enum ok; enum forbidden_origin; enum unauthorized; enum unsupported_media_type;
        enum request_too_large; enum invalid_settings; enum wrong_profile;
        enum revision_conflict; enum revision_exhausted; enum storage_unavailable;
    }

    attribute maxRevision : Integer = (900719925 * 10000000 + 4740991) {
        doc /* The largest revision: 2^53 - 1, the largest integer a JSON number carries
             exactly. */
        @FollowsSource { reference = "RFC 7493 section 2.2"; }
    }

    attribute def AudioSelection {
        doc /* Exactly the keys input_device and output_device, both required and nullable:
             null is a JSON null, never an omitted key. A value is opaque nonempty UTF-8 of at
             most 256 bytes without U+0000..001F or U+007F..009F. The two are saved
             independently; saving them enumerates and opens no device. The browser offers
             them by endpoint name (CL-044-08). */
        attribute input_device : String[0..1] = null;
        attribute output_device : String[0..1] = null;
    }
    enum def AgcSetting { enum FAST; enum MID; enum SLOW; }
    attribute def RadioSettings {
        doc /* The radio settings the station manages over CAT (CL-044-10): present exactly
             while control is CAT on an IC-7300 CI-V endpoint. agc is FAST, MID or SLOW,
             SLOW for FT8 and FT4 on the IC-7300. RadioSettings is separate from
             ControlSelection, which identifies the receive-only confirmation. */
        doc /* power_limit_pct (CL-044-12), optional 1..100, is the profile power: the Po in
             percent of the radio's full scale that the Tx level never drives above; without
             it only the radio's own RF power setting limits it. The Tx level is not in the
             profile document: it is tx-level.json in the profile directory, and storing it
             does not advance the revision. */
        attribute agc : AgcSetting = AgcSetting::SLOW;
        attribute power_limit_pct : Integer[0..1];
    }
    attribute def Settings {
        doc /* The five editable fields and the optional radio (CL-044-10). display_name is
             1..64 UTF-8 bytes without leading or trailing whitespace or control characters
             (U+0000..001F, U+007F..009F). callsign is empty or 3..12 ASCII uppercase letters,
             digits or slash with at least one letter and one digit. locator is empty or a
             4, 6 or 8 character Maidenhead locator, [A-R]{2}[0-9]{2}([A-X]{2}([0-9]{2})?)?. No
             value is normalized and no national callsign rule is claimed. An invalid value is
             refused, never replaced by a default. */
        doc /* radio is present exactly for a managed radio; an edit without it keeps the
             saved value. The browser renders every string of the profile literally, also in
             the title and in errors, never as markup. */
        attribute display_name : String = "New station";
        attribute callsign : String = "";
        attribute locator : String = "";
        attribute audio : AudioSelection;
        attribute control : ControlSelection;
        attribute radio : RadioSettings[0..1];
    }
    attribute def Endpoint {
        doc /* Exactly the keys bind and origin. bind is a numeric socket address, IP and port
             1..65535; port 0 is refused in profile mode. origin is required and nullable: null
             only for a loopback bind, whose origin is then the scheme, the bound IP and the
             port; otherwise scheme://host:port without credentials, path, query, fragment or
             trailing slash, whose scheme matches the runtime TLS and whose port is the bind
             port. The host may be localhost or a DNS alias of the listener. A non-loopback
             bind needs an explicit HTTPS origin and runtime TLS and token. The station is
             reached directly: no proxy remaps it. */
        doc /* The effective browser origin, the one readiness, GET /profile, the page and the
             Origin checks use, keeps an explicit alias rather than the numeric bind. */
        attribute 'bind' : String = "127.0.0.1:8080";
        attribute origin : String[0..1] = null;
    }
    attribute def ProfileDocument {
        doc /* profile.json: a UTF-8 JSON object of at most profileFileMaxBytes with exactly the
             keys schema_version, profile_id, revision, display_name, callsign, locator,
             endpoint, connection_type, audio, control and, for a managed radio, radio. The
             Settings fields stand flat in the object, not in a nested settings key. Malformed
             UTF-8 or JSON, a duplicate, unknown or missing key, a wrong type or a value outside
             its domain is refused. The document holds no TLS path, token, contact or
             recording. */
        doc /* profile_id is a lowercase hyphenated UUID v4 chosen at creation; neither the
             station nor the browser changes it, and an edit of it in the file is
             unsupported. */
        @FollowsSource { reference = "RFC 9562 section 5.4 (UUID version 4)"; }
        attribute schema_version : Integer = 1;
        attribute profile_id : String;
        attribute revision : Integer = 0;
        attribute settings : Settings;
        attribute endpoint : Endpoint;
        attribute connection_type : ConnectionType = ConnectionType::'standard';
        assert constraint supportedSchema { schema_version == 1 }
        assert constraint supportedBackend { connection_type == ConnectionType::'standard' }
        assert constraint safeRevision { revision >= 0 and revision <= maxRevision }
    }
    attribute def NativeProfileDocument {
        doc /* The profile of a native FlexRadio station (FR-023), chosen at creation: the keys
             of ProfileDocument with schema_version 2, connection_type native_flex and the
             required key native. Its audio selections are null, its control and PTT disabled,
             and it has no radio settings. Radio serial, slice index or letter, DAX channel,
             stream ID, client handle and tuning are never persisted. GET and PUT /profile
             keep their shapes, and the connection type is not editable. A binary that knows
             only schema 1 refuses it as unsupported_schema. */
        attribute schema_version : Integer = 2;
        attribute profile_id : String;
        attribute revision : Integer = 0;
        attribute settings : Settings;
        attribute endpoint : Endpoint;
        attribute connection_type : ConnectionType = ConnectionType::native_flex;
        attribute native : NativeIntent;
    }
    attribute def NativeIntent {
        doc /* The key native: client_id is a lowercase UUID v4 generated at creation, this
             station's GUI-client identity and not a radio identity; rx_antenna is 1..16
             uppercase letters, digits or underscore; radio_address, optional, is an IPv4
             address:port, a locator for a radio that discovery cannot reach, never an
             identity and never compared. */
        attribute client_id : String;
        attribute rx_antenna : String;
        attribute radio_address : String[0..1];
    }

    item def HttpProfileGet :> WstxStationCommands::StationRequest {
        doc /* GET /profile. Over TLS it needs the selected profile's cookie
             (WstxStationProtocol::AuthenticateProfile). A supplied Origin is exact; an absent
             Origin is permitted for an ordinary same-origin GET. No CORS permission is
             given. */
    }
    item def HttpProfilePut :> WstxStationCommands::StationRequest {
        doc /* PUT /profile: a JSON body of at most profileHttpMaxBytes UTF-8 bytes with exactly
             these keys, Content-Type application/json with an optional UTF-8 charset. */
        attribute profile_id : String;
        attribute revision : Integer;
        attribute settings : Settings;
    }
    item def SaveProfile :> WstxProfileAccess::ProfileRequest {
        doc /* The station forwards validated settings and revision to its own selected
             profile; a request never selects a directory. */
        attribute profile_id : String;
        attribute expectedRevision : Integer;
        attribute settings : Settings;
    }
    item def ProfileSnapshot :> WstxProfileAccess::ProfileOutcome {
        doc /* The selected profile inside the station; the runtime inputs stay private. */
        attribute document : ProfileDocument;
    }
    item def HttpProfileRepresentation :> WstxStationCommands::StationOutcome {
        doc /* The 200 body of GET and PUT /profile with exactly these keys: application/json,
             Cache-Control no-store, at most profileHttpMaxBytes. endpoint is the effective
             browser origin, not the bind object. No path, secret, schema_version or internal
             object is exported. */
        attribute profile_id : String;
        attribute boot_id : String;
        attribute revision : Integer;
        attribute endpoint : String;
        attribute connection_type : ConnectionType;
        attribute settings : Settings;
    }
    item def HttpProfileError :> WstxStationCommands::StationOutcome {
        doc /* The error body {"error":{"code":<outcome>,"field":<field>}}; field is a dotted
             field name for invalid_settings where one applies, null otherwise. No value, path
             or exception is echoed. */
        attribute outcome : HttpOutcome;
        attribute field : String[0..1];
    }
}

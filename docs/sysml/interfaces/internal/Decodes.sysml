package WstxDecodes {
    private import ScalarValues::*;
    port def DecodesPort { out item result : ResultRecord; }
    interface def Decodes {
        doc /* The decoded messages of each period, from receive to a consumer. */
        end receive : DecodesPort;
        end consumer : ~DecodesPort;
    }
    enum def FrameStatus {
        doc /* decoded: a payload of a supported family with valid content. unsupported: a
             CRC-valid payload of a family the product does not unpack. invalid_payload: a
             CRC-valid payload of a supported family whose content is outside its domain. */
        enum decoded;
        enum unsupported;
        enum invalid_payload;
    }
    enum def CallKind { enum call; enum token; enum hash; }
    enum def ExchangeKind { enum blank; enum grid; enum report; enum roger; }

    attribute def CallValue {
        attribute kind : CallKind;
        attribute text : String[0..1];
        attribute hash_bits : Integer[0..1];
        attribute hash_value : Integer[0..1];
        doc /* A call or a token (CQ, DE, QRZ, a CQ modifier) has its text and null hash
             fields; a concrete call is 1 to 13 upper-case characters, 11 at most in a
             nonstandard message. A hash has its width (10, 12 or 22 bits) and its value,
             and null text, or, in a station's live publication, the call HashResolution
             filled in, without brackets; its kind stays hash. */
    }
    attribute def StandardExchange {
        attribute kind : ExchangeKind;
        attribute textValue : String[0..1];
        attribute numericValue : Integer[0..1];
        doc /* On the wire exactly {kind, value}: blank null, grid a 4-character grid, report
             an integer -50..50, roger RRR, RR73 or 73. */
    }
    attribute def PayloadFields {
        doc /* The fields of a decoded payload: one variant per message family, each with all
             its keys and no others. */
    }
    attribute def FreeTextFields :> PayloadFields {
        attribute 'type' : String = "free_text";
        attribute value : String;
        doc /* Family 0.0: 1 to 13 characters, trailing padding trimmed; all blank is invalid. */
    }
    attribute def TelemetryFields :> PayloadFields {
        attribute 'type' : String = "telemetry";
        attribute value : String;
        doc /* Family 0.5: 18 upper-case hex digits, the first 0 to 7. */
    }
    attribute def StandardFields :> PayloadFields {
        attribute 'type' : String = "standard";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute exchange : StandardExchange;
        doc /* Families 1 (/R) and 2 (/P). */
    }
    attribute def RttyFields :> PayloadFields {
        attribute 'type' : String = "rtty";
        attribute tu : Boolean;
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute report : Integer;
        attribute exchangeKind : String;
        attribute serial : Integer[0..1];
        attribute stateToken : String[0..1];
        doc /* Family 3: on the wire the exchange is {kind, value}, a serial 0..7999 or a
             state or province 8001..8171. */
    }
    attribute def DxpeditionFields :> PayloadFields {
        attribute 'type' : String = "dxpedition";
        attribute 'first' : CallValue;
        attribute 'second' : CallValue;
        attribute hashed : CallValue;
        attribute report : Integer;
        doc /* Family 0.1. */
    }
    attribute def FieldDayFields :> PayloadFields {
        attribute 'type' : String = "field_day";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute transmitters : Integer;
        attribute 'class' : String;
        attribute section : String;
        doc /* Families 0.3 (1 to 16 transmitters) and 0.4 (17 to 32). */
    }
    attribute def NonstandardFields :> PayloadFields {
        attribute 'type' : String = "nonstandard";
        attribute full_call : CallValue;
        attribute hashed_call : CallValue;
        attribute hash_second : Boolean;
        attribute cq : Boolean;
        attribute roger : String[0..1];
        doc /* Family 4. A nonstandard CQ shows no hash and keeps its bits. */
    }
    attribute def VhfFields :> PayloadFields {
        attribute 'type' : String = "vhf";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute report : Integer;
        attribute serial : Integer;
        attribute grid : String;
        doc /* Family 5, the EU VHF contest message. */
    }

    item def ResultRecord :> WstxModeProcessing::ProcessingResult {
        attribute sequence : Integer;
        attribute status : FrameStatus;
        attribute payload77 : String;
        attribute i3 : Integer;
        attribute n3 : Integer[0..1];
        attribute text : String[0..1];
        attribute fields : PayloadFields[0..1];
        attribute start_frame : Integer;
        attribute frequency_hz : Real;
        attribute snr_db : Real[0..1];
        attribute a_priori : Integer[0..1];
        assert constraint boundedRecord {
            sequence >= 0 and sequence <= (900719925 * 10000000 + 4740991) and
            i3 >= 0 and i3 <= 7 and
            start_frame >= 0 and start_frame <= (900719925 * 10000000 + 4740991)
        }
        doc /* One decoded frame, with exactly these keys; a_priori is present only for an
             a-priori word. payload77 is the exact 77 payload bits as 0 and 1 characters,
             also for an unsupported or invalid payload. n3 is null unless i3 is 0. text
             (at most 80 ASCII characters) and fields are present only when the status is
             decoded, otherwise null. frequency_hz lies within DecodeBand; snr_db is null or
             as WstxModemDecode::MeasureFrame states it; start_frame indexes the canonical
             12 kHz stream. */
    }
}

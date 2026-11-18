package WstxModeProcessing {
    private import ScalarValues::*;
    private import ModelNotes::FollowsSource;

    doc /* What crosses between the modes part and the two functions that use it: receive
         gives windows of samples and gets the decoded frames, transmit gives a message
         and gets its waveform. It also holds the facts of each mode that several parts
         read: the mode, its period and the band in which frames are decoded. */

    enum def Mode {
        doc /* The modes the station decodes and sends. */
        enum ft4;
        enum ft8;
    }

    attribute def Period {
        doc /* The period of each mode.
             A period starts where UTC is a whole multiple of the period length.
             A period is even when its start divided by the period length is even, and
             odd otherwise (PeriodParity).
             A station that sends on time starts its frame the nominal start after the
             period start; the DT of a decoded frame is its start against that instant. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: mainwindow.cpp, m_TRperiod and "
                + "the Tx period choice";
        }
        attribute ft8PeriodMs : Integer = 15000;
        attribute ft4PeriodMs : Integer = 7500;
        attribute ft8NominalStartMs : Integer = 500;
        attribute ft4NominalStartMs : Integer = 452 {
            doc /* Counted to the ramp symbol that leads an FT4 frame. */ }
        attribute ft8FrameMs : Integer = 12640 {
            doc /* The length of an FT8 frame. */ }
        attribute ft4FrameMs : Integer = 5040 {
            doc /* The length of an FT4 frame with its two ramp symbols. */ }
    }
    enum def PeriodParity {
        enum even;
        enum odd;
    }

    attribute def DecodeBand {
        doc /* The audio band of the lowest tone of a decoded frame, both ends included. */
        attribute decodeBandLowHz : Integer = 200;
        attribute decodeBandHighHz : Integer = 3500;
    }

    port def ReceiveProcessing {
        doc /* Written from receive's side; the modes part uses the conjugate.
             One request runs at a time.
             The frames of a request come back one by one while it runs, and its
             WindowEnd follows the last of them. */
        out item request : ProcessingRequest;
        out item cancel : Cancel;
        out item calls : CallsUpdate;
        in item result : ProcessingResult;
        in item ended : WindowEnd;
    }
    interface def ReceiveProcessingLink {
        doc /* Windows of samples to decode, and the decoded frames back. */
        end receive : ReceiveProcessing;
        end modes : ~ReceiveProcessing;
    }

    item def ProcessingRequest {
        doc /* One window to decode. */
        attribute mode : Mode;
        attribute samples : Real[0..360000] {
            doc /* The window: mono samples at 12 kHz, each a finite number. Its longest
                 length is 30 s. */ }
        attribute originFrame : Integer {
            doc /* The place of the window's first sample in the 12 kHz stream it is
                 taken from. */ }
        attribute periodStartFrame : Integer[0..1] {
            doc /* The place of one period start in that stream, by which the decoder
                 tells the periods of the window apart. Absent while the stream is not
                 tied to station time. */ }
        attribute continuous : Boolean {
            doc /* True for a window of continuous receive, whose windows overlap and
                 follow each other in the stream; false for a window of a recording. */ }
        attribute context : APrioriContext;
    }
    item def Cancel {
        doc /* Receive withdraws the request that runs. It carries nothing, because one
             request runs at a time. */
    }

    enum def QsoProgress {
        doc /* How far the station's contact is, as the message the station sends next. */
        @FollowsSource { reference = "WSJT-X at the behaviour baseline: nQSOProgress"; }
        enum calling;
        enum replying;
        enum report;
        enum rogerReport;
        enum rogers;
        enum signoff;
    }
    attribute def StationCalls {
        doc /* The two calls the modes part needs from the station. */
        attribute myCall : String[0..1] {
            doc /* The profile's callsign. Absent while the profile has none. */ }
        attribute dxCall : String[0..1] {
            doc /* The call of the station the current contact is with. Absent without a
                 contact. */ }
    }
    attribute def APrioriContext {
        doc /* What the station knows before a window is decoded. It is fixed for the
             whole window. */
        attribute calls : StationCalls;
        attribute qsoProgress : QsoProgress;
        attribute rxHz : Real { doc /* The contact's receive audio frequency. */ }
        attribute txHz : Real { doc /* The contact's transmit audio frequency. */ }
        attribute cqOnly : Boolean {
            doc /* True while the station has not transmitted for some time; only a CQ
                 is then expected. */ }
    }
    item def CallsUpdate {
        doc /* The station's calls, for the hashed calls of decoded frames. Receive gives
             it at station start and whenever one of the two calls changes. */
        attribute calls : StationCalls;
    }

    enum def DecodeError {
        doc /* Why a window ended before all of it was searched.
             cancelled: receive withdrew the request.
             invalidSamples: a sample is not a finite number, or a window of continuous
             receive starts before the one before it.
             searchLimited: the window holds more candidates than the decoder searches.
             decodeLimit: the window is longer than 30 s, or a frame exceeds the limits
             of what one request may return. */
        enum cancelled;
        enum invalidSamples;
        enum searchLimited;
        enum decodeLimit;
    }
    item def WindowEnd {
        doc /* The end of a request. The frames returned before it stay valid. */
        attribute error : DecodeError[0..1] {
            doc /* Absent when the whole window was searched. */ }
    }

    enum def FrameStatus {
        doc /* decoded: a payload of a supported family with valid content.
             unsupported: a CRC-valid payload of a family the product does not unpack.
             invalidPayload: a CRC-valid payload of a supported family whose content is
             outside its domain. */
        enum decoded;
        enum unsupported;
        enum invalidPayload;
    }
    enum def CallKind {
        enum call;
        enum token;
        enum hash;
    }
    enum def ExchangeKind {
        enum blank;
        enum grid;
        enum report;
        enum roger;
        enum 'state';
        enum serial;
    }

    attribute def CallValue {
        doc /* A call or a token (CQ, DE, QRZ, a CQ modifier) has its text and no hash
             fields; a call is 1 to 13 upper-case characters, 11 at most in a nonstandard
             message. A hash has its width (10, 12 or 22 bits) and its value; its text is
             the call the station has learned for it, without brackets, and absent
             until then. */
        attribute kind : CallKind;
        attribute text : String[0..1];
        attribute hashBits : Integer[0..1];
        attribute hashValue : Integer[0..1];
    }
    attribute def Exchange {
        doc /* What a message exchanges: blank nothing, grid a 4-character grid, report an
             integer from -50 to 50, roger RRR, RR73 or 73, state a state or province,
             serial a serial number. */
        attribute kind : ExchangeKind;
        attribute textValue : String[0..1];
        attribute numericValue : Integer[0..1];
    }
    attribute def PayloadFields {
        doc /* The fields of a decoded payload: one variant per message family, each with
             all its fields and no others. */
    }
    attribute def FreeTextFields :> PayloadFields {
        doc /* Family 0.0: 1 to 13 characters, trailing padding trimmed. A text of blanks
             only is invalid. */
        attribute 'type' : String = "free_text";
        attribute value : String;
    }
    attribute def TelemetryFields :> PayloadFields {
        doc /* Family 0.5: 18 upper-case hexadecimal digits, the first 0 to 7. */
        attribute 'type' : String = "telemetry";
        attribute value : String;
    }
    attribute def StandardFields :> PayloadFields {
        doc /* Families 1 (with /R) and 2 (with /P). The exchange is blank, grid, report
             or roger. */
        attribute 'type' : String = "standard";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute exchange : Exchange;
    }
    attribute def RttyFields :> PayloadFields {
        doc /* Family 3. The exchange is a serial from 0 to 7999, or a state or
             province. */
        attribute 'type' : String = "rtty";
        attribute tu : Boolean;
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute report : Integer;
        attribute exchange : Exchange;
    }
    attribute def DxpeditionFields :> PayloadFields {
        doc /* Family 0.1. */
        attribute 'type' : String = "dxpedition";
        attribute 'first' : CallValue;
        attribute 'second' : CallValue;
        attribute hashed : CallValue;
        attribute report : Integer;
    }
    attribute def FieldDayFields :> PayloadFields {
        doc /* Families 0.3 (1 to 16 transmitters) and 0.4 (17 to 32). */
        attribute 'type' : String = "field_day";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute transmitters : Integer;
        attribute 'class' : String;
        attribute section : String;
    }
    attribute def NonstandardFields :> PayloadFields {
        doc /* Family 4. A nonstandard CQ shows no hash and keeps its bits. */
        attribute 'type' : String = "nonstandard";
        attribute fullCall : CallValue;
        attribute hashedCall : CallValue;
        attribute hashSecond : Boolean;
        attribute cq : Boolean;
        attribute roger : String[0..1];
    }
    attribute def VhfFields :> PayloadFields {
        doc /* Family 5, the EU VHF contest message. */
        attribute 'type' : String = "vhf";
        attribute 'to' : CallValue;
        attribute 'from' : CallValue;
        attribute ack : Boolean;
        attribute report : Integer;
        attribute serial : Integer;
        attribute grid : String;
    }

    item def ProcessingResult {
        doc /* One decoded frame. */
        attribute status : FrameStatus;
        attribute payload77 : String {
            doc /* The 77 payload bits as the characters 0 and 1, also for an unsupported
                 or invalid payload. */ }
        attribute i3 : Integer;
        attribute n3 : Integer[0..1] { doc /* Present only when i3 is 0. */ }
        attribute text : String[0..1] {
            doc /* The message as text, at most 80 ASCII characters. Present only when
                 the status is decoded. */ }
        attribute fields : PayloadFields[0..1] {
            doc /* Present only when the status is decoded. */ }
        attribute startFrame : Integer {
            doc /* The place in the 12 kHz stream of the frame's first symbol, the ramp
                 symbol for FT4. */ }
        attribute frequencyHz : Real {
            doc /* The audio frequency of the frame's lowest tone, within DecodeBand. */ }
        attribute snrDb : Real[0..1] {
            doc /* The signal-to-noise ratio in a whole number of dB on the 2500 Hz scale
                 of WSJT-X. Absent for a frame that is not wholly inside the window, and
                 without a noise baseline. */ }
        attribute aPriori : Integer[0..1] {
            doc /* The a-priori type, 1 to 6, of a frame that was decoded with the help
                 of the context. Absent for a frame decoded without it. */ }
        assert constraint bounded {
            i3 >= 0 and i3 <= 7 and
            startFrame >= 0 and startFrame <= (900719925 * 10000000 + 4740991)
        }
    }

    port def EncodeProcessing {
        doc /* Written from transmit's side; the modes part uses the conjugate.
             Every request is answered at once by its waveform or by its refusal. */
        out item request : EncodeRequest;
        out item accepted : AcceptedMessage;
        in item waveform : Waveform;
        in item refusal : EncodeRefusal;
    }
    interface def EncodeProcessingLink {
        doc /* A message to encode, and its waveform back. */
        end transmit : EncodeProcessing;
        end modes : ~EncodeProcessing;
    }

    port def PackProcessing {
        doc /* Written from qso's side; the modes part uses the conjugate. Every request is
             answered at once. */
        out item request : PackRequest;
        in item answer : PackAnswer;
    }
    interface def PackProcessingLink {
        doc /* Whether a text can be sent, and as which message: from qso to modes. */
        end qso : PackProcessing;
        end modes : ~PackProcessing;
    }
    item def PackRequest {
        doc /* A text qso would send. */
        attribute text : String;
    }
    item def PackAnswer {
        doc /* What WstxMessageEncode::PackMessage gives for the text: the packed message
             or the refusal, exactly one of the two. */
        attribute packed : PackedMessage[0..1];
        attribute refusal : EncodeRefusalReason[0..1];
    }

    enum def SampleRate {
        enum hz12000;
        enum hz48000;
    }
    item def EncodeRequest {
        doc /* One message to turn into audio. */
        attribute text : String;
        attribute mode : Mode;
        attribute toneZeroHz : Real {
            doc /* The audio frequency of the lowest tone. */ }
        attribute rate : SampleRate;
    }
    enum def MessageFamily {
        doc /* The message families the station sends. */
        enum 'standard';
        enum portable;
        enum nonstandard;
        enum freeText;
        enum telemetry;
        enum fieldDay;
        enum rttyRoundup;
        enum euVhf;
    }
    attribute def PackedMessage {
        doc /* A message as it goes on the air. */
        attribute normalizedText : String {
            doc /* The message as a receiver shows it. */ }
        attribute payload77 : String;
        attribute i3 : Integer;
        attribute n3 : Integer[0..1] { doc /* Present only when i3 is 0. */ }
        attribute family : MessageFamily;
    }
    item def Waveform {
        doc /* The audio of one message. */
        attribute packed : PackedMessage;
        attribute samples : Real[1..*] {
            doc /* Mono samples at the requested rate, with a peak of 1, from the first
                 sample of the frame to its last. */ }
    }
    enum def EncodeRefusalReason {
        doc /* Why a message is not encoded.
             empty: nothing is left of the text after it is normalized.
             tooLong: the message has more than 37 characters, or a free text more than
             13.
             invalidText: a character that no supported family can carry.
             unsupportedFamily: a message of a family the station does not send.
             notExact: a receiver would show the message differently from the text.
             roundTripMismatch: the packed bits do not unpack to the normalized text.
             frequencyOutOfRange: the tones would leave the audio band of the mode. */
        enum 'empty';
        enum tooLong;
        enum invalidText;
        enum unsupportedFamily;
        enum notExact;
        enum roundTripMismatch;
        enum frequencyOutOfRange;
    }
    item def EncodeRefusal {
        attribute reason : EncodeRefusalReason;
    }
    item def AcceptedMessage {
        doc /* A message that transmit has accepted for sending, as its normalized text.
             The modes part learns the calls it names. */
        attribute text : String;
    }
}

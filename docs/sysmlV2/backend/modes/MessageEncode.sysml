package WstxMessageEncode {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-005';
    private import ModelBindings::ImplementationState;
    private import ModelBindings::AutomationState;
    private import ModelBindings::Status;
    private import ModelBindings::Automation;
    private import ModelBindings::ImplementedIn;
    private import ModelBindings::TestedBy;
    private import ModelBindings::TestLevel;
    private import ModelBindings::TestLocation;
    private import ModelNotes::FollowsSource;
    private import ModelNotes::DiffersFromSource;
    private import WstxModesPart::ModeFunctions;
    private import WstxModeProcessing::*;

    doc /* The encode function of the modes part: a message goes in, its audio comes out.
         The packing, the channel code and the waveform are those of WSJT-X; this file
         states the product's choices over them. */

    // ---- From text to bits ----------------------------------------------------------------

    action def PackMessage {
        in text : String;
        out packed : PackedMessage[0..1];
        out refusal : EncodeRefusalReason[0..1];
        doc /* How a text becomes the 77 bits of a message. Exactly one of the two
             results is given.
             The text is normalized: letters to upper case, runs of blanks to one blank,
             no blank at either end.
             The family is chosen in the order in which WSJT-X chooses it.
             The packed bits are unpacked again by the payload function of the modes
             part; the message is packed only when that gives the normalized text.
             A text that WSJT-X would send in an altered form is refused with notExact:
             a telemetry word of fewer than 18 hexadecimal digits, and a Field Day or
             RTTY Roundup message with a call that is not a standard call.
             A DXpedition message and a WSPR message are refused with
             unsupportedFamily.
             A text that fits no family is sent as free text when it has at most 13
             characters of the free-text alphabet, and is refused otherwise. */
        @ImplementedIn { module = "server/src/transmit/pack.rs"; }
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: packjt77, pack77 and its "
                + "grammar";
        }
        @DiffersFromSource {
            what = "WSJT-X cuts a text that fits no family down to 13 characters of free "
                + "text; the encoder refuses it.";
        }
    }

    // ---- FT8 --------------------------------------------------------------------------------

    requirement 'CL-009-01' {
        subject modes : ModeFunctions;
        doc /* The encoder MUST turn a message of every supported family into the FT8
             audio that WSJT-X sends for it, and refuse a message that it cannot send
             unaltered (PackMessage, Ft8WaveformContract). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-005'; end #derive ::> 'CL-009-01'; }

    attribute def Ft8WaveformContract {
        doc /* The FT8 audio of one message.
             The channel code, the tones and the waveform are those of the source.
             The waveform holds the symbols and nothing before or after them.
             With the lowest tone from minTone0Hz to maxTone0Hz all tones lie within
             200 Hz to 3000 Hz; a lowest tone outside is refused with
             frequencyOutOfRange. */
        @ImplementedIn {
            module = "server/src/modes/transmit/mod.rs; "
                + "server/src/modes/transmit/waveform.rs";
        }
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: genft8, gen_ft8wave, and the "
                + "printouts of ft8code and ft8sim";
        }
        attribute minTone0Hz : Real = 200.0;
        attribute maxTone0Hz : Real = 2950.0;
    }

    // ---- FT4 --------------------------------------------------------------------------------

    requirement 'CL-011-01' {
        subject modes : ModeFunctions;
        doc /* The encoder MUST turn a message of every supported family into the FT4
             audio that WSJT-X sends for it, with the packing and the refusals of FT8
             (PackMessage, Ft4WaveformContract). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-005'; end #derive ::> 'CL-011-01'; }

    attribute def Ft4WaveformContract {
        doc /* The FT4 audio of one message.
             The channel code, the tones and the waveform are those of the source.
             The waveform holds one ramp symbol, the tones and one ramp symbol, and
             nothing before or after them.
             With the lowest tone from minTone0Hz to maxTone0Hz all tones lie within
             200 Hz to 3000 Hz; a lowest tone outside is refused with
             frequencyOutOfRange. */
        @ImplementedIn {
            module = "server/src/modes/transmit/mod.rs; "
                + "server/src/modes/transmit/waveform.rs";
        }
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: genft4, gen_ft4wave as the "
                + "transmitter calls it, and the printout of ft4sim";
        }
        attribute minTone0Hz : Real = 200.0;
        attribute maxTone0Hz : Real = 2916.666667;
    }

    // ---- Test cases -------------------------------------------------------------------------

    verification 'TC-005-001' {
        doc /* A message as FT8 audio.
             Setup: the encoder alone; the bits and tones that ft8code of WSJT-X prints
             for a set of messages of every supported family and of every kind of
             refusal, and two noise-free recordings made by ft8sim.
             (a) For every message of the set that WSJT-X sends unaltered, the 77 bits,
             the CRC, the parity and the 79 tones equal those of ft8code.
             (b) "" is refused as empty, "HELLO WORLD 123" as tooLong,
             "TNX BOB 73 GL!" as invalidText and "CAFE" as notExact.
             (c) The waveform at 12 kHz has 151680 samples and lies within 0.003 of the
             recording; shifted by one sample, and 0.01 Hz off, it does not.
             (d) The waveform at 48 kHz has 606720 samples, and every fourth of them
             lies within 0.006 of the waveform at 12 kHz.
             (e) A lowest tone of 200 Hz and of 2950 Hz is accepted; 199.99 Hz and
             2950.01 Hz are refused as frequencyOutOfRange.
             (f) The decoder returns the message of a waveform that the encoder made. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-009-01'; }
        @TestedBy { test = "server/tests/transmit_vectors.rs"; }
    }

    verification 'TC-005-002' {
        doc /* A message as FT4 audio.
             Setup: the encoder alone; the bits and tones that ft4sim of WSJT-X prints
             for the message set of the FT8 case and one FT4 exchange, and two
             noise-free recordings made by ft4sim.
             (a) For every message of the set that WSJT-X sends unaltered, the 77 bits,
             the code word and the 103 tones equal those of ft4sim; every other message
             is refused.
             (b) The waveform at 12 kHz has 60480 samples and lies within 0.001 of the
             recording; shifted by one sample, 0.01 Hz off, and with a ramp one sample
             late, it does not.
             (c) The waveform at 48 kHz has 241920 samples, and every fourth of them
             lies within 0.025 of the waveform at 12 kHz.
             (d) A lowest tone of 200 Hz and of 2916 Hz is accepted; 199.99 Hz and
             2916.68 Hz are refused as frequencyOutOfRange.
             (e) The decoder returns the message of a waveform that the encoder made. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-011-01'; }
        @TestedBy { test = "server/tests/transmit_ft4_vectors.rs"; }
    }
}

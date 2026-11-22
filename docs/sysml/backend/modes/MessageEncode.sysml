package WstxMessageEncode {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-005';
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;
    private import WstxModelNotes::FollowsSource;
    private import WstxModelNotes::DiffersFromSource;
    private import WstxModesPart::ModeFunctions;
    private import WstxModeProcessing::*;

    doc /* The encode function of the modes part: a message goes in, its audio comes out.
         The packing, the channel code and the waveform are those of WSJT-X; this file
         states the product's choices over them. */

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
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: packjt77, pack77 and its "
                + "grammar";
        }
        @DiffersFromSource {
            what = "WSJT-X cuts a text that fits no family down to 13 characters of free "
                + "text; the encoder refuses it.";
        }
    }

    requirement 'CL-009-01' {
        subject modes : ModeFunctions;
        doc /* The encoder MUST turn a message of every supported family into the FT8
             audio that WSJT-X sends for it, and refuse a message that it cannot send
             unaltered (PackMessage, Ft8WaveformContract). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/modes/transmit/pack.rs; server/src/modes/transmit/mod.rs; "
                + "server/src/modes/transmit/waveform.rs";
        }
    }
    #derivation connection { end #original ::> 'FR-005'; end #derive ::> 'CL-009-01'; }

    attribute def Ft8WaveformContract {
        doc /* The FT8 audio of one message.
             The channel code, the tones and the waveform are those of the source.
             The waveform holds the symbols and nothing before or after them.
             With the lowest tone from minTone0Hz to maxTone0Hz all tones lie within
             200 Hz to 3000 Hz; a lowest tone outside is refused with
             frequencyOutOfRange. */
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: genft8, gen_ft8wave, and the "
                + "printouts of ft8code and ft8sim";
        }
        attribute minTone0Hz : Real = 200.0;
        attribute maxTone0Hz : Real = 2950.0;
    }

    requirement 'CL-011-01' {
        subject modes : ModeFunctions;
        doc /* The encoder MUST turn a message of every supported family into the FT4
             audio that WSJT-X sends for it, with the packing and the refusals of FT8
             (PackMessage, Ft4WaveformContract). */
        @Status { build = ImplementationState::implemented; }
        @ImplementedIn {
            module = "server/src/modes/transmit/pack.rs; server/src/modes/transmit/mod.rs; "
                + "server/src/modes/transmit/waveform.rs";
        }
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
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: genft4, gen_ft4wave as the "
                + "transmitter calls it, and the printout of ft4sim";
        }
        attribute minTone0Hz : Real = 200.0;
        attribute maxTone0Hz : Real = 2916.666667;
    }

    verification 'TC-005-001' {
        doc /* A message as FT8 audio. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-009-01'; }
        @TestedBy { test = "server/tests/transmit_vectors.rs"; }
    }

    verification 'TC-005-002' {
        doc /* A message as FT4 audio. */
        subject modes : ModeFunctions;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-011-01'; }
        @TestedBy { test = "server/tests/transmit_ft4_vectors.rs"; }
    }
}

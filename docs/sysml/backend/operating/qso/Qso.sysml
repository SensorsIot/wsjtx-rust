package WstxQsoPart {
    private import ScalarValues::*;
    private import WstxQsoControl::QsoControlPort;
    private import WstxStationTime::StationTimePort;
    private import WstxStrategies::ActivitySharePort;
    private import WstxDecodes::DecodesPort;
    private import WstxDisplayData::DisplayDataPort;
    private import WstxOperatingChain::TargetChoicePort;
    private import WstxOperatingChain::MessageToSendPort;
    private import WstxOperatingChain::CompletedContactPort;
    private import WstxHearing::TargetHearingPort;
    private import WstxModeProcessing::PackProcessing;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelBindings::DetailTests;
    private import WstxModelNotes::CodeDiffers;

    part def QsoService {
        doc /* Level 3 of the operating chain: the contact, made by hand or started by Auto,
             and where it transmits. */
        @ImplementedIn {
            module = "server/src/contact.rs; server/src/contact_http.rs; "
                + "server/src/operating/qso/freeslot.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/contact.rs, server/src/contact_http.rs, outside "
                + "server/src/operating/qso/ and client/src/operating/qso/.";
        }
        @DetailTests {
            tests = "server/src/contact_tests.rs; server/src/operating/qso/freeslot_tests.rs; "
                + "server/src/mcp_tests.rs";
            covers = "the contact engine, the quiet-space function and the waterfall's periods; "
                + "Auto Seq and Call 1st saved in their own file, also through the MCP tool";
        }
        port operations : ~QsoControlPort;
        port time : ~StationTimePort;
        port activity : ~ActivitySharePort;
        port target : ~TargetChoicePort;
        port transmit : MessageToSendPort;
        port completed : CompletedContactPort;
        port decodes : ~DecodesPort {
            doc /* The decoded frames: the partner's messages and the stations decoded in a
                 period. */
        }
        port display : ~DisplayDataPort {
            doc /* The detailed spectrum rows, whose levels the quiet space judges. */
        }
        port hearing : ~TargetHearingPort {
            doc /* What the partner hears: the frequencies he decodes, for the quiet space. */
        }
        port pack : PackProcessing {
            doc /* Whether a text can be sent unaltered, and its family: every message a
                 contact would send is asked before it is set. */
        }
    }
}

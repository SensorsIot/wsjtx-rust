package WstxModesPart {
    private import ScalarValues::*;
    private import WstxModeProcessing::EncodeProcessing;
    private import WstxModeProcessing::ReceiveProcessing;
    part def ModeFunctions {
        attribute currentReceiveSettings : WstxModeProcessing::Settings[0..1];
        attribute intendedModeCapabilities : WstxRequirements::ModeCapability[*];
        doc /* Pure protocol/symbol/waveform and decoding calculations with independent vectors; no filesystem/hardware/network/wall-clock dependency. */
        doc /* Pure receive calculations and encoding/waveform generation depend on no
             device, filesystem, wall-clock or network. WstxModemDecode and
             WstxOfflineDecode own concrete mode contracts and status; hardware format
             adaptation and common rate conversion remain outside this boundary. */
        port receive : ~ReceiveProcessing;
        port encode : ~EncodeProcessing;
    }
}

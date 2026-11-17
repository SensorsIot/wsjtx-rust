package WstxModesPart {
    private import ScalarValues::*;
    private import WstxModeProcessing::ReceiveProcessing;
    private import WstxModeProcessing::EncodeProcessing;
    private import WstxModeProcessing::PackProcessing;

    part def ModeFunctions {
        doc /* The FT8 and FT4 protocol functions of the station. It decodes the frames in
             a window of samples, turns each payload into a message with its fields, and
             turns a message into its waveform. */
        port receive : ~ReceiveProcessing;
        port encode : ~EncodeProcessing;
        port pack : ~PackProcessing {
            doc /* qso's texts, answered by PackMessage. */
        }
    }
}

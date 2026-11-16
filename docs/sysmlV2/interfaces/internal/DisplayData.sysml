package WstxDisplayData {
    private import ScalarValues::*;
    private import WstxDecodes::JobIdentity;

    doc /* The spectrum rows receive makes from the samples of its job: a thin row for
         each second and a detailed row for each fifth of a second. A row is for
         display; a consumer may leave rows out. */

    item def SpectrumFrame {
        doc /* The thin row: 128 levels over 0 to 3000 Hz for one second of samples. */
        attribute identity : JobIdentity;
        attribute sequence : Integer;
        attribute first_frame : Integer { doc /* The first sample of the row. */ }
        attribute end_frame : Integer {
            doc /* The sample after the last one of the row. A row is shorter than a
                 second only at the end of a recording. */ }
        attribute levels : Integer[128] {
            doc /* Each from 0 to 120: the level in dB above -120 dBFS. */ }
        attribute tx : Boolean {
            doc /* True for a row of a period the station transmitted in. */ }
        assert constraint interval {
            sequence >= 0 and first_frame == 12000 * sequence and end_frame > first_frame
            and end_frame <= first_frame + 12000
        }
    }
    item def DetailedSpectrumFrame {
        doc /* The detailed row: 1024 levels over 0 to 3000 Hz for 0.2 s of samples. */
        attribute identity : JobIdentity;
        attribute sequence : Integer;
        attribute first_frame : Integer;
        attribute end_frame : Integer {
            doc /* As in SpectrumFrame; a row is shorter than 0.2 s only at the end of a
                 recording. */ }
        attribute levels : Integer[1024] { doc /* As in SpectrumFrame. */ }
        attribute tx : Boolean { doc /* As in SpectrumFrame. */ }
        assert constraint interval {
            sequence >= 0 and first_frame == 2400 * sequence and end_frame > first_frame
            and end_frame <= first_frame + 2400
        }
    }

    port def DisplayDataPort {
        doc /* Written from receive's side. */
        out item spectrum : SpectrumFrame;
        out item detailedSpectrum : DetailedSpectrumFrame;
    }
    interface def DisplayData {
        doc /* The spectrum rows from receive to a consumer. */
        end receive : DisplayDataPort;
        end consumer : ~DisplayDataPort;
    }
}

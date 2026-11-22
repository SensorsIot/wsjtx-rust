package WstxSpectrum {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-003';
    private import WstxReceivePart::ReceiveService;
    private import WstxDisplayData::SpectrumFrame;
    private import WstxDisplayData::DetailedSpectrumFrame;
    private import WstxReceiveControl::ReceiveKind;
    private import WstxModelBindings::ImplementationState;
    private import WstxModelBindings::AutomationState;
    private import WstxModelBindings::Status;
    private import WstxModelBindings::Automation;
    private import WstxModelBindings::TestedBy;
    private import WstxModelBindings::TestLevel;
    private import WstxModelBindings::TestLocation;

    requirement 'CL-006-03' {
        subject receive : ReceiveService;
        doc /* Receive MUST make of the samples of its job a thin spectrum row for each
             second and a detailed row for each fifth of a second, both by the stated
             transform (ThinSpectrum, DetailedSpectrum, ReplayPacing). */
        @Status { build = ImplementationState::implemented; }
    }
    #derivation connection { end #original ::> 'FR-003'; end #derive ::> 'CL-006-03'; }

    attribute def ThinSpectrum {
        doc /* How a SpectrumFrame is made.
             Windows of size samples are taken every hop samples, the first at the
             first sample of the recording or, on the receive stream, at the first
             whole second of the epoch; a window that reaches beyond the end of a
             recording is filled with zeros.
             A window is weighted with the periodic Hann window and transformed; the
             amplitude of bin k is twice the magnitude of the transform divided by the
             sum of the window's weights, and for bin 0 once that.
             The lowest 512 bins, 0 to 3000 Hz, are kept in 128 groups of 4
             neighbouring bins; the value of a group is the largest amplitude in it.
             A row holds, for each group, the largest value among the windows that
             start within the second of the row.
             The level of a value is 20 log10 of it in dB, limited to -120 to 0, plus
             120, rounded to the nearest whole number.
             A break in the receive stream starts the windows anew at the first whole
             second after it. */
        attribute size : Integer = 2048;
        attribute hop : Integer = 256;
    }

    attribute def DetailedSpectrum {
        doc /* How a DetailedSpectrumFrame is made.
             Windows of detailSize samples are taken every detailHop samples and
             weighted, transformed and scaled as in ThinSpectrum.
             The lowest 1024 bins, 0 to 3000 Hz, are kept, each a value of its own.
             A row holds, for each bin, the root of the mean of the squared amplitudes
             of the windows that start within the rowFrames samples of the row.
             The level of a value is formed as in ThinSpectrum.
             A break in the receive stream starts the windows anew at the first
             multiple of rowFrames after it. */
        attribute detailSize : Integer = 4096;
        attribute detailHop : Integer = 480;
        attribute rowFrames : Integer = 2400;
    }

    attribute def ReplayPacing {
        doc /* When the rows of a job are published.
             A live job publishes a row when the stream has brought every sample of
             the last window that starts in it.
             A replay (ReceiveKind::spectrum) publishes its rows in the time of the
             recording: a detailed row not before the time of its last sample has
             passed since the start of the job, and a thin row with the detailed row
             that ends its second or the recording.
             The last rows of a replay end with the recording and are shorter. */
    }

    verification 'TC-010-001' {
        doc /* The thin spectrum against a transform computed apart. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-006-03'; }
        @TestedBy {
            test = "server/src/receive/spectrum_rows_tests.rs::"
                + "both_fft_paths_agree_with_direct_dft_and_analytic_dbfs; "
                + "server/src/receive/spectrum_rows_tests.rs::"
                + "replay_window_start_and_partial_last_row_follow_source_clock";
        }
    }

    verification 'TC-010-004' {
        doc /* The detailed spectrum against a transform computed apart. */
        subject receive : ReceiveService;
        @TestLevel { cost = 2; location = TestLocation::developmentPc; }
        @Automation { run = AutomationState::implemented; }
        objective { verify 'CL-006-03'; }
        @TestedBy {
            test = "server/src/receive/spectrum_rows_tests.rs::"
                + "detailed_native_bins_and_power_rows_follow_independent_dft";
        }
    }
}

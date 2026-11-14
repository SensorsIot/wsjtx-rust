package WstxClockPart {
    private import ScalarValues::*;
    private import WstxPeriodTiming::ClockStatusPort;
    private import WstxPeriodTiming::PeriodTimingPort;
    private import WstxDecodes::DecodesPort;
    private import WstxTimeSource::TimeSourcePort;
    part def ClockService {
        doc /* Station time: the corrected UTC and the period boundaries the other functions
             keep time by, and the clock's quality. */
        port status : ClockStatusPort;
        port timing : PeriodTimingPort;
        port decodes : ~DecodesPort;
        port timeSource : TimeSourcePort;
    }
}

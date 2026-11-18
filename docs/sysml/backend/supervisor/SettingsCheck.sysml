package WstxSettingsCheck {
    private import ScalarValues::*;
    private import RequirementDerivation::*;
    private import WstxRequirements::'FR-001';
    private import WstxSupervisorPart::Supervisor;
    private import WstxStationCommands::CheckSettings;
    private import WstxStationCommands::CheckLine;
    private import WstxStationCommands::SettingsCheckReport;
    private import WstxStationCommands::CheckRefused;
    private import WstxStationCommands::WorkingFrequencies;
    private import WstxProfileAccess::ShackConfig;
    private import WstxRadioControl::RadioStatus;
    private import WstxRadioControl::PowerStatus;
    private import WstxRadioControl::AgcStatus;
    private import WstxRadioControl::RadioAbility;
    private import WstxAudioControl::AudioStatus;
    private import WstxStationTime::ClockQuality;
    private import WstxTransmitControl::TxLevelStatus;
    private import WstxLogControl::CountryFileState;
    private import WstxHearing::FeedStatus;
    private import ModelBindings::ImplementationState;
    private import ModelBindings::Status;

    doc /* The settings check: the one walk through the station's settings that tells
         whether the station is ready to operate. */

    requirement 'CL-001-01' {
        subject supervisor : Supervisor;
        doc /* The supervisor MUST check the station's settings on CheckSettings as
             CheckRule says. */
        @Status { build = ImplementationState::target; }
    }
    #derivation connection { end #original ::> 'FR-001'; end #derive ::> 'CL-001-01'; }

    attribute def CheckRule {
        doc /* A CheckSettings passes the checks of WstxStationAuthority::GateRule and is
             refused with CheckRefused busy while a contact is in progress, the
             transmitter is not at rest, a selection is pending or a check runs.
             The check changes no setting. It makes one CheckLine for each check, in the
             order of the areas of CheckArea, and gives SettingsCheckReport after each
             line and at its end.
             station: the shack's callsign and locator are set (ShackConfig) and the
             station has a continent.
             radio: with a radio over CAT, the connection is ready (RadioStatus) and its
             frequency, mode and data mode are confirmed; with PTT over CAT, the rig has
             RadioAbility::keyOverCat; with split rig, the rig has RadioAbility::split; the
             AGC was written or found unchanged (AgcStatus); on a native profile, the
             session is ready; without a radio, skipped.
             power: the output power of the station's band was written or found
             unchanged (PowerStatus); without an entry for the band, or without
             RadioAbility::setPower, skipped. With CheckSettings::withTune, a Tune tone
             then finds the audio drive, and the line passes when the finding ends with
             stored or maxWithoutAlc and no swrHigh or swrFault (TxLevelStatus);
             the tone ends with the finding. Without withTune that part is skipped.
             audio: the capture runs without a warning (AudioStatus) and the profile names
             an output device.
             clock: the clock has no warning (ClockQuality).
             operating: the operating mode has a working frequency in the station's region
             (WorkingFrequencies), every Tx macro packs as free text, the
             active strategy lies within the rules of a strategy, a contest in force lies in
             its period, and the Most Wanted list has been read.
             files: the logbook has been read, the country file is in use
             (CountryFileState) and the station's folder takes a line of the heard file.
             destinations: every UDP target has an address that resolves; with the
             switches of PSK Reporter on, its feed is connected (FeedStatus).
             A value the settings take only within its rule, and a choice of the browser,
             need no line.
             A check that needs what an earlier one found missing is skipped with that
             reason. A line that fails or is skipped says why, in the words of operating,
             and where to change it. The report is ready when no line failed. */
    }
}

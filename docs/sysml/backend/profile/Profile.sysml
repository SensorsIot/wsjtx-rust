package WstxProfilePart {
    private import WstxProfileAccess::*;
    private import WstxRecordingTransfer::RecordingTransfer;
    private import WstxRecordingTransfer::RecordedSamples;
    private import WstxClubLog::ClubLogPort;
    private import WstxCountryFiles::CountryFilesPort;
    private import WstxModelBindings::ImplementedIn;
    private import WstxModelNotes::CodeDiffers;

    part def PersistedProfile {
        doc /* The profile of one station: its saved document, its hidden store, its
             folder and the one recording it holds. It is created once, opened when its
             station starts and held by that station process alone, keeps the station
             config and the records of the station's parts across restarts, saves a
             change of them, fetches the Most Wanted list and the country file, takes in a
             recording and gives
             it to receive as samples. What a setting or a record means is defined by
             the part that uses it. */
        @ImplementedIn {
            module = "server/src/profile.rs; server/src/recording_http.rs";
        }
        @CodeDiffers {
            what = "Its code stands in server/src/main.rs, server/src/most_wanted.rs, "
                + "server/src/profile.rs, server/src/radio_control/setup.rs, "
                + "server/src/radio_setup.rs, server/src/recording.rs, "
                + "server/src/recording_http.rs, outside server/src/profile/ and "
                + "client/src/profile/.";
        }
        attribute config : StationConfig {
            doc /* The station config, as the saved document holds it. */ }
        attribute memory : StationMemory {
            doc /* The hidden store, as it is kept. */ }
        port context : ~ProfileAccess {
            doc /* The supervisor. Every item of ProfileAccess crosses here: the
                 supervisor takes the folder, the document and the hidden store,
                 gives each part its configuration and its records, and brings the
                 saves. */
        }
        port upload : ~RecordingTransfer;
        port recordedSamples : RecordedSamples;
        port clubLog : ClubLogPort { doc /* The Club Log service, for the Most Wanted list. */ }
        port countryFiles : CountryFilesPort {
            doc /* country-files.com, for the country file. */ }
    }
}

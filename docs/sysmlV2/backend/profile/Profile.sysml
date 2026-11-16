package WstxProfilePart {
    private import WstxProfileAccess::*;
    private import WstxRecordingTransfer::RecordingTransfer;
    private import WstxRecordingTransfer::RecordedSamples;
    private import ModelBindings::ImplementedIn;

    part def PersistedProfile {
        doc /* The profile of one station: its saved document, its hidden store, its
             folder and the one recording it holds. It is created once, opened when its
             station starts and held by that station process alone, keeps the station
             config and the records of the station's parts across restarts, saves a
             change of them, takes in a recording and gives it to receive as samples.
             It only stores: what a setting or a record means is defined by the part
             that uses it. */
        @ImplementedIn { module = "server/src/profile.rs"; }
        attribute config : StationConfig {
            doc /* The station config, as the saved document holds it. */ }
        attribute memory : StationMemory {
            doc /* The hidden store, as it is kept. */ }
        port context : ~ProfileAccess {
            doc /* The station service. Every item of ProfileAccess crosses here: the
                 station service takes the folder, the document and the hidden store,
                 gives each part its configuration and its records, and brings the
                 saves. */
        }
        port upload : ~RecordingTransfer;
        port recordedSamples : RecordedSamples;
    }
}

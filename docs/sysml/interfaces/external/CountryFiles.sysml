package WstxCountryFiles {
    private import ScalarValues::*;
    private import WstxModelNotes::FollowsSource;

    doc /* The exchange with country-files.com: the station asks for the newest country file
         of AD1C, cty.dat. */

    item def CtyQuery {
        doc /* Ask for the file: one GET for sourceUrl. The station names itself to the
             service as WSTX-Rust with its version. */
        attribute sourceUrl : String = "http://www.country-files.com/bigcty/cty.dat";
        @FollowsSource {
            reference = "WSJT-X at the behaviour baseline: Configuration "
                + "on_CTY_download_button_clicked, the source of Download Latest CTY.dat";
        }
    }
    item def CtyDownload {
        doc /* The answer: the text of the file. Only an answer with the status 200 of at
             most bytesMax bytes is a file. */
        attribute bytesMax : Integer = 1048576;
        attribute text : String;
    }
    port def CountryFilesPort {
        doc /* Written from the profile's side; the service has the conjugate. A CtyQuery
             is answered by one CtyDownload. */
        out item query : CtyQuery;
        in item download : CtyDownload;
    }
    interface def CountryFiles {
        doc /* The profile, the settings function, and country-files.com. */
        end profile : CountryFilesPort;
        end service : ~CountryFilesPort;
    }
}

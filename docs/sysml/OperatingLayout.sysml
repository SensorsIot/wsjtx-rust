// Canonical operating layout SHA256: 8e7a28689eee4ef1e3c764c292b658d85964a6d008bd9723d2bfab71cdd89486
package WstxOperatingLayout {
    private import ScalarValues::*;

    doc /* Implementation contract for the profile-mode read-only operating layout.
         Markdown authority: docs/WSTX Rust FSD.md4.7.1 and6.6 TC007002. Existing signal and
         profile contracts are reused, not redefined. Full QSO/TX/log behavior is
         outside this slice. No modeled verification verdict is asserted. */

    enum def CapabilityState { enum unsupported; enum unavailable; enum available; }
    enum def LinkState { enum connecting; enum connected; enum stale; }
    enum def SecondaryRegion { enum settings; enum recording; }

    attribute def OperatingPresentation {
        attribute profileMode : Boolean;
        attribute link : LinkState;
        attribute serverIdentity : String;
        attribute profileIdentity : String;
        attribute dialFrequencyAvailable : Boolean = false;
        attribute modeAvailable : Boolean = false;
        attribute audio : CapabilityState = CapabilityState::unavailable;
        attribute cat : CapabilityState = CapabilityState::unavailable;
        attribute decoder : CapabilityState = CapabilityState::unsupported;
        attribute transmit : CapabilityState = CapabilityState::unsupported;
        attribute messageRowCount : Integer = 0;
        attribute liveResultInterfaceAvailable : Boolean = false;
        attribute selectedContactRowCount : Integer = 0;
        attribute transmitEnabled : Boolean = false;
        attribute haltEnabled : Boolean = false;
        attribute autoSequenceEnabled : Boolean = false;
        attribute logEnabled : Boolean = false;
        assert constraint readOnlyUnsupportedCapabilities {
            (liveResultInterfaceAvailable or messageRowCount == 0) and
            messageRowCount >= 0 and messageRowCount <= 2048 and
            selectedContactRowCount == 0 and
            not transmitEnabled and not haltEnabled and
            not autoSequenceEnabled and not logEnabled
        }
        doc /* Link transitions follow existing station.status/socket authority.
             A connected link does not imply audio/CAT/decoder/TX availability.
             Unknown frequency/mode are visible unavailable text, never defaults.
             Profile identity uses literal text, never HTML interpretation.
             With liveResultInterfaceAvailable,12.8 explicit Start/Stop and next-job
             spectrum/FT4/FT8 selection use the saved endpoint/current revision.
             Device enumeration requires an operator action; viewing settings or
             choosing a mode never opens audio. Actual12.7 records alone populate
             Band Activity using source seconds, nullable SNR and audio frequency;
             no fabricated UTC/DT, message text or resolved hash. Full source/job/
             generation/sequence binds each row; new identity clears rows, stale
             pages cannot append. At most2048 rows, explicit cursor-expiry history
             warning and partial stop/failure output; unsupported payloads display
             their status. One pending page, Thin limit1/4s and status priority
             follow12.8. RX selection/TX/log remain unsupported. TC009004 exercises
             actual verified native input through converter/manager/modem/HTTP to
             literal browser rows and stale/epoch/stop/cursor/cadence boundaries;
             TC007002 keeps the unsupported/no-input empty-view baseline. */
    }

    attribute def SplitGeometry {
        attribute signalAboveWorkspace : Boolean = true;
        attribute lowerWorkspaceScrollable : Boolean = true;
        attribute horizontalPageOverflow : Boolean = false;
        attribute minimumSignalPixels : Integer = 160;
        attribute minimumWorkspacePixels : Integer = 200;
        doc /* Signal then keyboard/mouse separator then operating workspace, within
             the same page under the station bar. ArrowUp/Down change height16CSSpx;
             Home chooses the minimum, End maximum with workspace retained.
             ARIA min/max/current follow the clamped actual signal height.
             360CSSpx and 200% zoom stack lower panes; text remains reachable.
             Existing 0..3000Hz, palette, 1:5 curve/waterfall and native bin contracts
             are unchanged. Secondary in-page disclosures reuse existing forms,
             preserve login and never obscure the station bar or disabled Halt Tx. */
    }

    verification def operatingLayout002 {
        objective {
            verify WstxRequirements::'CL-010-05';
            verify WstxRequirements::'CL-010-07';
            verify WstxRequirements::'CL-010-08';
        }
        doc /* TC-007-002, CL-010-05/07/08: cost2 local real-server Chromium cases at
             desktop/mobile/200% equivalent viewport. Assert ordering, literal
             identity, empty/unavailable views, disabled actions/no new commands,
             disclosure keyboard access, actual pointer/key split geometry and ARIA,
             no horizontal page overflow, stale link after disconnect. Existing
             TC010005/006/007 independently guard signal semantics. */
    }
}

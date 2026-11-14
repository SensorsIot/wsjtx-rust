package WstxRadioControlPart {
    private import ScalarValues::*;
    private import WstxRadioControl::RadioControl;
    private import WstxKeying::Keying;
    private import WstxCat::CatPort;
    part def RadioBinding {
        doc /* The station's selected radio resource. Persisted intent resolves it at
             connection, and every control request carries it as resource context. The
             radio itself is an outside thing (OutsideThing catRadio, flexRadio).
             WstxFlexSession::NativeFlexWireSubset settles native slice and handle
             reconciliation; actual radio capacity is reported at runtime. */
    }
    part def RadioAuthority {
        doc /* One effective authority for constrained resources and transmit access across
             all station/backend choices. This is not a new process placement decision. */
        port requests : ~RadioControl;
        port authorized : RadioControl;
        binding authorizedContext bind authorized.request = requests.request;
        binding returnedContext bind requests.outcome = authorized.outcome;
    }
    part def RadioControlInterface {
        attribute configuredIntent : WstxRadioControl::ControlSelection;
        attribute observedState : WstxRadioIO::CatState;
        attribute currentFacts : WstxRadioFacts::RadioFacts[0..1];
        attribute frequencyProvenance : WstxRadioFacts::FactProvenance;
        attribute modeProvenance : WstxRadioFacts::FactProvenance;
        attribute dataProvenance : WstxRadioFacts::FactProvenance;
        doc /* Own selected capabilities, typed CAT/control/PTT/status/resource claims; not audio samples/sound devices, browser/MCP policy or duplicate modem logic. */
        doc /* Capabilities, CAT/PTT/status, independent failures and resource claims. No
             samples; control implementation coverage does not limit physical radio capabilities. */
        port station : ~RadioControl;
        port transmit : ~Keying;
        port backend : RadioControl;
    }
    part def RustRadioDriver {
        attribute connectionSettings : WstxRadioControl::ControlSelection;
        attribute observed : WstxRadioControl::RadioObservation[0..1];
        port authorized : ~RadioControl;
        port radio : CatPort;
    }
}

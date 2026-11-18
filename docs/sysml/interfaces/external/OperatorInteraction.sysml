package WstxOperatorInteraction {
    private import ScalarValues::*;

    doc /* The operator and a browser window of the station. */

    port def OperatorInteractionPort {
        doc /* Written from the browser's side; the operator uses the conjugate. */
        out item screen : Screen;
        in item input : OperatorInput;
    }
    item def Screen {
        doc /* What the window shows: the operating screen and its regions
             (WstxOperatingScreen::ScreenLayout), with the sound of an alert and a notification
             of the browser (WstxSettings::AlertDisplay). */
    }
    item def OperatorInput {
        doc /* What the operator does: the pointer, the keys (WstxOperatingScreen::KeyRule)
             and touch. */
    }
    interface def OperatorInteraction {
        doc /* The operator works the station through a browser window. */
        end browserClient : OperatorInteractionPort;
        end operator : ~OperatorInteractionPort;
    }
}

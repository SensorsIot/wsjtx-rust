package WstxOperatorInteraction {
    private import ScalarValues::*;

    port def OperatorInteractionPort;
    item def OperatorInteractionItem { doc /* What the operator and the browser client exchange. */ }
    interface def OperatorInteraction {
        doc /* The operator and the browser client. */
        end browserClient : OperatorInteractionPort;
        end operator : ~OperatorInteractionPort;
        item interaction : OperatorInteractionItem;
    }
}

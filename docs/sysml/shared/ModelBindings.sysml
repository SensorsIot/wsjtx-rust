package WstxModelBindings {
    private import ScalarValues::*;
    enum def ImplementationState {
        doc /* How far a clause is built. */
        enum target;
        enum partial;
        enum implemented;
    }
    enum def AutomationState {
        doc /* How far a test case is automated. */
        enum planned;
        enum partial;
        enum implemented;
    }
    metadata def Status { attribute build : ImplementationState; }
    metadata def Automation { attribute run : AutomationState; attribute method : String[0..1]; }
    metadata def ImplementedIn { attribute module : String; }
    metadata def TestedBy { attribute test : String; }
    metadata def DetailTests { attribute tests : String; attribute covers : String; }
    enum def TestLocation { enum developmentPc; enum station; enum simulator; enum flexRadio; }
    metadata def TestLevel { attribute cost : Integer; attribute location : TestLocation; }
}

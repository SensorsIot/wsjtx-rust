package ModelBindings {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    metadata def Status { attribute build : ImplementationState; }
    metadata def Automation { attribute run : AutomationState; attribute method : String[0..1]; }
    metadata def ImplementedIn { attribute module : String; }
    metadata def TestedBy { attribute test : String; }
    metadata def DetailTests { attribute tests : String; attribute covers : String; }
    enum def TestLocation { enum developmentPc; enum station; enum simulator; enum flexRadio; }
    metadata def TestLevel { attribute cost : Integer; attribute location : TestLocation; }
    metadata def RetiredCase {
        attribute identity : String;
        attribute test : String[0..1];
        attribute supersededBy : String[0..1];
    }
}

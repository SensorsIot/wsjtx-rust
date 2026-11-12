package ModelBindings {
    private import ScalarValues::*;
    private import WstxRequirements::ImplementationState;
    private import WstxRequirements::AutomationState;
    metadata def Status { attribute build : ImplementationState; }
    metadata def Automation { attribute run : AutomationState; attribute method : String[0..1]; }
    metadata def ImplementedIn { attribute module : String; }
    metadata def TestedBy { attribute test : String; }
    metadata def DetailTests { attribute tests : String; attribute covers : String; }
    metadata def RetiredCase { attribute identity : String; attribute test : String; }
}

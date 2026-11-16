/* Shared metadata for a product model: what the model declares as its status, and which
   code and tests belong to an element. A project whose tools read these in another form
   keeps that form and does not include this file. */
package ModelBindings {
    private import ScalarValues::*;

    enum def BuildState { enum built; enum partlyBuilt; enum planned; }
    enum def AutomationState { enum automated; enum manual; enum planned; }

    /* What the model declares about an element. A declaration is not a test result. */
    metadata def Status { attribute build : BuildState; }
    metadata def Automation { attribute run : AutomationState; }

    /* The module that implements a part or a function of a part. */
    metadata def ImplementedIn { attribute module : String; }

    /* The test that shows a promise at the part boundary. */
    metadata def TestedBy { attribute test : String; }

    /* The tests of the inside of a part, as a set. */
    metadata def DetailTests {
        attribute tests : String;
        attribute covers : String;
    }
}

package ModelBindings {
    private import ScalarValues::*;

    doc /* Shared metadata for a product model: what the model declares as its status, and
         which code and tests belong to an element. A project whose tools read these in
         another form keeps that form and does not include this file. */

    enum def BuildState { enum built; enum partlyBuilt; enum planned; }
    enum def AutomationState { enum automated; enum manual; enum planned; }

    metadata def Status {
        doc /* What the model declares about an element. A declaration is not a test
             result. */
        attribute build : BuildState;
    }
    metadata def Automation {
        doc /* How the element's verification runs, as declared. */
        attribute run : AutomationState;
    }
    metadata def ImplementedIn {
        doc /* The module that implements a part or a function of a part. */
        attribute module : String;
    }
    metadata def TestedBy {
        doc /* The test that shows a promise at the part boundary. */
        attribute test : String;
    }
    metadata def DetailTests {
        doc /* The tests of the inside of a part, as a set. */
        attribute tests : String;
        attribute covers : String;
    }
}

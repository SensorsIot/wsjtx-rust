/* Shared metadata for a product model: what the model leaves unsaid, what it declares
   as its status, where a rule comes from, and which code and tests belong to an element.
   A project includes this file in its model and imports the package. */
package ModelNotes {
    private import ScalarValues::*;

    /* Something observable that a coder needs and the model lacks. Needs a decision. */
    metadata def NotStated { attribute what : String; }

    /* Two statements that disagree: in the model, or between the model, the code and a
       named reference. The text names both. */
    metadata def Conflict { attribute what : String; }

    /* A choice left to the coder on purpose, with the limit it must respect. */
    metadata def LeftOpen { attribute what : String; }

    /* The external reference a rule follows, with its version. */
    metadata def FollowsSource { attribute reference : String; }

    /* A deliberate difference from that reference. */
    metadata def DiffersFromSource { attribute what : String; }

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

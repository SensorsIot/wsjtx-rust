package ModelNotes {
    private import ScalarValues::*;

    doc /* Shared metadata for the product model: what the model leaves unsaid, and where a
         rule comes from. */

    metadata def NotStated {
        doc /* Something observable that a coder needs and the model lacks. Needs a
             decision. */
        attribute what : String;
    }
    metadata def Conflict {
        doc /* Two statements that disagree: in the model, or between the model, the code
             and a named reference. The text names both. */
        attribute what : String;
    }
    metadata def LeftOpen {
        doc /* A choice left to the coder on purpose, with the limit it must respect. */
        attribute what : String;
    }
    metadata def FollowsSource {
        doc /* The external reference a rule follows, with its version. */
        attribute reference : String;
    }
    metadata def DiffersFromSource {
        doc /* A deliberate difference from that reference. */
        attribute what : String;
    }
}

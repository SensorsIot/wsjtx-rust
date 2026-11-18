package WstxModelNotes {
    private import ScalarValues::*;

    doc /* Shared metadata for the product model: what the model leaves unsaid, and where a
         rule comes from. */

    metadata def NotStated {
        doc /* Something observable that a coder needs and the model lacks. Needs a
             decision. */
        attribute what : String;
    }
    metadata def FollowsSource {
        doc /* The external reference a rule follows, with its version. */
        attribute reference : String;
    }
    metadata def Debugging {
        doc /* A clause of a debugging function: it serves finding faults, not operating,
             and no use case carries it. */
    }
    metadata def CodeDiffers {
        doc /* What the code does today where it differs from the element this marks. */
        attribute what : String;
    }
    metadata def DiffersFromSource {
        doc /* A deliberate difference from that reference. */
        attribute what : String;
    }
}

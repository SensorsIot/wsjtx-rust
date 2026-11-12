/* Shared metadata for a product model: what the model leaves unsaid, and where a rule
   comes from.
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
}

// Canonical authority: SysML
package WstxRequirements {
    private import ScalarValues::*;
    doc /* Canonical functional requirements and durable verification definitions.
         The other Wstx packages own detailed typed contracts; validation does not execute tests.
         Coverage flags describe implemented source slices, not acceptance or whole-project parity. */
    enum def ImplementationState { enum target; enum partial; enum implemented; }
    enum def AutomationState { enum planned; enum partial; enum implemented; }

}

package WstxProfileAccess {
    private import ScalarValues::*;
    private import WstxArchitecture::ProfileOutcome;
    private import WstxArchitecture::ProfileRequest;
    port def ProfileAccess {
        out item request : ProfileRequest;
        in item outcome : ProfileOutcome;
    }
}

// Fixture of the model-value readers (TC-DOC-014): each value here is refused; the reasons
// are in ../expected.json.
package FixtureFaults {
    private import ScalarValues::*;
    attribute twice : Integer = 1;
    attribute twice : Integer = 2;
    attribute unset : Integer;
    attribute sum : Integer = 1 + 2;
    attribute joined : String = "a" + "b";
    attribute pair = (1, 2);
    attribute windowSeconds = 5 [SI::s];
    attribute ft8WindowMaxSecs : Integer = 5;
    attribute pollMs : Integer = 2000;
    attribute def Unused { attribute count : Integer; }
}

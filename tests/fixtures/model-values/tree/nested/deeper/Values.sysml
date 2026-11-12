// Fixture of the model-value readers (TC-DOC-014): read by server/tests/model_values.rs and
// tests/model-values.test.cjs against ../../../expected.json. Two folders deep, and the file
// name differs from its package.
package FixtureValues {
    private import ScalarValues::*;
    doc /* attribute documentedOnly : Integer = 3; */

    // attribute commentedLine : Integer = 1;
    /* attribute commentedBlock : Integer = 2; */

    attribute pageRecords : Integer = 1;
    attribute workerMemoryMaxMiB : Integer = 64;
    attribute offsetHz : Integer = -150;
    attribute enabled : Boolean = true;
    attribute disabled : Boolean = false;
    attribute 'type' : String = "quoted name";
    attribute text : String = "say \"hi\"; {open} close} // not a comment";
    attribute chosen : Mode = Mode::second;

    enum def Mode {
        doc /* first: one. second: two. enum fourth; is not a member. */
        enum first;
        second;
        enum third { doc /* a member with a doc body */ }
    }

    attribute def Entry {
        attribute band : String;
        attribute ft8Hz : Integer;
        attribute ft4Hz : Integer[0..1];
        attribute weight : Real = -2.5;
    }
    attribute entryOne : Entry {
        attribute :>> band = "20m";
        attribute :>> ft8Hz = 14074000;
        attribute :>> ft4Hz = 14080000;
    }
    attribute entryTwo : FixtureValues::Entry {
        attribute :>> band = "160m";
        attribute :>> ft8Hz = 1840000;
        attribute :>> ft4Hz = null;
    }
    attribute other : Other { attribute :>> band = "not an entry"; }
    attribute entryThree : Entry {
        // attribute :>> band = "commented";
        attribute :>> band = "6m";
        attribute :>> ft8Hz = 50313000;
        attribute :>> ft4Hz = 50318000;
    }
}

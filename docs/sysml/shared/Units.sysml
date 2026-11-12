package WstxUnits {
    doc /* The units a value of the model may carry in its name. A value with a unit ends its
         name in one member of UnitSuffix and is written as a number in that unit. */

    enum def UnitSuffix {
        doc /* Hz: hertz. Ms: milliseconds. Seconds: seconds. Bytes: bytes. MiB: mebibytes,
             1,048,576 bytes. Db: decibels. Frames: audio sample frames at the rate of the
             audio stream. */
        enum Hz;
        enum Ms;
        enum Seconds;
        enum Bytes;
        enum MiB;
        enum Db;
        enum Frames;
    }
}

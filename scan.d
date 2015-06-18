module filepunch.scan;

import std.algorithm;
import std.file : dirEntries, SpanMode;
import std.stdio;

import core.sys.posix.unistd : close;

import filepunch.file;

int main(string[] args)
{
     auto names =
        dirEntries(".", SpanMode.shallow, false)
        .filter!(de => de.isFile)
        .map!(de => de.name);

    foreach (name; names) {
        auto fd = openToRead(name);
        scope(exit) close(fd);

        auto info = getFileInfo(fd);

        // Write this stuff before we go through the file in case that explodes.
        write(name, " could save ");

        auto zeroSpaceLengths = getZeroRuns(fd, info)
                                      .map!(zr => zr.length);
        const auto zeroSpace = reduce!((l1, l2) => l1 + l2)(0L, zeroSpaceLengths);
        writeln(possibleSavings(info, zeroSpace).toHuman);
    }

    return 0;
}


size_t pessimalSize(const ref FileInfo fi)
{
    return max(fi.logicalSize + (fi.blockSize - fi.logicalSize % fi.blockSize),
               fi.actualSize);
}

size_t possibleSavings(const ref FileInfo fi, size_t zeroSpace)
{
    immutable pessimal = pessimalSize(fi);
    immutable optimal = pessimal - zeroSpace;
    return fi.actualSize <= optimal ? 0 : fi.actualSize - optimal;
}

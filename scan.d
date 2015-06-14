module filepunch.scan;

import std.algorithm;
import std.file;
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
        write("name: ", name,
                " logical: ", info.logicalSize,
                " actual: ", info.actualSize,
                " block size: ", info.blockSize);

        auto zeroSpaceLengths = getZeroRuns(fd, info)
                                      .map!(zr => zr.length);
        const auto zeroSpace = reduce!((l1, l2) => l1 + l2)(0L, zeroSpaceLengths);
        writeln(" zero space: ", zeroSpace);
    }

    return 0;
}

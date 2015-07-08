module filepunch.scan;

import std.algorithm;
import std.c.stdlib : exit;
import std.conv : to;
import std.stdio;
import std.getopt;
import std.range : empty;

import core.sys.posix.unistd : close;

import argstopaths;
import help;

import filepunch.file;

int main(string[] args)
{
    bool machine;
    bool recursive;

    try {
        getopt(args,
            config.caseSensitive,
            config.bundling,
            "help|h", { writeAndSucceed(helpText); },
            "version", { writeAndSucceed(versionText); },
            "recursive|r", &recursive,
            "machine|m", &machine);
    }
    catch (GetOptException e) {
        writeAndFail(e.msg, "\n", "See --help for more information.");
    }

    // Slice off the path through which we were invoked
    args = args[1 .. $];

    if (args.empty)
        writeAndFail("No files provided");

    foreach (name; argsToPaths(args, recursive)) {
        auto fd = openToRead(name);
        scope(exit) close(fd);

        auto info = getFileInfo(fd);

        // Write this stuff before we go through the file in case that explodes.
        write(name, machine ? " " : " could save ");

        auto zeroSpaceLengths = getZeroRuns(fd, info)
                                      .map!(zr => zr.length);
        const auto zeroSpace = reduce!((l1, l2) => l1 + l2)(0L, zeroSpaceLengths);

        immutable possible = possibleSavings(info, zeroSpace);
        writeln(machine ? possible.to!string : possible.toHuman);
    }

    return 0;
}

size_t pessimalSize(const ref FileInfo fi)
{
    // The largest the file could be is the max of its actual size or,
    // if the file is sparse, its logical size rounded up to the nearest block.
    return max(fi.logicalSize + (fi.blockSize - fi.logicalSize % fi.blockSize),
               fi.actualSize);
}

size_t possibleSavings(const ref FileInfo fi, size_t zeroSpace)
{
    immutable pessimal = pessimalSize(fi);
    immutable optimal = pessimal - zeroSpace; // The smallest it could be

    // The amount of space we can save is the difference between the optimal
    // size and the current (actual) size, provided that value is positive.
    return fi.actualSize <= optimal ? 0 : fi.actualSize - optimal;
}

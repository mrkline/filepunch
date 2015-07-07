module filepunch.scan;

import std.algorithm;
import std.c.stdlib : exit;
import std.conv : to;
import std.stdio;
import std.getopt;

import core.sys.posix.unistd : close;

import argstopaths;

import filepunch.file;

int main(string[] args)
{
    bool machine;
    bool recursive;

    try {
        getopt(args,
            config.caseSensitive,
            config.bundling,
            "help|h", { writeln(helpText); exit(0); },
            "version", { writeln(versionText); exit(0); },
            "recursive|r", &recursive,
            "machine|m", &machine);
    }
    catch (GetOptException e) {
        stderr.writeln(e.msg);
        stderr.writeln("See --help for more information.");
        exit(1);
    }

    foreach (name; argsToPaths(args[1 .. $], recursive)) {
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

string helpText = q"EOS
Usage: holescan [<options>] <files and directories>

Scans files for space that could be saved as holes.

Several Linux filesystems (XFS, ext4, btrfs, tmpfs) support sparse files, i.e.
files that save space by omitting empty filesystem blocks that contain only
zeroes. Unfortunately, these "holes" in the files aren't automatically created
by writing a string of zeroes, but only by seeking past them with `fseek`,
`lseek`, etc. It's entirely possible that more room on your hard drive could be
saved by finding empty blocks and replacing them with holes.

This utility scans through the given files and reports on how much space can be
saved for each. It currently assumes that it is on a filesystem that supports
sparse files. Functionality to check this beforehand may be added in future
versions.

Options:

  --help, -h
    Show this text and exit.

  --version
    Show version information and exit.

  --recursive
    Recursively search specified directories, which are otherwise ignored.

  --machine, -m
    Display output better suited for by other scripts/programs instead of
    humans. When specified, each line of output will consist of the file path, a
    space, then the number of bytes that could be saved by punching holes.
EOS";

string versionText = q"EOS
holescan, v 0.1
Part of the filepunch toolset by Matt Kline, 2015
https://github.com/mrkline/filepunch
EOS";

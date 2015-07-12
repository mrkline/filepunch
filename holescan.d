module filepunch.holescan;

import std.algorithm;
import std.conv : to;
import std.getopt;
import std.range : empty;
import std.stdio;
import std.typecons;

import core.sys.posix.unistd : close;

import argstopaths;
import help;

import filepunch.file;
import filepunch.linuxio;

int main(string[] args)
{
    bool verbose;
    bool machine;
    bool recursive;

    try {
        getopt(args,
            config.caseSensitive,
            config.bundling,
            "help|h", { writeAndSucceed(helpText); },
            "version", { writeAndSucceed(versionText); },
            "verbose|v", &verbose,
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

    real total = 0;

    auto descriptorRange = argsToPaths(args, recursive)
        // Open the file descriptor and tack it on
        .map!(path => tuple!("path", "fd")(path, openToRead(path)));


    foreach (file; descriptorRange) {
        scope(exit) close(file.fd);

        if (file.fd < 0) {
            stderr.writeln("Could not open ", file.path, ", skipping");
            continue;
        }

        auto info = getFileInfo(file.fd);

        auto zeroRunLengths = getZeroRuns(file.fd, info)
            .map!(zr => zr.length);

        // We need to seed reduce with 0, as it is possible that zeroRunLengths
        // is an empty range (there are no empty blocks)
        immutable zeroSpace = reduce!((l1, l2) => l1 + l2)(0L, zeroRunLengths);

        immutable possible = possibleSavings(info, zeroSpace);
        total += possible;

        if (possible > 0 || verbose) {
            writeln(file.path, machine ? " " : " could save ",
                    machine ? possible.to!string : possible.toHuman);
        }

    }
    if (machine)
        writeln(total);
    else
        writeln("Total possible savings: ", total.toHuman);

    return 0;
}

string helpText = q"EOS
Usage: holescan [<options>] <files and directories>

Scans files for empty blocks (that could be represented as holes).

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

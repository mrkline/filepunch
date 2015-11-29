module filepunch.filepunch;

import std.algorithm;
import std.conv : to;
import std.getopt;
import std.range;
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
        .map!(path => tuple!("path", "fd")(path, openToReadAndWrite(path)))
        // Don't run the above mapping more than once per path
        .cache()
        // Filter out bad file descriptors and warn about them
        .filter!(f => filterDescriptorsAndWarn(f.path, f.fd));


    foreach (file; descriptorRange) {
        scope(exit) close(file.fd);

        auto info = getFileInfo(file.fd);

        immutable preSize = info.actualSize;

        auto zeroSpace = getZeroRuns(file.fd, info)
            // While we're calculating the size of all zero runs in the file,
            // punch them into holes.
            .tee!(zr => punchHole(file.fd, zr))
            .map!(zr => zr.length)
            .sum;

        // possibleSavings() is just an estimate.
        // Just stat the file again instead.
        immutable postSize = getFileInfo(file.fd).actualSize;

        if (postSize > preSize) {
            /* Tests indicate that though files can seem to get larger,
             * the additional size usually goes away after the file has actually
             * been sunk to disk.
             * Filesystems are odd.
             */
        }
        else {
            immutable saved = preSize - postSize;
            total += saved;

            if (saved > 0 || verbose) {
                writeln(file.path, machine ? " " : " saved ",
                        machine ? saved.to!string : saved.toHuman);
            }
        }
    }
    if (machine)
        writeln(total);
    else
        writeln("Total savings: ", total.toHuman);

    return 0;
}

string helpText = q"EOS
Usage: filepunch [<options>] <files and directories

Saves space in files by punching holes in empty blocks

Several Linux filesystems (XFS, ext4, btrfs, tmpfs) support sparse files, i.e.
files that save space by omitting empty filesystem blocks that contain only
zeroes. Unfortunately, these "holes" in the files aren't automatically created
by writing a string of zeroes, but only by seeking past them with `fseek`,
`lseek`, etc. It's entirely possible that more room on your hard drive could be
saved by finding empty blocks and replacing them with holes.

This utility scans through the given files and punches holes wherever possible.
It currently assumes that it is on a filesystem that supports sparse files.
Functionality to check this beforehand may be added in future versions.

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
    space, then the number of bytes saved by punching holes.
EOS";

string versionText = q"EOS
filepunch, v 0.1
Part of the filepunch toolset by Matt Kline, 2015
https://github.com/mrkline/filepunch
EOS";

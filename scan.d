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
            "version|v", { writeln(versionText); exit(0); },
            "machine|m", &machine,
            "recursive|r", &recursive
            );
    }
    catch (GetOptException e) {
        stderr.writeln(e.msg);
        stderr.writeln("See scan --help for more information.");
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
    return max(fi.logicalSize + (fi.blockSize - fi.logicalSize % fi.blockSize),
               fi.actualSize);
}

size_t possibleSavings(const ref FileInfo fi, size_t zeroSpace)
{
    immutable pessimal = pessimalSize(fi);
    immutable optimal = pessimal - zeroSpace;
    return fi.actualSize <= optimal ? 0 : fi.actualSize - optimal;
}

string helpText = q"EOS
EOS";

string versionText = q"EOS
filepunch, v 0.1
by Matt Kline, 2015
EOS";

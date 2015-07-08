import std.stdio;
import std.c.stdlib : exit;

/// Writes whatever you tell it and then exits the program successfully
void writeAndSucceed(S...)(S toWrite)
{
	writeln(toWrite);
	exit(0);
}

/// Writes the help text and fails.
/// If the user explicitly requests help, we'll succeed (see writeAndSucceed),
/// but if what they give us isn't valid, bail.
void writeAndFail(S...)(S helpText)
{
	stderr.writeln(helpText);
	exit(1);
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

module filepunch.file;

import std.conv : to;
import std.exception;
import std.range : empty;
import std.string : toStringz;

import core.sys.linux.errno;
import core.sys.posix.fcntl;
import core.sys.posix.stdio;
import core.sys.posix.sys.stat;
import core.sys.posix.sys.types;
import core.sys.posix.unistd;

extern(C) {

int fallocate(int fd, int mode, off_t offset, off_t len);

/// Linux lseek extensions (see man 2 lseek)
enum {
    SEEK_DATA = 3,
    SEEK_HOLE = 4
}

} // end extern(C)

immutable kilo = 1024;
immutable mega = kilo * 1024;
immutable giga = mega * 1024;

/** Takes a number of bytes and returns a human-readable value
 * in bytes, KB, MB, or GB
 *
 * This is a terribly poor imitation of -h output of du,
 * as generated by gnulib's human_readable.
 */
string toHuman(real bytes)
{
    import std.format;
    string prefix;

    if (bytes == 0)
        return "0";

    if (bytes >= giga) {
        bytes /= giga;
        prefix = "G";
    }
    else if (bytes >= mega) {
        bytes /= mega;
        prefix = "M";
    }
    else if (bytes >= kilo) {
        bytes /= kilo;
        prefix ="K";
    }

    if (bytes < 10 && !prefix.empty)
        return format("%.1f", bytes) ~ prefix;
    else
        return format("%.0f", bytes) ~ prefix;
}

unittest
{
    assert(toHuman(1023) == "1023");
    assert(toHuman(1024) == "1.0K");
    assert(toHuman(1024 * 5) == "5.0K");
    assert(toHuman(1024 * 11) == "11K");
    assert(toHuman(0) == "0");
    assert(toHuman(7) == "7");
}

/// Opens a Posix file descriptor in read-only mode
int openToRead(string path)
{
    auto fd = open(path.toStringz, O_RDONLY);
    return fd;
}

/// Information about a file deduced from stat()
/// that we care about
struct FileInfo {
    /// The apparent size of the file
    size_t logicalSize;
    /// The actual, on-disk size of the file (in multiples of block size)
    size_t actualSize;
    /// The size of the filesystem blocks for this file
    size_t blockSize;
}

FileInfo getFileInfo(int fd)
{
    stat_t ss;
    enforce(fstat(fd, &ss) == 0, "fstat failed");

    FileInfo ret;
    ret.logicalSize = ss.st_size;
    // st_blocks is in "blocks" of 512, regardless of the actual st_blksize.
    ret.actualSize = ss.st_blocks * 512;
    ret.blockSize = ss.st_blksize;

    return ret;
}

/// A run of zero bytes in a file
struct ZeroRun {
    /// The offset in bytes from the start of the file
    size_t start;
    /// Length of the run, in bytes
    size_t length;
}

auto getZeroRuns(int fd, const ref FileInfo fi)
{
    import std.algorithm : all;
    import std.range;
    import std.traits : ReturnType;

    // See readBlock() below
    static struct BlockResults {
        /// The block contained no non-zero bytes
        bool isAllZeroes;
        /// The amount read
        /// (could be less than the block size if we hit EOF)
        ReturnType!read amountRead;
    }

    /// The Voldemort type that provides our range of ZeroRuns
    static struct PossibleHoleFinder {
        this(int _fd, size_t bs) {
            fd = _fd;
            // Ideally, we'd use malloc and free here instead of bringing
            // the GC into this, but some of the std.algorithm ranges
            // (e.g. reduce) copy the ranges fed to them by value, causing
            // fun double deletes and the like.
            // TODO: Have std.algorithm ranges move, if possible.
            bb = new ubyte[bs];
            popFront();
        }

        @property auto ref front() { return curr; }

        void popFront()
        {
            enforce(!empty, "You cannot pop an empty range.");
            BlockResults br;

            // Look for a block that is all zeroes (or stop at EOF)
            do {
                br = readBlock();
            } while (br.amountRead > 0 && !br.isAllZeroes);

            // If we hit EOF, we're done.
            if (br.amountRead == 0) {
                bb = null; // Makes empty() true
                return;
            }

            // Otherwise we just hit the start of a new run of zeroes
            // Update curr (our current ZeroRun) as needed
            auto currentLocation = lseek(fd, 0, SEEK_CUR);
            enforce(currentLocation >= 0,
                    "lseek(fd, 0, SEEK_CUR) failed with errno " ~
                    errno.to!string);
            curr.start = currentLocation - br.amountRead;
            curr.length = br.amountRead;

            // Keep reading until we hit EOF or stop getting zeroes
            while(true) {
                br = readBlock();
                if (br.amountRead == 0 || !br.isAllZeroes)
                    return;

                curr.length += br.amountRead;

                // We may be in a hole, and can drastically speed things up
                // by jumping out of the hole
                currentLocation = curr.start + curr.length;

                immutable saughtLocation = lseek(fd, currentLocation, SEEK_DATA);
                // There is a very unlikely but possible chance that the rest
                // of this file is one big hole, in which case lseek will fail
                // with errno ENXIO
                if (saughtLocation < 0) {
                    enforce(errno == ENXIO,
                            "Unknown failure of lseek(SEEK_DATA), errno " ~
                            errno.to!string);
                    immutable end = lseek(fd, 0, SEEK_END);
                    curr.length = end - curr.start;
                    return;
                }

                // If we didn't skip over a hole, saught - current == 0,
                // so there's no need to branch here.
                curr.length += saughtLocation - currentLocation;
            }
        }

        // Our buffer pointer doubles as an indicator if we've hit EOF
        // See the EOF condition in popFront()
        @property bool empty() { return bb is null; }

    private:
        int fd; // file descriptor
        ubyte[] bb; // block buffer
        ZeroRun curr; // current item in the range

        /// Reads one filesystem block of the file and checks if it was all 0.
        BlockResults readBlock() {
            assert(bb !is null);
            BlockResults ret;
            ret.amountRead = read(fd, &bb[0], bb.length);
            enforce(ret.amountRead >= 0, "read() failed with errno " ~
                                         errno.to!string);
            ret.isAllZeroes = all!(b => b == 0)(bb);
            return ret;
        }
    }
    // Ensure that we have created an input range that returns ZeroRuns.
    static assert(isInputRange!PossibleHoleFinder);
    static assert(is(typeof(PossibleHoleFinder.front()) == ZeroRun));

    return PossibleHoleFinder(fd, fi.blockSize);
}

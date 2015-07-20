module filepunch.linuxio;

import std.conv : to;
import std.exception;
import std.range;
import std.string : toStringz;

import core.sys.linux.errno;
import core.sys.posix.fcntl;
import core.sys.posix.stdio;
import core.sys.posix.sys.stat;
import core.sys.posix.sys.types;
import core.sys.posix.unistd;

private extern(C) {

int fallocate(int fd, int mode, off_t offset, off_t len);

/// Linux lseek extensions (see man 2 lseek)
enum {
    SEEK_DATA = 3,
    SEEK_HOLE = 4
}

enum {
    FALLOC_FL_KEEP_SIZE = 0x01,
    FALLOC_FL_PUNCH_HOLE = 0x02,
    FALLOC_FL_NO_HIDE_STALE = 0x04
}

} // end extern(C)

int openToRead(string path)
{
    return open(path.toStringz, O_RDONLY);
}

int openToReadAndWrite(string path)
{
    return open(path.toStringz, O_RDWR);
}

/// Information about a file deduced from stat() that we care about
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

void punchHole(int fd, ZeroRun run)
{
    enforce(fallocate(fd, FALLOC_FL_KEEP_SIZE | FALLOC_FL_PUNCH_HOLE,
                      run.start, run.length) == 0,
            "fallocate failed with error " ~ errno.to!string);

}

/// Returns a range of runs of zero bytes in a file
auto getZeroRuns(int fd, const ref FileInfo fi)
{
    import std.algorithm : all;
    import std.traits : ReturnType;

    // See readBlock() below
    static struct BlockResults {
        /// The block contained no non-zero bytes
        bool isAllZeroes;
        /// The amount read (could be less than the block size if we hit EOF)
        ReturnType!read amountRead;
    }

    /// The Voldemort type that acts as our range of ZeroRuns
    static struct PossibleHoleFinder {

    private:
        int fd; // file descriptor
        ubyte[] bb; // block buffer
        ZeroRun curr; // current item in the range

        /// Reads one filesystem block of the file and checks if it was all 0.
        BlockResults readBlock() {
            assert(bb !is null);
            BlockResults ret;
            ret.amountRead = read(fd, &bb[0], bb.length); // Standard Posix read
            enforce(ret.amountRead >= 0, "read() failed with errno " ~
                                         errno.to!string);
            ret.isAllZeroes = all!(b => b == 0)(bb[0 .. ret.amountRead]);
            return ret;
        }

    public:
        // Constructor that takes the file descriptor and the block size
        this(int _fd, size_t bs) {
            fd = _fd;
            // Ideally, we'd use malloc and free here instead of bringing
            // the GC into this, but some of the std.algorithm ranges
            // (e.g. reduce) copy the ranges fed to them by value, causing
            // fun double deletes and the like.
            // TODO: Have std.algorithm ranges move, if possible.
            bb = new ubyte[bs];
            popFront(); // Bring up the first zero run
        }

        @property auto ref front() { return curr; }

        void popFront()
        {
            enforce(!empty, "You cannot pop an empty range.");

            // Look for a block that is all zeroes (or stop at EOF)
            BlockResults br;
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
                // by jumping out of the hole using lseek with SEEK_DATA
                currentLocation = curr.start + curr.length;
                immutable soughtLocation = lseek(fd, currentLocation, SEEK_DATA);

                // There is a very unlikely but possible chance the rest
                // of this file is one big hole, in which case lseek will fail
                // with errno ENXIO
                if (soughtLocation < 0) {
                    enforce(errno == ENXIO,
                            "Unknown failure of lseek(SEEK_DATA), errno " ~
                            errno.to!string);
                    immutable end = lseek(fd, 0, SEEK_END);
                    curr.length = end - curr.start;
                    return;
                }

                // If we didn't skip over a hole, sought - current == 0,
                // so there's no need to branch here.
                curr.length += soughtLocation - currentLocation;
            }
        }

        // Our buffer pointer doubles as an indicator if we've hit EOF
        // See the EOF condition in popFront()
        @property bool empty() { return bb is null; }
    }
    // Ensure we have created an input range which returns ZeroRuns.
    static assert(isInputRange!PossibleHoleFinder);
    static assert(is(ReturnType!(PossibleHoleFinder.front) == ZeroRun));

    return PossibleHoleFinder(fd, fi.blockSize);
}

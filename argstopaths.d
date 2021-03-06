import std.algorithm;
import std.exception;
import std.file;
import std.range;
import std.range.interfaces;
import std.stdio;

InputRange!string argsToPaths(string[] paths, bool recursive)
{
    // Ignore paths that don't exist (see filterExisting)
    auto existingPaths = paths.filter!(p => filterExisting(p));

    // The .save is so we make a copy of the range, using the original
    // for directories below. This does mean we'll filter twice
    // (and possibly stat the file on the filesystem multiple times),
    // but it's a minuscule hit in comparison to the rest of the I/O
    // we'll be doing.
    auto files = existingPaths.save.filter!(p => p.isFile);
    auto dirs = existingPaths.filter!(p => p.isDir);

    if (recursive) {
        auto expandedDirs = dirs
            .map!(p => expandDirectory(p)) // recurse into them
            .cache() // Don't evaluate the above mapping several times
            .joiner // Join these ranges into one contiguous one
            .handle!(Exception, RangePrimitive.access | RangePrimitive.pop,
                     (e, r) => DirEntry.init)
            .filter!(de => de != de.init)
            .filter!(p => p.isFile) // We only want the files
            .map!(de => de.name); // Reduce from DirEntry back down to a string

        // We wrap this so we can use polymorphism to have a single return type
        // (the InputRange interface)
        return inputRangeObject(chain(files, expandedDirs));
    }
    else {
        foreach (dir; dirs)
            stderr.writeln("ignoring directory " , dir);

        // We wrap this so we can use polymorphism to have a single return type
        // (the InputRange interface)
        return inputRangeObject(files);
    }
}

private:

bool filterExisting(string path)
{
    if (path.exists) {

        auto de = DirEntry(path);
        if (!de.isFile && !de.isDir) {
            stderr.writeln("ignoring special file ", path);
            return false;
        }

        return true;
    }
    else {
        stderr.writeln(path, " does not exist");
        return false;
    }
}

InputRange!DirEntry expandDirectory(string path)
{
    try {
        return inputRangeObject(dirEntries(path, SpanMode.depth, false));
    }
    catch (Exception ex) {
        stderr.writeln("Could not open directory ", path, ", skipping");
        return inputRangeObject(only(DirEntry.init));
    }
}

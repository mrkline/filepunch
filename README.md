# Filepunch

## What?

Several Linux filesystems (XFS, ext4, btrfs, tmpfs) support _sparse files_, i.e.
files that save space by omitting empty filesystem blocks that contain only zeroes.
Unfortunately, these "holes" in the files aren't automatically created by writing
a string of zeroes, but only by seeking past them with `fseek`, `lseek`, etc.
It's entirely possible that more room on your hard drive could be saved by
finding empty blocks and replacing them with holes.

I plan on building two tools:

1. A scanner, which scans through files to find how much space could be saved by
   replacing empty blocks with holes.

2. A "hole puncher" which actually punches holes over empty blocks.

## Why?

I was interested in learning more about sparse files and playing with related
system calls.

## Caveats

This is most useful for files that are unlikely to be modified,
since any writes to holes will force the filesystem to create actual blocks
in their stead.

## License

Zlib (I did it, do whatever you want, I'm not liable for whatever happens).

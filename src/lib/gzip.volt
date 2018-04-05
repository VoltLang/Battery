module lib.gzip;

import watt.io;
import watt.path;
import watt.io.streams;
import watt.text.sink;
import watt.text.path;

import lib.miniz;

enum Id1                = 31;
enum Id2                = 139;
enum DeflateCompression = 8;

enum u8 FlagText        = 0b00000001;
enum u8 FlagHcrc        = 0b00000010;
enum u8 FlagExtra       = 0b00000100;
enum u8 FlagName        = 0b00001000;
enum u8 FlagComment     = 0b00010000;
enum u8 ReservedFlags   = 0b11100000;

enum CHUNKSIZE = 128;  //! Read and write up to this many bytes at a time.

fn extract(inFilename: string, destination: string) string
{
	version (Windows) {
		ifs := new InputFileStream(inFilename, "rb");
	} else {
		ifs := new InputFileStream(inFilename);
	}
	if (ifs.get() != Id1) {
		return null;
	}
	if (ifs.get() != Id2) {
		return null;
	}

	compression := cast(i32)ifs.get();
	if (compression != DeflateCompression) {
		return null;
	}

	flags := cast(u8)ifs.get();
	if ((flags & ReservedFlags) != 0) {
		return null;
	}

	// Skip MTIME, (todo)XFL, and OS bytes.
	ifs.skipBytes(6);
	if (ifs.eof()) {
		return null;
	}

	if (flags & FlagExtra) {
		xlen := ifs.readShort();
		// Ignore the FEXTRA stuff.
		ifs.skipBytes(xlen);
	}

	filename: string;
	if (flags & FlagName) {
		filename = ifs.readNulString();
	} else {
		ext := extension(inFilename);
		filename = inFilename[0 .. $-ext.length];
	}

	if (flags & FlagComment) {
		// Ignore the FCOMMENT.
		ifs.readNulString();
	}

	if (flags & FlagHcrc) {
		// Ignore the FCRC.
		ifs.readShort();
	}

	filename = concatenatePath(destination, baseName(filename));
	version (Windows) {
		ofs := new OutputFileStream(filename, "wb");
	} else {
		ofs := new OutputFileStream(filename);
	}
	assert(ofs.isOpen);

	mzs: mz_stream_s;
	mz_inflateInit2(&mzs, -MZ_DEFAULT_WINDOW_BITS);
	scope (exit) mz_inflateEnd(&mzs);

	inbuf : u8[CHUNKSIZE];
	outbuf: u8[CHUNKSIZE];
	mzs.next_out = &outbuf[0];
	mzs.avail_out = cast(u32)outbuf.length;
	iter: size_t;
	for (;;) {
		if (ifs.eof() && mzs.avail_in == 0) {
			return null;
		}
		// Read `CHUNKSIZE` bytes of input.
		if (mzs.avail_in == 0) {
			inbufsz: size_t;
			while (!ifs.eof() && inbufsz < inbuf.length) {
				inbuf[inbufsz++] = cast(u8)ifs.get();
			}
			mzs.next_in = &inbuf[0];
			mzs.avail_in = cast(u32)inbufsz;
		}

		status := mz_inflate(&mzs, MZ_SYNC_FLUSH);
		if (status == MZ_BUF_ERROR && mzs.avail_in == 0) {
			// Needs more data to continue.
			continue;
		}
		if (status == MZ_STREAM_END || mzs.avail_out == 0) {
			n := CHUNKSIZE - mzs.avail_out;
			foreach (i; 0 .. n) {
				ofs.put(outbuf[i]);
			}
			mzs.next_out = &outbuf[0];
			mzs.avail_out = cast(u32)outbuf.length;
		}

		if (status == MZ_STREAM_END) {
			break;
		} else if (status != MZ_OK) {
			return null;
		}
	}

	ofs.close();
	ifs.close();

	return filename;
}

//! Skip `count` bytes.
fn skipBytes(ifs: InputFileStream, count: size_t)
{
	foreach (i; 0 .. count) {
		ifs.get();
	}
}

//! Read a nul terminated string.
fn readNulString(ifs: InputFileStream) string
{
	ss: StringSink;
	c: dchar;
	do {
		c = ifs.get();
		if (c != 0) {
			ss.sink((cast(char*)&c)[0 .. 1]);
		}
	} while (c != 0 && !ifs.eof());
	return ss.toString();
}

/*!
 * Read two bytes as a number, where the LSB is stored first.  
 * (i.e. 520 == [0b00001000] (8) [0b00000010] (512))
 */
fn readShort(ifs: InputFileStream) size_t
{
	b1 := cast(size_t)ifs.get();
	b2 := cast(size_t)ifs.get();
	return (b2 << 8) | b1;
}

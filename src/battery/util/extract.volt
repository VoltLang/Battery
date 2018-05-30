module battery.util.extract;

import watt = [watt.path, watt.conv, watt.io, watt.algorithm,
watt.io.streams, watt.text.path, watt.io.file, watt.text.string];
version (!Windows) import posix = core.c.posix.sys.stat;

import miniz = amp.archive.miniz;
import gzip = amp.archive.gzip;
import tar = amp.archive.microtar;

/*!
 * Extract an archive file to a directory.
 *
 * The type of the archive is determined by the file extension.  
 *
 * @Params filename The path to the archive file to extract.
 * @Params destination Path to a directory to extract the archive to.
 * If the contents of the archive is one directory, that directory will
 * be extracted directly into `destination`. Otherwise, a directory name
 * based on the filename will be chosen, and the files will be extracted
 * into that.
 * @Returns The path to the directory that was created that contains the
 * archive, or an empty string if the archive couldn't be extracted.
 */
fn archive(filename: string, destination: string) string
{
	extension := watt.toLower(watt.extension(filename));
	switch (extension) {
	case ".zip":
		extractZip(filename, destination);
		break;
	case ".gz":
		if (!watt.endsWith(watt.toLower(filename), ".tar.gz")) {
			return null;
		}
		goto case;
	case ".tgz":
		extractTarGz(filename, destination);
		break;
	default:
		break;
	}
	return findRoot(destination);
}

/* Find a folder containing 'battery.toml' in a path where
 * an archive has just been extracted.
 * Either the battery.toml will be directly in `destination`,
 * or `destination`'s root contains one (and only one) directory
 * that contains battery.toml.  
 * If neither of those conditions hold, `null` is returned.
 */
fn findRoot(destination: string) string
{
	result: string;
	fn dgt(path: string) watt.SearchStatus
	{
		if (path == "." || path == ".." || path == TarHeaderFile) {
			return watt.SearchStatus.Continue;
		}
		if (path == "battery.toml") {
			result = destination;
			return watt.SearchStatus.Halt;
		}
		dir := watt.concatenatePath(destination, path);
		if (watt.isDir(dir)) {
			proposed := watt.concatenatePath(dir, "battery.toml");
			if (watt.exists(proposed)) {
				result = dir;
			}
		}
		return watt.SearchStatus.Halt;
	}
	watt.searchDir(destination, "*", dgt);
	return result;
}

private:

enum TarHeaderFile = "pax_global_header";

fn extractZip(filename: string, destination: string)
{
	firstDirectory: string;

	za: miniz.mz_zip_archive;
	retval := miniz.mz_zip_reader_init_file(&za, watt.toStringz(filename), 0);
	scope (exit) miniz.mz_zip_reader_end(&za);
	if (retval == miniz.MZ_FALSE) {
		return;
	}

	foreach (i: miniz.mz_uint; 0 .. za.m_total_files) {
		filenamelength := miniz.mz_zip_reader_get_filename(&za, i, null, 0);
		filenameBuf := new char[](filenamelength);
		miniz.mz_zip_reader_get_filename(&za, i, filenameBuf.ptr, filenamelength);

		fname := watt.concatenatePath(destination, cast(string)filenameBuf);
		if (miniz.mz_zip_reader_is_file_a_directory(&za, i)) {
			str := watt.concatenatePath(destination, fname);
			watt.mkdirP(fname);
		} else {
			miniz.mz_zip_reader_extract_to_file(&za, i, watt.toStringz(fname), 0);
		}
	}
}

fn extractTarGz(filename: string, destination: string)
{
	tarname := gzip.extract(filename, destination);
	if (tarname !is null) {
		extractTar(tarname, destination);
		watt.remove(tarname);
	}
}

fn extractTar(inFilename: string, destination: string) bool
{
	t: tar.mtar_t;
	h: tar.mtar_header_t;

	if (tar.mtar_open(&t, watt.toStringz(inFilename), "r") != tar.MTAR_ESUCCESS) {
		return false;
	}
	scope (exit) tar.mtar_close(&t);

	while (tar.mtar_read_header(&t, &h) != tar.MTAR_ENULLRECORD) {
		fname := watt.concatenatePath(destination, watt.toString(h.name.ptr));
		if (h.type != cast(u32)tar.MTAR_TDIR) {
			version (Windows) {
				ofs := new watt.OutputFileStream(fname, "wb");
			} else {
				ofs := new watt.OutputFDStream(fname);
			}
			dataWritten: size_t;
			while (dataWritten < h.size) {
				chunk: char[gzip.CHUNKSIZE];
				readsize := watt.min(gzip.CHUNKSIZE, h.size - dataWritten);
				tar.mtar_read_data(&t, cast(void*)chunk.ptr, cast(u32)readsize);
				ofs.write(chunk[0 .. readsize]);
				dataWritten += readsize;
			}
			version (!Windows) posix.fchmod(ofs.fd, cast(posix.mode_t)h.mode);
			ofs.close();
		} else {
			watt.mkdirP(fname);
		}
		tar.mtar_next(&t);
	}

	return true;
}

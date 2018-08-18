// Copyright 2012-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Function for manipulating files and paths.
 */
module build.util.file;

import core.exception;

version (Linux || OSX) {
	import core.c.posix.sys.stat : stat_t, stat;
} else {
	import core.c.windows.windows : MultiByteToWideChar, CP_UTF8,
		GetFileAttributesExW, GET_FILEEX_INFO_LEVELS,
		WIN32_FILE_ATTRIBUTE_DATA;
}

//! @Returns `true` if the file `a` has been modified more recently than `b`.
fn modifiedMoreRecentlyThan(a: string, b: string) bool
{
	aAccess, aModified, bAccess, bModified: u64;
	getTimes(a, out aAccess, out aModified);
	getTimes(b, out bAccess, out bModified);
	return aModified > bModified;
}

fn getTimes(name: string, out access: u64, out modified: u64)
{
	version (OSX || Linux) {
		path: char[512];
		buf: stat_t;

		path[0 .. name.length] = name;
		path[name.length] = 0;

		if (stat(path.ptr, &buf)) {
			throw new Exception("stat failed");
		}

		access = cast(u64)buf.st_atime;
		modified = cast(u64)buf.st_mtime;
	} else {
		buf: WIN32_FILE_ATTRIBUTE_DATA;
		tmp: wchar[512];

		numChars := MultiByteToWideChar(
			CP_UTF8, 0, name.ptr, cast(int)name.length, null, 0);

		if (numChars < 0) {
			throw new Exception("invalid filename");
		}

		if (cast(uint) numChars + 1 > tmp.length) {
			throw new Exception("filename to long");
		}

		numChars = MultiByteToWideChar(
			CP_UTF8, 0, name.ptr, cast(int)name.length, tmp.ptr, numChars);
		tmp[numChars] = '\0';

		ret := GetFileAttributesExW(
			tmp.ptr, GET_FILEEX_INFO_LEVELS.GetFileExInfoStandard,
			cast(void*) &buf);
		if (ret == 0) {
			throw new Exception("GetFileAttributesExW failed");
		}

		access = buf.ftLastAccessTime.dwLowDateTime |
			(buf.ftLastAccessTime.dwHighDateTime << 32UL);

		modified = buf.ftLastWriteTime.dwLowDateTime |
			(buf.ftLastWriteTime.dwHighDateTime  << 32UL);
	}
}

/*!
 * Replaces @oldPrefix and @oldSuffix with @newPrefix and @newSuffix.
 *
 * Assumes that name starts and ends with @oldPrefix, @oldSuffix.
 */
fn replacePrefixAndSuffix(name: string,
                          oldPrefix: string, newPrefix: string,
                          oldSuffix: string, newSuffix: string) string
{
	// Should be enough for all platforms max pathlength.
	len: size_t = name.length -
		oldPrefix.length -
		oldSuffix.length +
		newPrefix.length +
		newSuffix.length;
	data: char[512];
	pos: size_t;

	if (len > data.length) {
		throw new Exception("error in replacePrefixSufix");
	}

	// Poor mans buffered string writer.
	fn add(tmp: string) {
		data[pos .. pos + tmp.length] = tmp;
		pos += tmp.length;
	}

	add(newPrefix);
	add(name[oldPrefix.length + 1 .. $ - oldSuffix.length]);
	add(newSuffix);

	// Make sure we don't return a pointer to the stack.
	return new string(data[0 .. pos]);
}

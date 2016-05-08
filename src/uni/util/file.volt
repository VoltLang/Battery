// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.d (BOOST ver. 1.0).

/**
 * Function for manipulating files and paths.
 */
module uni.util.file;

version (Linux || OSX) {
	import core.posix.sys.stat : stat_t, stat;
} else {
}


void getTimes(string name, out ulong access, out ulong modified)
{
	version (OSX || Linux) {
		char[512] path;
		stat_t buf;

		path[0 .. name.length] = name;
		path[name.length] = 0;

		if (stat(path.ptr, &buf)) {
			throw new Exception("stat failed");
		}

		access = cast(ulong) buf.st_atime;
		modified = cast(ulong) buf.st_mtime;
	} else {
		throw new Exception("getTimes not implemented!");
	}
}

/**
 * Replaces @oldPrefix and @oldSuffix with @newPrefix and @newSuffix.
 *
 * Assumes that name starts and ends with @oldPrefix, @oldSuffix.
 */
string replacePrefixAndSuffix(string name,
                             string oldPrefix, string newPrefix,
                             string oldSuffix, string newSuffix)
{
	// Should be enough for all platforms max pathlength.
	size_t len = name.length -
		oldPrefix.length -
		oldSuffix.length +
		newPrefix.length +
		newSuffix.length;
	char[512] data;
	size_t pos;

	if (len > data.length) {
		throw new Exception("error in replacePrefixSufix");
	}

	// Poor mans buffered string writer.
	void add(string tmp) {
		data[pos .. pos + tmp.length] = tmp;
		pos += tmp.length;
	}

	add(newPrefix);
	add(name[oldPrefix.length + 1 .. $ - oldSuffix.length]);
	add(newSuffix);

	// Make sure we don't return a pointer to the stack.
	return new string(data[0 .. pos]);
}

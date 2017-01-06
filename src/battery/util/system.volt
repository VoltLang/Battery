// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * OS helpers.
 */
module battery.util.system;

import core.exception;
version (Windows) import core.windows;
else import core.posix.unistd;

import watt.text.format;

fn processorCount() u32
{
	count: u32;
	version (Windows) {
		si: SYSTEM_INFO;
		GetSystemInfo(&si);
		count = si.dwNumberOfProcessors;
	}
	version (Posix) {
		count = cast(u32)sysconf(_SC_NPROCESSORS_ONLN);
	} else {
		count = 9;
	}
	if (count == 0) {
		throw new Exception("processorCount failed to detect cpus.");
	}
	return count;
}

fn getBuiltArch() string
{
	version (X86) {
		return "x86";
	} else version (X86_64) {
		return "x86_64";
	} else {
		return "UnknownArch";
	}
}

fn getBuiltPlatform() string
{
	version (MSVC) {
		return "msvc";
	} else version (MinGW) {
		return "mingw";
	} else version (Linux) {
		return "linux";
	} else version (OSX) {
		return "osx";
	}
}

fn getBuiltIdent() string
{
	return format("%s-%s", getBuiltArch(), getBuiltPlatform());
}

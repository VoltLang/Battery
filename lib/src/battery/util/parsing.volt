// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Common parsing functions.
 */
module battery.util.parsing;

import core.exception;
import battery.defines;


fn isArch(s: string) bool
{
	switch (s) {
	case "x86", "x86_64": return true;
	default: return false;
	}
}

fn stringToArch(s: string) Arch
{
	switch (s) {
	case "x86": return Arch.X86;
	case "x86_64": return Arch.X86_64;
	default: throw new Exception("unknown arch");
	}
}

fn isPlatform(s: string) bool
{
	switch (s) {
	case "msvc", "linux", "osx", "metal": return true;
	default: return false;
	}
}

fn stringToPlatform(s: string) Platform
{
	switch (s) {
	case "msvc": return Platform.MSVC;
	case "linux": return Platform.Linux;
	case "osx": return Platform.OSX;
	case "metal": return Platform.Metal;
	default: throw new Exception("unknown platform");
	}
}

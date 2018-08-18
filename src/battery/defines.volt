// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Common enums and defines.
 */
module battery.defines;

import core.exception;


/*!
 * Each of these listed platforms corresponds
 * to a Version identifier.
 *
 * Posix and Windows are not listed here as they
 * they are available on multiple platforms.
 *
 * Posix on Linux and OSX.
 * Windows on MinGW and MSVC.
 */
enum Platform
{
	MSVC,
	Linux,
	OSX,
	Metal,
}

/*!
 * Each of these listed architectures corresponds
 * to a Version identifier.
 */
enum Arch
{
	X86,
	X86_64,
}


/*
 *
 * Misc util
 *
 */

fn toString(arch: Arch) string
{
	final switch(arch) with (Arch) {
	case X86: return "x86";
	case X86_64: return "x86_64";
	}
}

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

fn toString(platform: Platform) string
{
	final switch(platform) with (Platform) {
	case MSVC: return "msvc";
	case Linux: return "linux";
	case OSX: return "osx";
	case Metal: return "metal";
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

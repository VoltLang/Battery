// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.defines;


/**
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

/**
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

string toString(Arch arch)
{
	final switch(arch) with (Arch) {
	case X86: return "x86";
	case X86_64: return "x86_64";
	}
}

string toString(Platform platform)
{
	final switch(platform) with (Platform) {
	case MSVC: return "msvc";
	case Linux: return "linux";
	case OSX: return "osx";
	case Metal: return "metal";
	}
}

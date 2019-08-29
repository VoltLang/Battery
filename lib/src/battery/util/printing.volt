// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Comming printing functions.
 */
module battery.util.printing;

import battery.defines;


fn archToString(arch: Arch) string
{
	final switch(arch) with (Arch) {
	case X86: return "x86";
	case X86_64: return "x86_64";
	case ARMHF: return "armhf";
	case AArch64: return "aarch64";
	}
}

fn platformToString(platform: Platform) string
{
	final switch(platform) with (Platform) {
	case MSVC: return "msvc";
	case Linux: return "linux";
	case OSX: return "osx";
	case Metal: return "metal";
	}
}

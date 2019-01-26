// Copyright 2018, Bernard Helyer.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Functions for retrieving and processing the LLVM version.
 */
module battery.frontend.llvmVersion;

import text     = watt.text.string;
import semver   = watt.text.semver;
import battery  = battery.commonInterfaces;


enum IdentifierPrefixLegacy = "LlvmVersion";
enum IdentifierPrefix = "LLVMVersion";

fn addVersionIdentifiers(ver: semver.Release, prj: battery.Project) bool
{
	if (!prj.llvmHack) {
		return false;
	}

	prj.defs ~= identifiers(ver);
	return true;
}

/*!
 * Given an LLVM version, return a list of identifiers to set while
 * compiling code.
 *
 * So if you pass a version of `3.9.1`, this function will return
 * an array containing `LLVMVersion3`, `LLVMVersion3_9`, and `LLVMVersion3_9_1`.
 * If you pass it a version of greater then 7, like say `8.1.0`. The extra
 * identifiers `LLVMVersion7AndAbove` and `LLVMVersion8AndAbove` will be
 * returned.
 */
fn identifiers(ver: semver.Release) string[]
{
	assert(ver !is null);
	idents: string[];

	idents ~= new "${IdentifierPrefixLegacy}${ver.major}";
	idents ~= new "${IdentifierPrefix}${ver.major}";
	idents ~= new "${IdentifierPrefix}${ver.major}_${ver.minor}";
	idents ~= new "${IdentifierPrefix}${ver.major}_${ver.minor}_${ver.patch}";

	if (ver.major >= 7) foreach (i; 7 .. ver.major + 1) {
		idents ~= new "${IdentifierPrefix}${i}AndAbove";
	}
	return idents;
}

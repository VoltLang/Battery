// Copyright 2018, Bernard Helyer.
// Copyright 2018-2019, Collabora, Ltd.
// Copyright 2026, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Functions for retrieving and processing the LLVM version.
 */
module battery.frontend.llvmVersion;

import watt.conv : toInt;
import watt.text.format : format;
import watt.text.ascii : isDigit;
import watt.text.string : split;
import semver   = watt.text.semver;
import battery  = battery.interfaces;


enum IdentifierPrefixLegacy = "LlvmVersion";
enum IdentifierPrefix = "LLVMVersion";

/*!
 * A requested LLVM version from the --llvm-version flag.
 *
 * Matches Python-style compatible releases: `~=14.1.6` means
 * `>= 14.1.6 && < 15.0.0`. Omitted minor/patch components default to zero.
 */
struct LLVMVersionRequest
{
public:
	ver: semver.Release;
	components: i32;

public:
	@property fn isSet() bool
	{
		return components != 0;
	}

	//! Suffix for versioned LLVM programs, e.g. `-14`.
	fn suffix() string
	{
		if (!isSet) {
			return null;
		}
		return format("-%s", ver.major);
	}

	fn matches(actual: semver.Release) bool
	{
		if (!isSet) {
			return true;
		}

		if (actual < ver) {
			return false;
		}

		upper := new semver.Release(format("%s.0.0", ver.major + 1));
		return actual < upper;
	}

	fn toString() string
	{
		switch (components) {
		case 1:
			return format("%s", ver.major);
		case 2:
			return format("%s.%s", ver.major, ver.minor);
		case 3:
			return ver.toString();
		default:
			return null;
		}
	}
}

/*!
 * Parse a --llvm-version value such as `14`, `14.1`, or `14.1.6`.
 */
fn parseRequest(verString: string, out req: LLVMVersionRequest) bool
{
	if (verString is null) {
		return false;
	}

	parts := split(verString, '.');
	if (parts.length == 0 || parts.length > 3) {
		return false;
	}

	foreach (part; parts) {
		if (part.length == 0) {
			return false;
		}
		foreach (c: char; part) {
			if (!isDigit(c)) {
				return false;
			}
		}
	}

	major := toInt(parts[0]);
	minor := parts.length >= 2 ? toInt(parts[1]) : 0;
	patch := parts.length >= 3 ? toInt(parts[2]) : 0;

	req.components = cast(i32)parts.length;
	req.ver = new semver.Release(format("%s.%s.%s", major, minor, patch));
	return true;
}

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

// Copyright 2018, Bernard Helyer.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Functions for retrieving and processing the LLVM version.
 */
module battery.frontend.llvmVersion;

import llvmConf = battery.frontend.llvmConf;
import text     = watt.text.string;
import semver   = watt.text.semver;
import process  = watt.process;
import battery  = [
	battery.interfaces,
	battery.configuration,
	battery.policy.config,
	battery.policy.tools,
];

enum IdentifierPrefixLegacy = "LlvmVersion";
enum IdentifierPrefix = "LLVMVersion";

/*!
 * Get the installed LLVM version from the system.
 *
 * @Returns The LLVM version or `null` if no LLVM could be detected.
 */
fn get(drv: battery.Driver) semver.Release
{
	if (!gCached) {
		gReleaseCache = getImpl(drv);
		gCached = true;
	}
	return gReleaseCache;
}

fn addVersionIdentifiers(drv: battery.Driver, prj: battery.Project) bool
{
	if (!text.startsWith(prj.name, "volta")) {
		return false;
	}
	prj.defs ~= identifiers(get(drv));
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

private:

global gReleaseCache: semver.Release;
global gCached: bool;

fn getImpl(drv: battery.Driver) semver.Release
{
	version (Windows) {
		if (llvmConf.parsed) {
			return llvmConf.llvmVersion;
		} else {
			return null;
		}
	} else {
		dummyConfig := new battery.Configuration();
		dummyConfig.kind = battery.ConfigKind.Native;
		dummyConfig.env = process.retrieveEnvironment();
		battery.doToolChainLLVM(drv, dummyConfig, battery.UseAsLinker.NO, battery.Silent.YES);
		configCmd := dummyConfig.getTool(battery.LLVMConfigName);
		if (configCmd is null) {
			return null;
		}

		configOutput: string;
		configRetval: u32;
		try {
			configOutput = process.getOutput(configCmd.cmd, ["--version"], ref configRetval);
		} catch (process.ProcessException e) {
			return null;
		}
		configOutput = text.strip(configOutput);
		if (configRetval != 0 || !semver.Release.isValid(configOutput)) {
			return null;
		}
		return new semver.Release(configOutput);
	}
}
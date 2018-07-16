// Copyright © 2018, Bernard Helyer.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
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

enum IdentifierPrefix = "LlvmVersion";

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
	idents := identifiers(get(drv));
	prj.defs ~= idents[..];
	return true;
}

/*!
 * Given an LLVM version, return a list of identifiers to set while
 * compiling code.
 *
 * So if you pass a version of `3.9.1`, this function will return
 * an array containing `LlvmVersion3`, `LlvmVersion3_9`, and `LlvmVersion3_9_1`,
 * and the version of intrinsics used: LlvmIntrinsics1 (explicit alignment <= 6)
 * or LlvmIntrinsics2 (>= 7).
 */
fn identifiers(ver: semver.Release) string[3]
{
	assert(ver !is null);
	idents: string[3];
	idents[0] = new "${IdentifierPrefix}${ver.major}";
	idents[1] = new "${IdentifierPrefix}${ver.major}_${ver.minor}";
	idents[2] = new "${IdentifierPrefix}${ver.major}_${ver.minor}_${ver.patch}";
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
// Copyright 2018-2019, Bernard Helyer.
// Copyright 2016-2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect LLVM toolchains.
 */
module battery.detect.llvm;

import core.exception;

import watt = [
	watt.io.file,
	watt.text.ascii,
	watt.text.string,
	watt.text.sink,
	watt.process];
import semver = watt.text.semver;

import conf = battery.detect.llvm.conf;

import battery.defines;
import battery.detect.llvm.logging;
import battery.util.path;


/*!
 * Which llvm commands that are needed.
 */
struct Needed
{
public:
	config, ar, clang, ld, link, wasm: bool;
}

/*!
 * Used as a argument when supplying a command on the command line.
 */
struct FromArgs
{
public:
	configCmd: string;    //!< The llvm-config command.
	configArgs: string[]; //!< The arguments for llvm-config.
	arCmd: string;        //!< The llvm-ar command.
	arArgs: string[];     //!< The arguments for llvm-ar.
	clangCmd: string;     //!< The clang command.
	clangArgs: string[];  //!< The arguments for clang.
	ldCmd: string;        //!< The ld.lld command.
	ldArgs: string[];     //!< The arguments for ld.lld.
	linkCmd: string;      //!< The lld-link command.
	linkArgs: string[];   //!< The arguments for lld-link.
	wasmCmd: string;      //!< The wasm-ld command.
	wasmArgs: string[];   //!< The arguments for wasm-ld.
}

/*!
 * Results from the detection code.
 */
struct Result
{
public:
	from: string;         //!< From where is this result?
	ver: semver.Release;  //!< LLVM Version.

	configCmd: string;    //!< The llvm-config command.
	configArgs: string[]; //!< The arguments for llvm-config.
	arCmd: string;        //!< The llvm-ar command.
	arArgs: string[];     //!< The arguments for llvm-ar.
	clangCmd: string;     //!< The clang command.
	clangArgs: string[];  //!< The arguments for clang.
	ldCmd: string;        //!< The ld.lld command.
	ldArgs: string[];     //!< The arguments for ld.lld.
	linkCmd: string;      //!< The lld-link command.
	linkArgs: string[];   //!< The arguments for lld-link.
	wasmCmd: string;      //!< The wasm-ld command.
	wasmArgs: string[];   //!< The arguments for wasm-ld.
}

/*!
 * Detect LLVM toolchains.
 */
fn detectFrom(path: string, confPaths: string[], out results: Result[]) bool
{
	log.info("Searching for LLVM toolchains.");
	result: Result;

	// First the configs.
	foreach (confPath; confPaths) {
		if (getFromConf(confPath, out result)) {
			results ~= result;
		}
	}

	// No suffix at all.
	if (getFromPath(path, null, out result)) {
		results ~= result;
	}

	// We do not scan the suffix paths on windows.
	suffixes := ["-10", "-9", "-8", "-7", "-6.0", "-5.0", "-4.0", "-3.9"];
	version (!Windows) foreach (suffix; suffixes) {
		if (getFromPath(path, suffix, out result)) {
			results ~= result;
		}
	}

	// Dump the info.
	foreach (ref r; results) {
		r.dump("Found");
	}

	return results.length != 0;
}

/*!
 * Detect llvm from arguments.
 */
fn detectFromArgs(ref fromArgs: FromArgs, out result: Result) bool
{
	// Arguments have the highest precedence.
	if (getFromArgs(ref fromArgs, out result)) {
		result.from = "arguments";
		result.dump("Found");
		return true;
	}
	return false;
}

/*!
 * Check the battery config for gdc.
 */
fn detectFromBatConf(ref batConf: BatteryConfig, out result: Result) bool
{
	log.info(new "Checking llvm from '${batConf.filename}'.");
	fromArgs: FromArgs;
	fromArgs.configCmd = batConf.llvmConfigCmd;
	fromArgs.clangCmd = batConf.llvmClangCmd;
	fromArgs.arCmd = batConf.llvmArCmd;
	fromArgs.linkCmd = batConf.llvmLinkCmd;
	fromArgs.wasmCmd = batConf.llvmWasmCmd;

	// Arguments have the highest precedence.
	if (getFromArgs(ref fromArgs, out result)) {
		result.from = "conf";
		result.dump("Found");
		return true;
	}

	return false;
}

/*!
 * Add extra arguments to the command, any given args are appended after the
 * extra arguments.
 */
fn addArgs(ref from: Result, arch: Arch, platform: Platform, out res: Result)
{
	res = from;
	if (res.clangCmd !is null) {
		res.clangArgs = getClangArgs(arch, platform) ~ res.clangArgs;
	}
}


private:

fn getFromConf(confPath: string, out res: Result) bool
{
	if (confPath is null) {
		return false;
	}

	if (!conf.parse(confPath, out res.ver, out res.clangCmd)) {
		return false;
	}

	res.from = "config";
	return true;
}

fn getFromArgs(ref fromArgs: FromArgs, out res: Result) bool
{
	// First see if we where given llvm-config or clang.
	res.configCmd = fromArgs.configCmd;
	if (!checkArgCmd(res.configCmd, "llvm-config")) {
		res.configCmd = null;
	}
	res.clangCmd = fromArgs.clangCmd;
	if (!checkArgCmd(res.clangCmd, "clang")) {
		res.clangCmd = null;
	}

	if (res.configCmd !is null) {
		res.ver = getVersionFromConfig(res.configCmd);
	} else if (res.clangCmd !is null) {
		res.ver = getVersionFromClang(res.clangCmd);
	}

	// Error out if llvm-config is needed and is missing.
	if (res.ver is null) {
		if (res.configCmd is null && res.clangCmd is null) {
			log.info("Was not given 'llvm-config' nor 'clang', skipping other commands.");
		} else {
			log.info(new "Could not determine LLVM version!\n\tllvm-config = '${res.configCmd}'\n\tclang = '${res.clangCmd}'");
		}
		return false;
	}

	if (checkArgCmd(fromArgs.arCmd, "llvm-ar")) {
		res.arCmd = fromArgs.arCmd;
	}

	if (checkArgCmd(fromArgs.ldCmd, "ld.lld")) {
		res.ldCmd = fromArgs.ldCmd;
	}

	if (checkArgCmd(fromArgs.linkCmd, "lld-link")) {
		res.linkCmd = fromArgs.linkCmd;
	}

	if (checkArgCmd(fromArgs.wasmCmd, "wasm-ld")) {
		res.wasmCmd = fromArgs.wasmCmd;
	}

	return true;
}

fn getFromPath(path: string, suffix: string, out res: Result) bool
{
	// First look for llvm-config or clang.
	res.configCmd = searchPath(path, "llvm-config" ~ suffix);
	res.clangCmd = searchPath(path, "clang" ~ suffix);

	if (res.configCmd !is null) {
		res.ver = getVersionFromConfig(res.configCmd);
	} else if (res.clangCmd !is null) {
		res.ver = getVersionFromClang(res.clangCmd);
	}

	// Error out if llvm-config is needed and is missing.
	if (res.ver is null) {
		if (res.configCmd is null && res.clangCmd is null) {
			log.info(new "Could not find 'llvm-config${suffix}' nor 'clang${suffix}' on the path, skipping other commands.");
		} else {
			log.info(new "Could not determine LLVM${suffix} version!\n\tllvm-config = '${res.configCmd}'\n\tclang = '${res.clangCmd}'");
		}
		return false;
	}

	res.arCmd = searchPath(path, "llvm-ar" ~ suffix);
	res.ldCmd = searchPath(path, "ld.lld" ~ suffix);
	res.linkCmd = searchPath(path, "lld-link" ~ suffix);
	res.wasmCmd = searchPath(path, "wasm-ld" ~ suffix);
	res.from = "path";
	return true;
}


/*
 *
 * Helpers
 *
 */

fn checkArgCmd(cmd: string, name: string) bool
{
	if (cmd is null) {
		return false;
	}

	if (watt.isFile(cmd)) {
		return true;
	}

	log.info(new "The ${name} command given as '${cmd}' does not exists!");
	return false;
}

fn getVersionFromConfig(cmd: string) semver.Release
{
	configOutput: string;
	configRetval: u32;
	ret: semver.Release;

	try {
		configOutput = watt.getOutput(cmd, ["--version"], ref configRetval);

		configOutput = watt.strip(configOutput);
		if (watt.endsWith(configOutput, "svn")) {
			// When you build from SVN you'll get 8.0.0svn (say). Trim the last part off.
			configOutput = configOutput[0 .. $-3];
		}

		ret = new semver.Release(configOutput);
	} catch (watt.ProcessException e) {
		log.info(new "Failed to run '${cmd}'\n\t${e.msg}");
	} catch (Exception e) {
		log.info(new "Failed to parse output from '${cmd}'\n\t${e.msg}");
	}

	return ret;
}

fn getVersionFromClang(cmd: string) semver.Release
{
	clangOutput: string;
	clangRetval: u32;
	ret: semver.Release;

	try {
		clangOutput = watt.getOutput(cmd, ["-v"], ref clangRetval);

		// Extract what we are looking for.
		line := extractClangVersionString(clangOutput);
		if (line is null) {
			log.info("Missing or invalid clang version line!");
			return null;
		}

		ret = new semver.Release(line);
	} catch (watt.ProcessException e) {
		log.info(new "Failed to run '${cmd}'\n\t${e.msg}");
	} catch (Exception e) {
		log.info(new "Failed to parse output from '${cmd}'\n\t${e.msg}");
	}

	return ret;
}

enum VersionLine = "clang version ";

fn extractClangVersionString(output: string) string
{
	line: string;
	foreach (l; watt.splitLines(watt.strip(output))) {
		if (watt.startsWith(l, VersionLine) == 0) {
			continue;
		}
		line = l;
		break;
	}

	if (line.length <= VersionLine.length) {
		return null;
	}

	// Cut off any junk at the end of the version string.
	index := VersionLine.length;
	while (index < line.length && !watt.isWhite(line[index])) {
		index++;
	}

	if (index == VersionLine.length) {
		return null;
	}

	return line[VersionLine.length .. index];
}


/*
 *
 * Arguments
 *
 */

fn getClangArgs(arch: Arch, platform: Platform) string[]
{
	return ["-target", getLLVMTargetString(arch, platform)];
}

//! configs used with LLVM tools, Clang and Volta.
fn getLLVMTargetString(arch: Arch, platform: Platform) string
{
	final switch (platform) with (Platform) {
	case MSVC:
		final switch (arch) with (Arch) {
		case X86: return null;
		case X86_64: return "x86_64-pc-windows-msvc";
		case ARMHF: return null;
		case AArch64: return null;
		}
	case OSX:
		final switch (arch) with (Arch) {
		case X86: return "i386-apple-macosx10.9.0";
		case X86_64: return "x86_64-apple-macosx10.9.0";
		case ARMHF: return null;
		case AArch64: return null;
		}
	case Linux:
		final switch (arch) with (Arch) {
		case X86: return "i386-pc-linux-gnu";
		case X86_64: return "x86_64-pc-linux-gnu";
		case ARMHF: return "armv7l-unknown-linux-gnueabihf";
		case AArch64: return "aarch64-unknown-linux-gnu";
		}
	case Metal:
		final switch (arch) with (Arch) {
		case X86: return "i686-pc-none-elf";
		case X86_64: return "x86_64-pc-none-elf";
		case ARMHF: return null;
		case AArch64: return null;
		}
	}
}

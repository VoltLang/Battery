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
	config, ar, clang, ld, link: bool;
}

/*!
 * Arguments to the detection code.
 */
struct Argument
{
public:
	arch: Arch;         //!< Arch we want to compile against.
	platform: Platform; //!< Platform we want to compile against.

	path: string;      //!< Path to search for commands.
	confPath: string;  //!< --llvmconf argument.

	configCmd: string; //!< The llvm-config command.
	arCmd: string;     //!< The llvm-ar command.
	clangCmd: string;  //!< The clang command.
	ldCmd: string;     //!< The ld.lld command.
	linkCmd: string;   //!< The lld-link command.
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
	configArgs: string[]; //!< The llvm-config argumetns.
	arCmd: string;        //!< The llvm-ar command.
	arArgs: string[];     //!< The llvm-ar arguments.
	clangCmd: string;     //!< The clang command.
	clangArgs: string[];  //!< The clang arguments.
	ldCmd: string;        //!< The ld.lld command.
	ldArgs: string[];     //!< The ld.lld arguments.
	linkCmd: string;      //!< The lld-link command.
	linkArgs: string[];   //!< The lld-link arguments.
}

/*!
 * Detect LLVM toolchains.
 */
fn detect(ref arg: Argument, out results: Result[]) bool
{
	log.info("Searching for LLVM toolchains.");
	result: Result;

	// Arguments have the highest precedence.
	if (getFromArgs(ref arg, out result)) {
		results ~= result;	
	}

	// Then the config.
	if (arg.getFromConf(out result)) {
		results ~= result;
	}

	// No suffix at all.
	if (getFromPath(ref arg, null, out result)) {
		results ~= result;
	}

	// We do not scan the suffix paths on windows.
	suffixes := ["-9", "-8", "-7", "-6.0", "-5.0", "-4.0", "-3.9"];
	version (!Windows) foreach (suffix; suffixes) {
		if (getFromPath(ref arg, suffix, out result)) {
			results ~= result;
		}
	}

	// Dump the info.
	foreach (ref r; results) {
		r.dump("Found");
	}

	return results.length != 0;
}


private:

fn getFromConf(ref arg: Argument, out res: Result) bool
{
	if (arg.confPath is null) {
		log.info("No llvm config file was given (--llvmconf), skipping.");
		return false;
	}

	if (!conf.parse(arg.confPath, out res.ver, out res.clangCmd)) {
		return false;
	}

	res.from = "config";
	res.clangArgs = getClangArgs(ref arg);
	return true;
}

fn getFromArgs(ref arg: Argument, out res: Result) bool
{
	if (checkArgCmd(arg.configCmd, "llvm-config")) {
		res.configCmd = arg.configCmd;
	} else {
		log.info("The llvm-config command was not given, skipping all other given commands.");
		return false;
	}

	res.ver = getVersionFromConfig(res.configCmd);
	if (res.ver is null) {
		return false;
	}

	if (checkArgCmd(arg.arCmd, "llvm-ar")) {
		res.arCmd = arg.arCmd;
	}

	if (checkArgCmd(arg.clangCmd, "clang")) {
		res.clangCmd = arg.clangCmd;
		res.clangArgs = getClangArgs(ref arg);
	}

	if (checkArgCmd(arg.ldCmd, "ld.lld")) {
		res.ldCmd = arg.ldCmd;
	}

	if (checkArgCmd(arg.linkCmd, "lld-link")) {
		res.linkCmd = arg.linkCmd;
	}

	res.from = "arguments";
	return true;
}

fn getFromPath(ref arg: Argument, suffix: string, out res: Result) bool
{
	res.configCmd = searchPath(arg.path, "llvm-config" ~ suffix);

	if (res.configCmd is null) {
		if (suffix is null) {
			log.info(new "Could not find 'llvm-config${suffix}' on the path, skipping other commands.");
		} else {
			log.info(new "Could not find 'llvm-config${suffix}' on the path, skipping other commands from llvm${suffix}.");
		}
		return false;
	}

	res.ver = getVersionFromConfig(res.configCmd);
	if (res.ver is null) {
		return false;
	}

	res.arCmd = searchPath(arg.path, "llvm-ar" ~ suffix);
	res.clangCmd = searchPath(arg.path, "clang" ~ suffix);
	res.ldCmd = searchPath(arg.path, "ld.lld" ~ suffix);
	res.linkCmd = searchPath(arg.path, "lld-link" ~ suffix);

	if (res.clangCmd !is null) {
		res.clangArgs = getClangArgs(ref arg);
	}

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

	try {
		configOutput = watt.getOutput(cmd, ["--version"], ref configRetval);

		configOutput = watt.strip(configOutput);
		if (watt.endsWith(configOutput, "svn")) {
			// When you build from SVN you'll get 8.0.0svn (say). Trim the last part off.
			configOutput = configOutput[0 .. $-3];
		}

		return new semver.Release(configOutput);
	} catch (watt.ProcessException e) {
		log.info(new "Failed to run llvm-config ${cmd}\n\t{e.msg}");
		return null;
	} catch (Exception e) {
		log.info(new "Failed to parse output from '${cmd}'\n\t{e.msg}");
		return null;
	}

	return null;
}


/*
 *
 * Arguments
 *
 */

fn getClangArgs(ref arg: Argument) string[]
{
	return ["-target", arg.getLLVMTargetString()];
}

//! configs used with LLVM tools, Clang and Volta.
fn getLLVMTargetString(ref arg: Argument) string
{
	final switch (arg.platform) with (Platform) {
	case MSVC:
		final switch (arg.arch) with (Arch) {
		case X86: return null;
		case X86_64: return "x86_64-pc-windows-msvc";
		}
	case OSX:
		final switch (arg.arch) with (Arch) {
		case X86: return "i386-apple-macosx10.9.0";
		case X86_64: return "x86_64-apple-macosx10.9.0";
		}
	case Linux:
		final switch (arg.arch) with (Arch) {
		case X86: return "i386-pc-linux-gnu";
		case X86_64: return "x86_64-pc-linux-gnu";
		}
	case Metal:
		final switch (arg.arch) with (Arch) {
		case X86: return "i686-pc-none-elf";
		case X86_64: return "x86_64-pc-none-elf";
		}
	}
}

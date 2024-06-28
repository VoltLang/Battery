// Copyright 2016-2024, Bernard Helyer.
// Copyright 2016-2024, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect and find the ldc command.
 */
module battery.detect.ldc;

import core.exception;

import watt = [
	watt.io.file,
	watt.text.ascii,
	watt.text.string,
	watt.text.sink,
	watt.process];
import semver = watt.text.semver;

import battery.defines;
import battery.util.path;

static import battery.util.log;


/*!
 * Used as an argument when supplying a command on the command line.
 */
struct FromArgs
{
	cmd: string;     //!< The path to the command.
	args: string[];  //!< The arguments to supply to the command.
}

/*!
 * The result of the detection.
 */
struct Result
{
	ver: semver.Release;  //!< If non-null the version of the command.
	from: string;         //!< Either "path", "args", "conf", or null.

	cmd: string;          //!< The path to the command.
	args: string[];       //!< The arguments to supply to the command.
}

/*!
 * Find LDC commands from the environment via PATH.
 *
 * @Param path If non-null, the value of the PATH environment variable.
 * @Param results After call, will contain found commands (if any).
 * @Returns `false` if no results were found.
 */
fn detectFromPath(path: string, out results: Result[]) bool
{
	res: Result;
	log.info("Detecting LDC from path.");

	if (fromPath(path, out res)) {
		results ~= res;
		res.dump("Found");
	}

	return results.length != 0;
}

/*!
 * Validate LDC command given to us via arguments.
 *
 * @Param arg The LDC command given via the arguments.
 * @Param result Will be filled out with the details from `arg` on success.
 * @Returns `false` if the arguments didn't have an LDC command or it could not be found.
 */
fn detectFromArgs(ref arg: FromArgs, out result: Result) bool
{
	if (arg.cmd is null) {
		return false;
	}

	log.info("Checking LDC from args.");

	if (!checkArgCmd(ref log, arg.cmd, "ldc")) {
		return false;
	}

	result.ver = getVersionFromLdc(arg.cmd);
	if (result.ver is null) {
		return false;
	}

	result.from = "args";
	result.cmd = arg.cmd;
	result.args = arg.args;
	result.dump("Found");
	return true;
}

/*!
 * Validate LDC command given to us via battery config.
 *
 * @Param batConf The battery config to check.
 * @Param result Filled in with the command from `batConf` on success.
 * @Returns `false` if batConf didn't contain an LDC command, or it couldn't be found.
 */
fn detectFromBatConf(ref batConf: BatteryConfig, out result: Result) bool
{
	if (batConf.ldcCmd is null) {
		return false;
	}

	log.info(new "Checking LDC from '${batConf.filename}'.");

	if (!checkArgCmd(ref log, batConf.ldcCmd, "ldc")) {
		return false;
	}

	result.ver = getVersionFromLdc(batConf.ldcCmd);
	if (result.ver is null) {
		return false;
	}

	result.from = "conf";
	result.cmd = batConf.ldcCmd;
	result.dump("Found");
	return true;
}

/*!
 * Add needed arguments to a Result.
 * Added arguments are added before any arguments present in the input Result.
 * 
 * @Param from The input result.
 * @Param arch The target architecture.
 * @Param platform The target platform.
 * @Param res The output result.
 */
fn addArgs(ref from: Result, arch: Arch, platform: Platform, out res: Result)
{
	res.from = from.from;
	res.cmd = from.cmd;
	if (target := getTargetString(arch)) {
		res.args = [target] ~ from.args;
	}
}

private:

/*!
 * So we get the right prefix on log messages.
 */	
global log: battery.util.log.Logger = {"detect.ldc"};

fn dump(ref res: Result, message: string)
{
	ss: watt.StringSink;

	ss.sink(message);
	watt.format(ss.sink, "\n\tver = %s", res.ver);
	watt.format(ss.sink, "\n\tfrom = %s", res.from);
	watt.format(ss.sink, "\n\tcmd = %s", res.cmd);
	watt.format(ss.sink, "\n\targs = [");
	foreach (arg; res.args) {
		ss.sink("\n\t\t");
		ss.sink(arg);
	}
	ss.sink("]");

	log.info(ss.toString());
}

fn fromPath(path: string, out res: Result) bool
{
	res.cmd = searchPath(path, "ldc2");
	if (res.cmd is null) {
		log.info("Failed to find 'ldc2' oon path.");
	}

	res.ver = getVersionFromLdc(res.cmd);
	if (res.ver is null) {
		return false;
	}

	res.from = "path";
	log.info(new "Found ldc '${res.cmd}'");
	return true;
}

/*!
 * Get a flag that outputs the target arch.
 */
fn getTargetString(arch: Arch) string
{
	final switch (arch) with (Arch) {
	case X86: return "--march=x86";
	case X86_64: return "--march=x86-64";
	case ARMHF: assert(false);
	case AArch64: return "--march=aarch64";
	}
}

fn getVersionFromLdc(cmd: string) semver.Release
{
	ldcOutput: string;
	line: string;
	ldcRetval: u32;
	ret: semver.Release;
	
	try {
		ldcOutput = watt.getOutput(cmd, ["-v"], ref ldcRetval);

		line = extractLdcVersionString(ldcOutput);
		if (line is null) {
			log.info("Couldn't extract LDC version.");
			return null;
		}

		ret = new semver.Release(line);
	} catch (watt.ProcessException e) {
		log.info(new "Failed to run '${cmd}'\n\t${e.msg}");
	} catch (Exception e) {
		log.info(new "Failed to parse output from '${cmd}' '${line}'\n\tf${e.msg}");
	}

	return ret;
}

/*!
 * Extracts a version string from the output of "ldc2 -v".
 *
 * At time of writing, ldc2's -v output was as follows:
 * $ ldc2 -v
 * binary    /opt/homebrew/Cellar/ldc/1.38.0/bin/ldc2
 * version   1.38.0 (DMD v2.108.1, LLVM 18.1.6)
 * config    /opt/homebrew/Cellar/ldc/1.38.0/etc/ldc2.conf (arm64-apple-darwin23.5.0)
 * Error: No source files
 *
 * extractLdcVersionString, given the above output, should return "1.38.0".
 */

enum VersionLineStart = "version";

fn extractLdcVersionString(output: string) string
{
	line: string;

	foreach (l; watt.splitLines(watt.strip(output))) {
		if (watt.startsWith(l, VersionLineStart)) {
			line = l;
			break;
		}
	}

	// We did not find any version line.
	if (line is null || line.length <= VersionLineStart.length) {
		return null;
	}

	// Remove the "version" from the start.
	line = line[VersionLineStart.length .. $];
	line = watt.stripLeft(line);
	
	// At this point we should be at the start of the version string.
	if (line.length == 0 || !watt.isDigit(line[0])) {
		return null;
	}

	// Get the index of the character one past the end of the version string.
	endIndex := watt.indexOf(line, ' ');
	if (endIndex == -1) {
		return null;
	}

	return line[0 .. endIndex];
}
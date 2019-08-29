// Copyright 2016-2019, Bernard Helyer.
// Copyright 2016-2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect and find the gdc command.
 */
module battery.detect.gdc;

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
 * Used as a argument when supplying a command on the command line.
 */
struct FromArgs
{
	cmd: string;
	args: string[];
}

/*!
 * The result of the dection, also holds any extra arguments to get NASM
 * to output in the correct format.
 */
struct Result
{
	ver: semver.Release;
	from: string;

	cmd: string;
	args: string[];
}

/*!
 * Detect and find the nasm command.
 */
fn detectFromPath(path: string, out results: Result[]) bool
{
	res: Result;
	log.info("Detecting GDC fron path.");

	// Command without any suffix.
	if (fromPath(path, out res)) {
		results ~= res;
	}

	// Try some known suffixes.
	suffixes := ["-6", "-7", "-8", "-9"];
	foreach (suffix; suffixes) {
		if (fromPath(path, out res, suffix)) {
			results ~= res;
		}
	}

	// Dump all found.
	foreach (ref result; results) {
		result.dump("Found");
	}

	return results.length != 0;
}

/*!
 * Detect gdc from arguments.
 */
fn detectFromArgs(ref arg: FromArgs, out result: Result) bool
{
	if (arg.cmd is null) {
		return false;
	}

	log.info("Checking gdc from args.");

	if (!checkArgCmd(ref log, arg.cmd, "gdc")) {
		return false;
	}

	result.ver = getVersionFromGdc(arg.cmd);
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
 * Check the battery config for gdc.
 */
fn detectFromBatConf(ref batConf: BatteryConfig, out result: Result) bool
{
	if (batConf.gdcCmd is null) {
		return false;
	}

	log.info(new "Checking gdc from '${batConf.filename}'.");

	if (!checkArgCmd(ref log, batConf.gdcCmd, "gdc")) {
		return false;
	}

	result.ver = getVersionFromGdc(batConf.gdcCmd);
	if (result.ver is null) {
		return false;
	}

	result.from = "conf";
	result.cmd = batConf.gdcCmd;
	result.dump("Found");
	return true;
}

/*!
 * Add extra arguments to the command, any given args are appended after the
 * extra arguments.
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
 * So we get the right prefix on logged messages.
 */
global log: battery.util.log.Logger = {"detect.gdc"};

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

fn fromPath(path: string, out res: Result, suffix: string = null) bool
{
	res.cmd = searchPath(path, new "gdc${suffix}");
	if (res.cmd is null) {
		log.info(new "Failed to find 'gdc${suffix}' on path.");
		return false;
	}

	res.ver = getVersionFromGdc(res.cmd);
	if (res.ver is null) {
		return false;
	}

	res.from = "path";
	log.info(new "Found gdc${suffix} '${res.cmd}'");
	return true;
}

/*!
 * Returns the format to be outputed for this configuration.
 */
fn getTargetString(arch: Arch) string
{
	final switch (arch) with (Arch) {
	case X86: return "-m32";
	case X86_64: return "-m64";
	case ARMHF: return null;
	case AArch64: return null;
	}
}

fn getVersionFromGdc(cmd: string) semver.Release
{
	gdcOutput: string;
	line: string;
	gdcRetval: u32;
	ret: semver.Release;

	try {
		gdcOutput = watt.getOutput(cmd, ["-v"], ref gdcRetval);

		// Extract what we are looking for.
		line = extractGdcVersionString(gdcOutput);
		if (line is null) {
			log.info("Missing or invalid gdc version line!");
			return null;
		}

		ret = new semver.Release(line);
	} catch (watt.ProcessException e) {
		log.info(new "Failed to run '${cmd}'\n\t${e.msg}");
	} catch (Exception e) {
		log.info(new "Failed to parse output from '${cmd}' '${line}'\n\t${e.msg}");
	}

	return ret;
}

enum VersionLine = "gcc version ";

fn extractGdcVersionString(output: string) string
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

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
 * A struct holding arguments for the dection code.
 */
struct Argument
{
	path: string;   //!< Path to search.
	cmd: string;    //!< Was NASM given from command line.
	args: string[]; //!< The extra arguments from command line.
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
fn detect(ref arg: Argument, out results: Result[]) bool
{
	res: Result;
	log.info("Detecting GDC");

	// See if we where given any.
	if (fromArgs(ref arg, out res)) {
		results ~= res;
	}

	// Command without any suffix.
	if (fromPath(ref arg, out res)) {
		results ~= res;
	}

	// Try some known suffixes.
	suffixes := ["-6", "-7", "-9"];
	foreach (suffix; suffixes) {
		if (fromPath(ref arg, out res, suffix)) {
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
 * Add extra arguments to the command, any given args are appended after the
 * extra arguments.
 */
fn addArgs(ref res: Result, arch: Arch, platform: Platform)
{
	res.args = [getTargetString(arch)] ~ res.args;
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

fn fromArgs(ref arg: Argument, out res: Result) bool
{
	if (!checkArgCmd(arg.cmd, "gdc")) {
		return false;
	}

	res.ver = getVersionFromGdc(arg.cmd);
	if (res.ver is null) {
		return false;
	}

	// Everything is ok, continue.
	res.from = "args";
	res.cmd = arg.cmd;
	res.args = arg.args;
	return true;
}

fn fromPath(ref arg: Argument, out res: Result, suffix: string = null) bool
{
	res.cmd = searchPath(arg.path, new "gdc${suffix}");
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

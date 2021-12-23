// Copyright 2016-2018, Bernard Helyer.
// Copyright 2016-2018, Jakob Bornecrantz.
// Copyright 2018-2021, Collabora, Ltd.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect and find the curl command.
 */
module battery.detect.curl;

import core.exception;

import watt = [
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
 * Detect and find the curl command.
 */
fn detectFromPath(path: string, out results: Result[]) bool
{
	res: Result;
	log.info("Detecting curl from path.");

	// Command without any suffix.
	if (fromPath(path, out res)) {
		results ~= res;
	}

	// Dump all found.
	foreach (ref result; results) {
		result.dump("Found");
	}

	return results.length != 0;
}

/*!
 * Detect curl from arguments.
 */
fn detectFromArgs(ref arg: FromArgs, out result: Result) bool
{
	if (arg.cmd is null) {
		return false;
	}

	log.info("Checking curl from args.");

	if (!checkArgCmd(ref log, arg.cmd, "curl")) {
		return false;
	}

	result.ver = getVersionFromCurl(arg.cmd);
	if (result.ver is null) {
		return false;
	}

	result.from = "args";
	result.cmd = arg.cmd;
	result.args = arg.args;
	result.dump("Found");
	return true;
}


private:

/*!
 * So we get the right prefix on logged messages.
 */
global log: battery.util.log.Logger = {"detect.curl"};

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

/*!
 * Search the path.Pretty print the result.
 */
fn fromPath(path: string, out res: Result) bool
{
	res.cmd = searchPath(path, "curl");
	if (res.cmd is null) {
		log.info("Failed to find 'curl' on path.");
		return false;
	}

	res.ver = getVersionFromCurl(res.cmd);
	if (res.ver is null) {
		return false;
	}

	res.from = "path";
	log.info(new "Found curl '${res.cmd}'");
	return true;
}

fn getVersionFromCurl(cmd: string) semver.Release
{
	curlOutput: string;
	line: string;
	curlRetval: u32;
	ret: semver.Release;

	try {
		curlOutput = watt.getOutput(cmd, ["-V"], ref curlRetval);

		// Extract what we are looking for.
		line = extractCurlVersionString(curlOutput);
		if (line is null) {
			log.info("Missing or invalid curl version line!");
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

enum VersionLines = ["curl "];

fn extractCurlVersionString(output: string) string
{
	line: string;
	versionLine: string;

	foreach (l; watt.splitLines(watt.strip(output))) {
		foreach (ver; VersionLines) {
			if (watt.startsWith(l, ver) == 0) {
				continue;
			}

			versionLine = ver;
		}

		// We did not find any version line.
		if (versionLine is null) {
			continue;
		}

		line = l;
		break;
	}

	if (line.length <= versionLine.length) {
		return null;
	}

	// Cut off any junk at the end of the version string.
	index := versionLine.length;
	while (index < line.length && !watt.isWhite(line[index])) {
		index++;
	}

	if (index == versionLine.length) {
		return null;
	}

	return line[versionLine.length .. index];
}

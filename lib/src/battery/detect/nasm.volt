// Copyright 2016-2019, Bernard Helyer.
// Copyright 2016-2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect and find the nasm command.
 */
module battery.detect.nasm;

import watt = [watt.text.sink, watt.text.string];

static import battery.util.log;

import battery.defines;
import battery.util.path;

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
	log.info("Detecting nasm on path.");

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

fn detectFromBatConf(ref batConf: BatteryConfig, out result: Result) bool
{
	if (batConf.nasmCmd is null) {
		return false;
	}

	log.info(new "Checking nasm from '${batConf.filename}'.");

	if (!checkArgCmd(ref log, batConf.nasmCmd, "nasm")) {
		return false;
	}

	result.from = "conf";
	result.cmd = batConf.nasmCmd;
	result.dump("Found");
	return true;
}

/*!
 * Detect nasm from arguments.
 */
fn detectFromArgs(ref arg: FromArgs, out result: Result) bool
{
	if (arg.cmd is null) {
		return false;
	}

	log.info("Checking nasm from args.");

	if (!checkArgCmd(ref log, arg.cmd, "nasm")) {
		return false;
	}

	result.from = "args";
	result.cmd = arg.cmd;
	result.args = arg.args;
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
	res.args = ["-f", getFormatString(arch, platform)] ~ from.args;
}


private:

/*!
 * So we get the right prefix on logged messages.
 */
global log: battery.util.log.Logger = {"detect.nasm"};

fn dump(ref res: Result, message: string)
{
	ss: watt.StringSink;

	ss.sink(message);
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
	res.cmd = searchPath(path, "nasm");
	if (res.cmd is null) {
		log.info("Failed to find 'nasm' on path.");
		return false;
	}

	res.from = "path";
	log.info(new "Found nasm '${res.cmd}'");
	return true;
}

/*!
 * Returns the format to be outputed for this configuration.
 */
fn getFormatString(arch: Arch, platform: Platform) string
{
	final switch (platform) with (Platform) {
	case MSVC:
		final switch (arch) with (Arch) {
		case X86: return "win32";
		case X86_64: return "win64";
		case AArch64: assert(false);
		}
	case OSX:
		final switch (arch) with (Arch) {
		case X86: return "macho32";
		case X86_64: return "macho64";
		case AArch64: assert(false);
		}
	case Linux:
		final switch (arch) with (Arch) {
		case X86: return "elf32";
		case X86_64: return "elf64";
		case AArch64: assert(false);
		}
	case Metal:
		final switch (arch) with (Arch) {
		case X86: return "elf32";
		case X86_64: return "elf64";
		case AArch64: assert(false);
		}
	}
}

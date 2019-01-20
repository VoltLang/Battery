// Copyright 2016-2019, Bernard Helyer.
// Copyright 2016-2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect and find the nasm command.
 *
 * @todo Remove lib property.
 * @todo Move expansions of libs and includes into here.
 */
module battery.detect.nasm;

import watt = [watt.text.sink, watt.text.string];

static import battery.util.log;

import battery.defines;
import path = battery.detect.path;


/*!
 * A struct holding arguments for the dection code.
 */
struct Argument
{
	arch: Arch;         //!< Arch we want nasm to compile against.
	platform: Platform; //!< Platform we want nasm to compile against.

	path: string;       //!< Path to search.
	argCmd: string;     //!< Was NASM given from command line.
	argArgs: string[];  //!< The extra arguments from command line.
}

/*!
 * The result of the dection, also holds any extra arguments to get NASM
 * to output in the correct format.
 */
struct Result
{
	cmd: string;
	args: string[];
}

/*!
 * Detect and find the nasm command.
 */
fn detect(ref arg: Argument, out res: Result) bool
{
	log.info("Detecting NASM");

	if (arg.argCmd !is null) {
		res.cmd = arg.argCmd;
		res.args = arg.getBaseArgs() ~ arg.argArgs;
		res.dump("Got NASM from arguments");
		return true;
	}

	res.cmd = path.detect(arg.path, "nasm");
	res.args = arg.getBaseArgs();

	if (res.cmd is null) {
		log.info("Failed to find NASM");
		return false;
	} else {
		log.info(new "Found NASM '${res.cmd}'");
		return true;
	}
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
 * Returns the list of arguments needed to make NASM output the correct format.
 */
fn getBaseArgs(ref arg: Argument) string[]
{
	return ["-f", arg.getFormatString()];
}

/*!
 * Returns the format to be outputed for this configuration.
 */
fn getFormatString(ref arg: Argument) string
{
	final switch (arg.platform) with (Platform) {
	case MSVC:
		final switch (arg.arch) with (Arch) {
		case X86: return "win32";
		case X86_64: return "win64";
		}
	case OSX:
		final switch (arg.arch) with (Arch) {
		case X86: return "macho32";
		case X86_64: return "macho64";
		}
	case Linux:
		final switch (arg.arch) with (Arch) {
		case X86: return "elf32";
		case X86_64: return "elf64";
		}
	case Metal:
		final switch (arg.arch) with (Arch) {
		case X86: return "elf32";
		case X86_64: return "elf64";
		}
	}
}

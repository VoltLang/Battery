// Copyright 2016-2019, Bernard Helyer.
// Copyright 2016-2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect and find the volta command.
 */
module battery.detect.volta;

import watt = [watt.text.format, watt.text.sink];

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
 * The result of the dection, also holds any extra arguments to get volta
 * to output in the correct format.
 */
struct Result
{
	from: string;

	cmd: string;
	args: string[];
}

/*!
 * Detect rdmd from arguments.
 */
fn detectFromArgs(ref arg: FromArgs, out result: Result) bool
{
	if (arg.cmd is null) {
		return false;
	}

	log.info("Checking Volta from args.");

	if (!checkArgCmd(ref log, arg.cmd, "volta")) {
		return false;
	}

	result.from = "args";
	result.cmd = arg.cmd;
	result.args = arg.args;
	result.dump("Found");
	return true;
}

/*!
 * Check the battery config for rdmd.
 */
fn detectFromBatConf(ref batConf: BatteryConfig, out result: Result) bool
{
	if (batConf.voltaCmd is null) {
		return false;
	}

	log.info(new "Checking rdmd from '${batConf.filename}'.");

	if (!checkArgCmd(ref log, batConf.voltaCmd, "volta")) {
		return false;
	}

	result.from = "conf";
	result.cmd = batConf.voltaCmd;
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
	res.args = from.args;
}


private:

/*!
 * So we get the right prefix on logged messages.
 */
global log: battery.util.log.Logger = {"detect.volta"};

/*!
 * Pretty print the result.
 */
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

// Copyright 2016-2019, Bernard Helyer.
// Copyright 2016-2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Code to search for commands on the path.
 */
module battery.detect.path;

import watt = [watt.text.sink, watt.text.string, watt.path];

static import battery.util.log;

import battery.util.path;
import battery.detect.path;


/*!
 * A struct holding arguments for the dection code.
 */
struct Argument
{
	cmd: string;  //!< Command to search for.
	path: string; //!< Path to search.
}

/*!
 * The result of the search.
 */
struct Result
{
	cmd: string;
}

/*!
 * Small helper function, return the command if it was found.
 */
fn detect(path: string, cmd: string) string
{
	res: Result;
	arg: Argument;
	arg.path = path;
	arg.cmd = cmd;
	if (arg.detect(out res)) {
		return res.cmd;
	} else {
		return null;
	}
}

/*!
 * Main detect function, searches the path and writes out if it can't find it.
 */
fn detect(ref arg: Argument, out res: Result) bool
{
	cmd := searchPath(arg.cmd.appendExeIfNeeded(), arg.path);
	if (cmd is null) {
		arg.dump("Failed to find command!");
		return false;
	}

	res.cmd = cmd;
	return true;
}

private:


/*!
 * So we get the right prefix on logged messages.
 */
global log: battery.util.log.Logger = {"detect.path"};

/*!
 * Dump the arguments and write out the given message.
 */
fn dump(ref arg: Argument, message: string)
{
	ss: watt.StringSink;

	ss.sink(message);
	watt.format(ss.sink, "\n\tcmd = '%s'", arg.cmd);
	watt.format(ss.sink, "\n\tpath = [");
	foreach (p; watt.split(arg.path, watt.pathSeparator[0])) {
		ss.sink("\n\t\t'");
		ss.sink(p);
		if (watt.exists(p)) {
			ss.sink("' (exists)");
		} else {
			ss.sink("' (not found)");
		}
	}
	ss.sink("]");

	log.info(ss.toString());
}

/*!
 * Usefull for windows where a .exe ending is needed.
 */
fn appendExeIfNeeded(cmd: string) string
{
	version (Windows) if (!watt.endsWith(cmd, ".exe")) {
		return cmd ~ ".exe";
	}
	return cmd;
}

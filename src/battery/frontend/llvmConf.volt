// Copyright © 2018, Bernard Helyer.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/*!
 * Code for handling a small config file that declares information regarding LLVM.
 *
 * This is for building the compiler on Windows systems, where we can't use
 * `llvm-config`.
 */
module battery.frontend.llvmConf;

import battery.interfaces;
import     io = watt.io;
import   toml = watt.toml;
import getopt = watt.text.getopt;
import semver = watt.text.semver;
import   file = watt.io.file;
import   path = [watt.path, watt.text.path];

enum DefaultLlvmTomlName = "llvm.toml";

fn scan(args: string[]) bool
{
	foreach (arg; args) {
		if (arg[0] == '-') {
			continue;
		}
		if (scan(arg)) {
			return true;
		}
	}
	return false;
}

fn scan(fpath: string) bool
{
	proposedPath := path.concatenatePath(fpath, DefaultLlvmTomlName);
	if (file.exists(proposedPath)) {
		parse(proposedPath);
		return true;
	}
	return false;
}

/*!
 * Parse llvmConf-related command line arguments.
 *
 * This parses the argument `--llvmconf` from `args`.
 */
fn parseArguments(ref args: string[])
{
	configPath: string;
	if (getopt.getopt(ref args, "llvmconf", ref configPath)) {
		parse(configPath);
	}
}

@property fn parsed() bool
{
	return gParsed;
}

@property fn llvmVersion() semver.Release
{
	assert(gParsed);
	return gLlvmVersion;
}

@property fn clangPath() string
{
	assert(gParsed);
	return gClangPath;
}

/*!
 * Given a path to a llvm.conf file, retrieve the contained values.
 *
 * The config file is a small [TOML](https://github.com/toml-lang/toml) file.
 * `llvmVersion` is a [semver](https://semver.org/) string.
 * `clangPath` is a string with a path to the clang executable.
 *
 * @Param confPath The path to the config file.
 */
fn parse(confPath: string)
{
	if (gParsed) {
		return;
	}
	confStr := cast(string)file.read(confPath);
	value   := toml.parse(confStr);
	gLlvmVersion = new semver.Release(value["llvmVersion"].str());
	gClangPath   = value["clangPath"].str();
	gParsed = true;
}

private:

global gParsed: bool;
global gLlvmVersion: semver.Release;
global gClangPath: string;

// Copyright 2018, Bernard Helyer.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Code for handling a small config file that declares information regarding LLVM.
 *
 * This is for building the compiler on Windows systems, where we can't use
 * `llvm-config`.
 */
module battery.detect.llvm.conf;

import core.exception;

import   toml = watt.toml;
import semver = watt.text.semver;
import   file = watt.io.file;
import   path = [watt.path, watt.text.path];

import battery.detect.llvm.logging;


/*!
 * Given a path to a llvm.conf file, retrieve the contained values.
 *
 * The config file is a small [TOML](https://github.com/toml-lang/toml) file.
 * `llvmVersion` is a [semver](https://semver.org/) string.
 * `clangPath` is a string with a path to the clang executable.
 *
 * @Param confPath The path to the config file.
 */
fn parse(confPath: string, out ver: semver.Release, out clangCmd: string) bool
{
	if (confPath is null) {
		return false;
	}

	log.info(new "Reading LLVM config from '${confPath}'");

	if (!file.isFile(confPath)) {
		log.info("Error file does not exists or is a folder!");
		return false;
	}

	confStr: string;
	try {
		confStr = cast(string) file.read(confPath);
	} catch (Exception e) {
		log.info(new "Error failed to read file!\n\t${e.msg}");
		return false;
	}

	try {
		value := toml.parse(confStr);
		ver = new semver.Release(value["llvmVersion"].str());
		clangCmd = value["clangPath"].str();
	} catch (Exception e) {
		log.info(new "Failed to parse file!\n\t${e.msg}");
		return false;
	}

	if (clangCmd is null) {
		log.info("Error the value clangPath was not specified.");
		return false;
	}
	return true;
}

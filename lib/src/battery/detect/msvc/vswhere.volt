// Copyright 2018-2019, Bernard Helyer.
// Copyright 2016-2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect LLVM toolchains.
 */
module battery.detect.msvc.vswhere;

version (Windows):

import core.exception;

import watt = [
	watt.io.file,
	watt.text.string,
	watt.text.path,
	watt.process];
import semver = watt.text.semver;

import battery.detect.msvc;
import battery.detect.msvc.util;
import battery.detect.msvc.logging;
import battery.detect.msvc.windows;

import battery.util.path;


fn fromVSWhere(out result: Result) bool
{
	log.info("Trying to find MSVC with vswhere.exe");

	if (!result.getInstallDir()) {
		return false;
	}

	if (!result.getUniversalSdkInformation()) {
		return false;
	}

	result.ver = VisualStudioVersion.V2017;
	result.from = "vswhere";
	result.addLinkAndCL("bin\\Hostx64\\x64");
	result.dump("Found");

	return true;
}


/*
 *
 * Helpers
 *
 */

enum InstallDirArgs = [
	"-latest",
	"-products", "*",
	"-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
	"-property", "installationPath"];

fn getInstallDir(ref result: Result) bool
{
	// @TODO look up env var ProgramFiles(x86)
	cmd := "C:\\Program Files (x86)\\Microsoft Visual Studio\\Installer\\vswhere.exe";
	if (!watt.exists(cmd)) {
		log.info(new "Didn't find vswhere.exe looked here: '${cmd}");
		return false;
	} else {
		log.info(new "Found vswhere.exe '${cmd}'");
	}

	installationPath: string;
	if (!getOutput(cmd, InstallDirArgs, out installationPath)) {
		return false;
	}

	if (!getVersionInstallDir(installationPath, out result.vcInstallDir)) {
		return false;
	}

	return true;
}

fn getOutput(cmd: string, args: string[], out output: string) bool
{
	retval: u32;
	try {
		output = watt.getOutput(cmd, args, ref retval);

		output = watt.strip(output);
		retval = 0;
	} catch (watt.ProcessException e) {
		log.info(new "Failed to run '${cmd}'\n\t${e.msg}");
		retval = 1;
	}

	return retval == 0;
}

fn getVersionInstallDir(input: string, out path: string) bool
{
	toolsVersionPath := watt.concatenatePath(input, "VC\\Auxiliary\\Build\\Microsoft.VCToolsVersion.default.txt");
	if (!watt.exists(toolsVersionPath)) {
		log.info(new "Tools version file does not exists: '${toolsVersionPath}'");
		return false;
	}

	verstr := watt.strip(cast(string)watt.read(toolsVersionPath));
	path = watt.concatenatePath(input, new "VC\\Tools\\MSVC\\${verstr}");
	if (!watt.isDir(path)) {
		log.info(new "Install path is not a dir: '${path}'");
		return false;
	}

	return true;
}

// Copyright 2018-2019, Bernard Helyer.
// Copyright 2016-2012, Jakob Bornecrantz.
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

	if (!result.getVSWhere()) {
		return false;
	}

	if (!result.getInstallDir()) {
		return false;
	}

	if (!result.getUniversalSdkInformation()) {
		return false;
	}

	if (!result.getProductLineVersion()) {
		// Ok to fail.
	}

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


/*!
 * Run a command grab the output to stdout and strip any whitespace from it.
 */
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

enum InstallDirArgs = [
	"-latest",
	"-products", "*",
	"-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
	"-property", "installationPath",
];

fn getVSWhere(ref result: Result) bool
{
	// @TODO look up env var ProgramFiles(x86)
	cmd := "C:\\Program Files (x86)\\Microsoft Visual Studio\\Installer\\vswhere.exe";
	if (!watt.exists(cmd)) {
		log.info(new "Didn't find vswhere.exe looked here: '${cmd}");
		return false;
	} else {
		log.info(new "Found vswhere.exe '${cmd}'");
	}

	result.vsWhereCmd = cmd;

	return true;
}

fn getInstallDir(ref result: Result) bool
{
	installationPath: string;
	if (!getOutput(result.vsWhereCmd, InstallDirArgs, out installationPath)) {
		return false;
	}

	if (!getVersionInstallDir(installationPath, out result.vcInstallDir)) {
		return false;
	}

	return true;
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

enum ProductLineVersionArgs = [
	"-latest",
	"-products", "*",
	"-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
	"-property", "catalog_productLineVersion",
];

fn getProductLineVersion(ref result: Result) bool
{
	verstr: string;
	if (!getOutput(result.vsWhereCmd, ProductLineVersionArgs, out verstr)) {
		return false;
	}

	if (!parseProductLineVersion(verstr, out result.ver)) {
		return false;
	}

	return true;
}

fn parseProductLineVersion(verstr: string, out ver: VisualStudioVersion) bool
{
	switch (verstr) {
	case "2015": ver = VisualStudioVersion.V2015; return true;
	case "2017": ver = VisualStudioVersion.V2017; return true;
	case "2019": ver = VisualStudioVersion.V2019; return true;
	case "2022": ver = VisualStudioVersion.V2022; return true;
	default:
		log.info(new "Unknown product version '${verstr}', falling back to VS2017");
		ver = VisualStudioVersion.V2017;
		return false;
	}
}

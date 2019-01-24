// Copyright 2018, Bernard Helyer.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect Visual Studio installations.
 */
module battery.detect.visualStudio.windows;

version (Windows):

import watt = [watt.algorithm, watt.conv, watt.io.file,
	watt.text.path, watt.text.sink, watt.text.string];

import battery.detect.visualStudio;
import battery.detect.visualStudio.logging;

import win32 = core.c.windows;
import c = core.c.string;


fn alphabeticDirectories(path: string) string[]
{
	paths: string[];

	fn addDir(name: string) watt.SearchStatus {
		if (name == "." || name == "..") {
			return watt.SearchStatus.Continue;
		}
		fullPath := watt.concatenatePath(path, name);
		if (!watt.isDir(fullPath)) {
			return watt.SearchStatus.Continue;
		}
		paths ~= name;
		return watt.SearchStatus.Continue;
	}

	watt.searchDir(path, "*", addDir);

	/* @todo Obviously a lot of issues here. Sort should be a template.
	 * Watt should have a way of comparing strings without dropping to strcmp.
	 * etc. Fix before merging.
	 */
	fn cmp(ia: size_t, ib: size_t) bool
	{
		return c.strcmp(watt.toStringz(paths[ia]), watt.toStringz(paths[ib])) <= 0;
	}

	fn swap(ia: size_t, ib: size_t)
	{
		tmp: string = paths[ia];
		paths[ia] = paths[ib];
		paths[ib] = tmp;
	}

	watt.runSort(paths.length, cmp, swap);
	return paths;
}

fn getUniversalSdkInformation(ref installationInfo: Result) bool
{
	retval := getWindowsSdkDir("v10.0", out installationInfo.windowsSdkDir);
	if (!retval) {
		retval = getWindowsSdkDir("v8.1", out installationInfo.windowsSdkDir);
		if (!retval) {
			return false;
		}
	}

	includePath := watt.concatenatePath(installationInfo.windowsSdkDir, "Include");
	versionPaths := alphabeticDirectories(includePath);
	foreach (path; versionPaths) {
		fullpath := watt.concatenatePath(includePath, path);
		fullpath = watt.concatenatePath(fullpath, `um\Windows.h`);
		if (watt.exists(fullpath) && path.length > 3 && path[0 .. 3] == "10.") {
			installationInfo.windowsSdkVersion = path;
		}
	}

	retval = getUniversalCrtDir(out installationInfo.universalCrtDir);
	if (!retval) {
		return false;
	}

	ucrtInclude := watt.concatenatePath(installationInfo.universalCrtDir, "Include");
	ucrtVersions := alphabeticDirectories(ucrtInclude);
	foreach (path; versionPaths) {
		if (path.length > 3 && path[0 .. 3] == "10.") {
			installationInfo.universalCrtVersion = path;
		}
	}

	installationInfo.addLibPath(watt.concatenatePath(installationInfo.universalCrtDir,
		new "lib\\${installationInfo.universalCrtVersion}\\ucrt\\x64"));
	installationInfo.addLibPath(watt.concatenatePath(installationInfo.windowsSdkDir,
		new "lib\\${installationInfo.windowsSdkVersion}\\um\\x64"));

	return true;
}

// Get the information on VS2015, if we can find it.
fn getVisualStudio2015Installation(out installationInfo: Result) bool
{
	log.info("Searching for Visual Studio 2017 using registry");

	retval := getVcInstallDir2015(out installationInfo.vcInstallDir);
	if (!retval) {
		log.info("Could not find vcInstallDir");
		return false;
	}

	installationInfo.addLibPath(watt.concatenatePath(installationInfo.vcInstallDir, "LIB\\amd64"));

	if (!getUniversalSdkInformation(ref installationInfo)) {
		log.info("Could not get Universal SDK information");
		return false;
	}

	proposedLinkerPath := watt.concatenatePath(installationInfo.vcInstallDir, "bin\\amd64");
	if (watt.exists(watt.concatenatePath(proposedLinkerPath, "link.exe"))) {
		installationInfo.linkerPath = proposedLinkerPath;
	}

	installationInfo.ver = VisualStudioVersion.V2015;
	installationInfo.dump("Found a VisualStudioInstallation");
	return true;
}

fn getVisualStudio2017Installation(out installationInfo: Result) bool
{
	log.info("Searching for Visual Studio 2017 using registry");

	retval := getVcInstallDir2017(out installationInfo.vcInstallDir);
	if (!retval) {
		log.info("Could not find vcInstallDir");
		return false;
	}

	installationInfo.addLibPath(watt.concatenatePath(installationInfo.vcInstallDir, "lib\\x64"));

	if (!getUniversalSdkInformation(ref installationInfo)) {
		log.info("Could not get Universal SDK information");
		return false;
	}

	proposedLinkerPath := watt.concatenatePath(installationInfo.vcInstallDir, "bin\\Hostx64\\x64");
	if (watt.exists(watt.concatenatePath(proposedLinkerPath, "link.exe"))) {
		installationInfo.linkerPath = proposedLinkerPath;
	}

	installationInfo.ver = VisualStudioVersion.V2017;
	installationInfo.dump("Found a VisualStudioInstallation");
	return true;
}

/*
 * Try to find a string value from a key in various places.
 *
 * This is based on the way VS's own batch files looks for things in the registry.
 * Using the given `keyHead`, HKLM\SOFTWARE\(Wow6432Node) will be checked.
 * The search order is always HKLM, HKCU, HKLM, HKCU.
 * The `wow64Priority` flag searches for the Wow6432Nodes first if `true`.
 *
 * Returns `true` if `valName` was found at any of the keys, and `val` will be
 * filled in with the first match. Otherwise returns `false`, and `val` should
 * not be read.
 */
fn quadKeySearch(keyHead: string, valName: string, wow64Priority: bool, out val: string) bool
{
	fn tryKey(hk: win32.DWORD, keyname: string) bool
	{
		key := new RegistryKey(hk, keyname);
		if (key.success) {
			val = key.getStringValue(valName);
			key.close();
			if (key.success) {
				return true;
			}
		}
		return false;
	}

	fn tryCombination(hk: win32.DWORD, sixtyFour: bool) bool
	{
		key: string;
		if (sixtyFour) {
			key = new "SOFTWARE\\Wow6432Node\\${keyHead}";
		} else {
			key = new "SOFTWARE\\${keyHead}";
		}
		return tryKey(hk, key);
	}

	if (tryCombination(win32.HKEY_LOCAL_MACHINE, wow64Priority)) return true;
	if (tryCombination(win32.HKEY_CURRENT_USER, wow64Priority)) return true;
	wow64Priority = !wow64Priority;
	if (tryCombination(win32.HKEY_LOCAL_MACHINE, wow64Priority)) return true;
	if (tryCombination(win32.HKEY_CURRENT_USER, wow64Priority)) return true;
	return false;
}

// Try to find the VC install path in the same manner as VS's own batch files.
fn getVcInstallDir2015(out val: string) bool
{
	return quadKeySearch(keyHead:`Microsoft\VisualStudio\SxS\VC7`, valName:`14.0`,
		wow64Priority:false, val:out val);
}

fn getVcInstallDir2017(out val: string) bool
{
	retval := quadKeySearch(keyHead:`Microsoft\VisualStudio\SxS\VS7`, valName:`15.0`,
		wow64Priority:false, val:out val);
	if (!retval) {
		return false;
	}
	toolsVersionPath := watt.concatenatePath(val, "VC\\Auxiliary\\Build\\Microsoft.VCToolsVersion.default.txt");
	if (!watt.exists(toolsVersionPath)) {
		return false;
	}
	verstr := cast(string)watt.read(toolsVersionPath);
	val = watt.concatenatePath(val, new "VC\\Tools\\MSVC\\${watt.strip(verstr)}");
	if (!watt.isDir(val)) {
		return false;
	}
	return true;
}

// Try to get a Windows SDK Dir of a specified version ("v10.0", "v8.1" etc).
fn getWindowsSdkDir(ver: string, out val: string) bool
{
	return quadKeySearch(keyHead:new "Microsoft\\Microsoft SDKs\\Windows\\${ver}", valName:`InstallationFolder`,
		wow64Priority:true, val:out val);
}

// Get the Universal CRT path from the registry.
fn getUniversalCrtDir(out val: string) bool
{
	return quadKeySearch(keyHead:`Microsoft\Windows Kits\Installed Roots`, valName:`KitsRoot10`,
		wow64Priority:true, val:out val);
}

// Thin wrapper for reading values from a registry key.
class RegistryKey
{
public:
	hKey: win32.HKEY;
	success: bool;  // Did the last operation complete okay?

public:
	// Try to open a subkey of a given default key. Sets `success`.
	this(hKey: win32.DWORD, subkey: string)
	{
		this(cast(win32.HKEY)hKey, subkey);
	}

	// Try to open a subkey of an open key. Sets `success`.
	this(hKey: win32.HKEY, subkey: string)
	{
		lRes := win32.RegOpenKeyExA(hKey,
			watt.toStringz(subkey), 0, win32.KEY_READ, &this.hKey);
		success = lRes == win32.ERROR_SUCCESS;
	}

public:
	// Close the handle to the key. Does not modify `success`.
	fn close()
	{
		win32.RegCloseKey(hKey);
		hKey = null;
	}

	fn openSubkey(name: string) RegistryKey
	{
		return new RegistryKey(hKey, name);
	}

	// Get a string value from the opened key. Sets `success`.
	fn getStringValue(valueName: string) string
	{
		val: string;
		success = getStringRegistryValue(hKey, valueName, out val);
		return val;
	}

	// Get the subkey names. Does not modify `success`.
	fn getSubkeyNames() string[]
	{
		return .getSubkeyNames(hKey);
	}

	// For every subkey, get a given string valuename, if it exists.
	fn getSubkeyValues(valuename: string) string[]
	{
		values: string[];

		subkeyNames := getSubkeyNames();
		foreach (subkeyName; subkeyNames) {
			subkey := openSubkey(subkeyName);
			if (!subkey.success) {
				continue;
			}
			val := subkey.getStringValue(valuename);
			subkey.close();
			if (!subkey.success) {
				continue;
			}
			values ~= val;
		}

		return values;
	}
}

// If `valueName` is a string value on `hKey`, return `true` and fill out `strValue`.
fn getStringRegistryValue(hKey: win32.HKEY, valueName: string, out strValue: string) bool
{
	bufSize: win32.DWORD = 512;
	buf := new char[](bufSize);
	type: win32.DWORD;
	lRes: win32.LONG = win32.RegQueryValueExA(hKey, watt.toStringz(valueName), null,
		&type, cast(win32.LPBYTE)buf.ptr, &bufSize);
	if (lRes != win32.ERROR_SUCCESS || type != win32.REG_SZ) {
		return false;
	}
	if (bufSize > 0 && bufSize-1 < buf.length && buf[bufSize-1] == '\0') {
		/* "(bufSize) includes any terminating null character or
		 *  characters unless the data was stored without them"
		 *    -RegQueryValueEx's MSDN entry
		 * "Damn it."
		 *    -The idiot writing this code
		 */
		bufSize--;
	}
	strValue = cast(string)buf[0 .. bufSize];
	return true;
}

// Get the name of all subkeys for a given registry key.
fn getSubkeyNames(hKey: win32.HKEY) string[]
{
	numSubkeys: win32.DWORD;
	maxSubkeyNameLen: win32.DWORD;
	lRes: win32.LONG = win32.RegQueryInfoKeyA(hKey, null, null, null, &numSubkeys, &maxSubkeyNameLen, null, null, null, null, null, null);
	if (lRes != win32.ERROR_SUCCESS) {
		return null;
	}
	subkeys := new string[](numSubkeys);
	for (index: win32.DWORD = 0; index < numSubkeys; ++index) {
		len: win32.DWORD = maxSubkeyNameLen + 1;  // RegQueryInfo doesn't include terminating NUL.
		buf := new char[](len);
		lRes = win32.RegEnumKeyExA(hKey, index, buf.ptr, &len, null, null, null, null);
		if (lRes != win32.ERROR_SUCCESS) {
			break;
		}
		// This length parameter *doesn't* include the NUL, so we can just use it.
		subkeys[index] = cast(string)buf[0 .. len];
	}
	return subkeys;
}

// Copyright 2018, Bernard Helyer.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect Visual Studio installations.
 */
module battery.detect.visualStudio;

import watt = [watt.io.file, watt.text.sink, watt.process.environment];

import battery.detect.visualStudio.logging;
import battery.detect.visualStudio.windows;


/*!
 * An enumeration of supported Visual Studio versions.
 */
enum VisualStudioVersion
{
	// Nothing should be before `Unknown`.
	Unknown,  //!< An unsupported Visual Studio version.
	V2015,    //!< Visual Studio 2015 (AKA v14)
	V2017,    //!< Visual Studio 2017 (AKA v15)
	MaxVersion,  // This should always be last.
}

/*!
 * Contains information on a particular Visual Studio installation.
 */
struct VisualStudioInstallation
{
public:
	fn addLibPath(path: string)
	{
		if (watt.isDir(path)) {
			mLibs ~= path;
		}
	}

public:
	//! The version of this installation.
	ver: VisualStudioVersion;
	//! The installation path of VC.
	vcInstallDir: string;
	//! The path to the Windows SDK.
	windowsSdkDir: string;
	//! The Windows SDK version.
	windowsSdkVersion: string;
	//! The path to the Universal CRT.
	universalCrtDir: string;
	//! The Universal CRT version.
	universalCrtVersion: string;
	//! Semicolon separated list of paths for the linker.
	@property fn lib() string
	{
		ss: watt.StringSink;
		foreach (_lib; mLibs) {
			ss.sink(_lib);
			ss.sink(";");
		}
		return ss.toString();
	}
	//! Path where link.exe resides.
	linkerPath: string;
	@property fn libsAsPaths() string[]
	{
		return mLibs;
	}

private:
	mLibs: string[];
}

/*!
 * Return a simple string that corresponds with a `VisualStudioVersion`
 */
fn visualStudioVersionToString(ver: VisualStudioVersion) string
{
	final switch (ver) with (VisualStudioVersion) {
	case Unknown, MaxVersion: return "unknown";
	case V2015: return "2015";
	case V2017: return "2017";
	}
}

/*!
 * Returns a list of supported Visual Studio installations.
 *
 * Only returns supported versions. Only works on 64 bit systems. An installation
 * is only considered valid if VC is installed.
 */
fn getVisualStudioInstallations(env: watt.Environment) VisualStudioInstallation[]
{
	installations: VisualStudioInstallation[];
	installationInfo: VisualStudioInstallation;

	// Prefer 2017
	version (Windows) if (getVisualStudio2017Installation(out installationInfo)) {
		installations ~= installationInfo;
	}
	version (Windows) if (getVisualStudio2015Installation(out installationInfo)) {
		installations ~= installationInfo;
	}
	if (getVisualStudioEnvInstallations(out installationInfo, env)) {
		installations ~= installationInfo;
	}

	return installations;
}

fn getVisualStudioEnvInstallations(out installationInfo: VisualStudioInstallation, env: watt.Environment) bool
{
	log.info("Searching for Visual Studio using enviroment");

	//installationInfo.oldInc = env.getOrNull("INCLUDE");
	//installationInfo.oldLib = env.getOrNull("LIB");

	dirVC := env.getOrNull("VCINSTALLDIR");
	dirVCTools := env.getOrNull("VCTOOLSINSTALLDIR");

	if (dirVCTools !is null) {
		installationInfo.ver = VisualStudioVersion.V2017;
		installationInfo.vcInstallDir = dirVCTools;
	} else if (dirVC !is null) {
		installationInfo.ver = VisualStudioVersion.V2015;
		installationInfo.vcInstallDir = dirVC;
	} else {
		log.info("Neither VS Tools 2015 or 2017 was found via environment.");
		log.info("Looked for 'VCINSTALLDIR' or 'VCTOOLSINSTALLDIR'.");
		return false;
	}

	fn getOrWarn(name: string) string {
		value := env.getOrNull(name);
		if (value.length == 0) {
			log.info(new "Missing env var '${name}'");
		}
		return value;
	}

	installationInfo.universalCrtDir = getOrWarn("UniversalCRTSdkDir");
	installationInfo.windowsSdkDir = getOrWarn("WindowsSdkDir");
	installationInfo.universalCrtVersion = getOrWarn("UCRTVersion");
	installationInfo.windowsSdkVersion = getOrWarn("WindowsSDKVersion");

	if (installationInfo.universalCrtDir.length == 0 ||
	    installationInfo.universalCrtVersion.length == 0 ||
	    installationInfo.windowsSdkDir.length == 0 ||
	    installationInfo.windowsSdkVersion.length == 0) {
		log.info("failed to find needed environmental variables.");
		return false;
	}

	installationInfo.dumpVisualStudioInstallation("Found a VisualStudioInstallation");
	return true;
}

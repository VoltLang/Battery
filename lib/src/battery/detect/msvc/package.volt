// Copyright 2018, Bernard Helyer.
// Copyright 2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect Visual Studio installations.
 *
 * @todo Remove lib property.
 * @todo Move expansions of libs and includes into here.
 */
module battery.detect.msvc;

import watt = [watt.io.file, watt.text.sink];

import battery.detect.msvc.logging;
import battery.detect.msvc.windows;


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
 * From environment.
 */
struct FromEnv
{
	vcInstallDir: string;
	vcToolsInstallDir: string;
	universalCrtDir: string;
	universalCrtVersion: string;
	windowsSdkDir: string;
	windowsSdkVersion: string;
}

/*!
 * Contains information on a particular Visual Studio installation.
 */
struct Result
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
fn detect(ref fromEnv: FromEnv, out results: Result[]) bool
{
	result: Result;

	// Prefer 2017
	version (Windows) if (getVisualStudio2017Installation(out result)) {
		results ~= result;
	}
	version (Windows) if (getVisualStudio2015Installation(out result)) {
		results ~= result;
	}
	if (getVisualStudioEnvInstallations(ref fromEnv, out result)) {
		results ~= result;
	}

	return results.length != 0;
}


private:

fn getVisualStudioEnvInstallations(ref fromEnv: FromEnv, out installationInfo: Result) bool
{
	log.info("Searching for Visual Studio using enviroment");

	//installationInfo.oldInc = env.getOrNull("INCLUDE");
	//installationInfo.oldLib = env.getOrNull("LIB");

	dirVC := fromEnv.vcInstallDir;
	dirVCTools := fromEnv.vcToolsInstallDir;

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

	fn getOrWarn(value: string, name: string) string {
		if (value.length == 0) {
			log.info(new "Missing env var '${name}'");
		}
		return value;
	}

	installationInfo.universalCrtDir = getOrWarn(fromEnv.universalCrtDir, "UniversalCRTSdkDir");
	installationInfo.windowsSdkDir = getOrWarn(fromEnv.windowsSdkDir, "WindowsSdkDir");
	installationInfo.universalCrtVersion = getOrWarn(fromEnv.universalCrtVersion, "UCRTVersion");
	installationInfo.windowsSdkVersion = getOrWarn(fromEnv.windowsSdkVersion, "WindowsSDKVersion");

	if (installationInfo.universalCrtDir.length == 0 ||
	    installationInfo.universalCrtVersion.length == 0 ||
	    installationInfo.windowsSdkDir.length == 0 ||
	    installationInfo.windowsSdkVersion.length == 0) {
		log.info("failed to find needed environmental variables.");
		return false;
	}

	installationInfo.dump("Found a VisualStudioInstallation");
	return true;
}

// Copyright 2018, Bernard Helyer.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Detect Visual Studio installations.
 */
module battery.detect.visualStudio;

import watt = [watt.io.file, watt.text.sink];

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
fn getVisualStudioInstallations() VisualStudioInstallation[]
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

	return installations;
}

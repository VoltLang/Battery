// Copyright 2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Shared logger for Visual Studio detection code.
 */
module battery.detect.visualStudio.logging;

static import battery.util.log;

import watt = [watt.text.sink, watt.text.string];

import battery.detect.visualStudio;

/*!
 * So we get the right prefix on logged messages.
 */
global log: battery.util.log.Logger = {"detect.visualStudio"};

fn dumpVisualStudioInstallation(ref installationInfo: VisualStudioInstallation, message: string)
{
	ss: watt.StringSink;

	ss.sink(message);
	watt.format(ss.sink, "\n\t ver = %s", installationInfo.ver.visualStudioVersionToString());
	watt.format(ss.sink, "\n\t vcInstallDir = %s", installationInfo.vcInstallDir);
	watt.format(ss.sink, "\n\t windowsSdkDir = %s", installationInfo.windowsSdkDir);
	watt.format(ss.sink, "\n\t windowsSdkVersion = %s", installationInfo.windowsSdkVersion);
	watt.format(ss.sink, "\n\t universalCrtDir = %s", installationInfo.universalCrtDir);
	watt.format(ss.sink, "\n\t universalCrtVersion = %s", installationInfo.universalCrtVersion);
	watt.format(ss.sink, "\n\t linkerPath = %s", installationInfo.linkerPath);
	watt.format(ss.sink, "\n\t libs = [");
	foreach (_lib; installationInfo.libsAsPaths) {
		ss.sink("\n\t\t");
		ss.sink(_lib);
	}
	ss.sink("]");

	log.info(ss.toString());
}

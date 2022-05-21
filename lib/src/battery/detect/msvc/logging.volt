// Copyright 2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Shared logger for Visual Studio detection code.
 */
module battery.detect.msvc.logging;

static import battery.util.log;

import watt = [watt.text.sink, watt.text.string];

import battery.detect.msvc;


/*!
 * So we get the right prefix on logged messages.
 */
global log: battery.util.log.Logger = {"detect.msvc"};

fn dump(ref result: Result, message: string)
{
	ss: watt.StringSink;

	ss.sink(message);
	watt.format(ss.sink, "\n\tver = %s", result.ver.visualStudioVersionToString());
	watt.format(ss.sink, "\n\tfrom = %s", result.from);
	watt.format(ss.sink, "\n\tvsWhereCmd = %s", result.vsWhereCmd);
	watt.format(ss.sink, "\n\tvcInstallDir = %s", result.vcInstallDir);
	watt.format(ss.sink, "\n\tclCmd = %s", result.clCmd);
	watt.format(ss.sink, "\n\tlinkCmd = %s", result.linkCmd);
	watt.format(ss.sink, "\n\twindowsSdkDir = %s", result.windowsSdkDir);
	watt.format(ss.sink, "\n\twindowsSdkVersion = %s", result.windowsSdkVersion);
	watt.format(ss.sink, "\n\tuniversalCrtDir = %s", result.universalCrtDir);
	watt.format(ss.sink, "\n\tuniversalCrtVersion = %s", result.universalCrtVersion);
	log.info(ss.toString());
}

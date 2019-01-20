// Copyright 2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Shared logger for Visual Studio detection code.
 */
module battery.detect.llvm.logging;

static import battery.util.log;

import watt = [watt.text.sink, watt.text.string];

import battery.detect.llvm;


/*!
 * So we get the right prefix on logged messages.
 */
global log: battery.util.log.Logger = {"detect.llvm"};

fn dump(ref arg: Argument, ref res: Result, message: string)
{
	ss: watt.StringSink;

	ss.sink(message);
	watt.format(ss.sink, "\n\tfrom = %s", res.from);
	watt.format(ss.sink, "\n\tver = %s", res.ver);
	if (arg.need.config) {
		watt.format(ss.sink, "\n\tconfigCmd = '%s'", res.configCmd);
		watt.format(ss.sink, "\n\tconfigArgs = %s", res.configArgs);
	}
	if (arg.need.ar) {
		watt.format(ss.sink, "\n\tarCmd = '%s'", res.arCmd);
		watt.format(ss.sink, "\n\tarArgs = %s", res.arArgs);
	}
	if (arg.need.clang) {
		watt.format(ss.sink, "\n\tclangCmd = '%s'", res.clangCmd);
		watt.format(ss.sink, "\n\tclangArgs = %s", res.clangArgs);
	}
	if (arg.need.ld) {
		watt.format(ss.sink, "\n\tldCmd = '%s'", res.ldCmd);
		watt.format(ss.sink, "\n\tldArgs = %s", res.ldArgs);
	}
	if (arg.need.link) {
		watt.format(ss.sink, "\n\tlinkCmd = '%s'", res.linkCmd);
		watt.format(ss.sink, "\n\tlinkArgs = %s", res.linkArgs);
	}
	log.info(ss.toString());
}

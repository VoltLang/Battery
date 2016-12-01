// Copyright © 2012-2013, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module battery.testing.main;

import core.exception;
import core.stdc.stdio : stdout, printf, fflush, fopen, fprintf, fclose;
import core.stdc.stdlib;

import watt.text.format;
import watt.text.getopt;
import watt.text.string : indexOf;
import watt.process;
import watt.path;
import watt.conv;
import watt.io;
import watt.io.file;

import battery.util.system;
import build.util.cmdgroup;

import core.windows.windows;

import battery.testing.test;
import battery.testing.legacy;
import battery.testing.command;
import battery.testing.searcher;
import battery.testing.project;
import battery.testing.output.xml;
import battery.testing.output.stdio;


enum DEFAULT_DIR = "test";
enum DEFAULT_RESULTS = "results.xml";

fn getArch() string
{
	version (X86) {
		return "x86";
	} else version (X86_64) {
		return "x86_64";
	} else {
		return "UnknownArch";
	}
}

fn getPlatform() string
{
	version (MSVC) {
		return "msvc";
	} else version (MinGW) {
		return "mingw";
	} else version (Linux) {
		return "linux";
	} else version (OSX) {
		return "osx";
	}
}

fn getFinalPrefix(base: string) string
{
	return format("%s-%s/%s/", getArch(), getPlatform(), base);
}

/**
 * Run tests.
 * Params:
 *   projects    = test projects to run.
 * Returns: non-zero on failure, zero on success.
 */
fn testMain(projects: Project[]) i32
{
	cmdGroup := new CmdGroup(retrieveEnvironment(), processorCount());
	tests: Test[];
	foreach (i, project; projects) {
		cmd := project.getCommand("volta");
		cs := new CommandStore("");
		cs.addCmd("volta", cmd.cmd, cmd.args);

		s := new Searcher(cs);
		tests ~= s.search(project.path, getFinalPrefix(format("test%s", i)));	
	}

	foreach (test; tests) {
		test.runTest(cmdGroup);
	}

	cmdGroup.waitAll();

	hasRegression: bool;

	writeXmlFile(DEFAULT_RESULTS, tests);
	writeToStdio(tests, out hasRegression);

	return hasRegression;
}

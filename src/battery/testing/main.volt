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
import battery.testing.cmd;

import core.windows.windows;

import battery.testing.test;
import battery.testing.legacy;
import battery.testing.command;
import battery.testing.searcher;
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
 *   threadCount = how many jobs to run at once. (0 means processor count).
 *   testDirs    = paths to test. (empty dir means just run 'test').
 *   configPath  = path to test config file. (empty string means default settings).
 *   progress    = print progress to stdout.
 *   compiler    = specify the compiler to use. (empty string means $VOLT).
 *   results     = name of the results XML file. (empty string means DEFAULT_RESULTS)
 * Returns: non-zero on failure, zero on success.
 */
fn testMain(threadCount: i32, testDirs: string[], configPath: string, printProgress: bool, compiler: string, results: string) i32
{
	testPrefixes: string[];
	foreach (i, dir; testDirs) {
		testPrefixes ~= format("test%s", i + 1);
	}
	filter: string;

	if (compiler is null) {
		compiler = getEnv("VOLT");
	}

	if (compiler is null && configPath == "") {
		writefln("must use --compiler|-c to specify compiler");
		writefln("or set enviroment variable VOLT");
		return 1;
	}

	if (testDirs.length != testPrefixes.length) {
		writefln("Too %s prefixes.", testDirs.length < testPrefixes.length ? "many" : "few");
		return 1;
	}

	if (testDirs.length == 0) {
		testPrefixes ~= "test1";
		testDirs ~= DEFAULT_DIR;
	}

	if (results is null) {
		results = DEFAULT_RESULTS;
	}

	foreach (testDir; testDirs) {
		if (!testDir.isDir()) {
			writefln("No such directory '%s'", testDir);
			return 1;
		}
	}

	cs := new CommandStore(configPath);
	if (compiler != "" && configPath == "") {
		cs.addCmd("volta", compiler, null);
	}

	j := threadCount > 0 ? cast(uint)threadCount : processorCount();
	cmdGroup := new CmdGroup(j, printProgress);


	s := new Searcher(cs);
	rets: Test[];
	foreach (i, testDir; testDirs) {
		rets ~= s.search(testDir, getFinalPrefix(testPrefixes[i]));
	}

	foreach (i, test; rets) {
		test.runTest(cmdGroup);
	}

	cmdGroup.waitAll();

	hasRegression: bool;

	writeXmlFile(results, rets);
	if (printProgress) {
		writeln();
	}
	writeToStdio(rets, out hasRegression);

	return hasRegression;
}

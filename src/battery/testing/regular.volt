// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/tesla/license.volt (BOOST ver. 1.0).
module battery.testing.regular;

import core.exception;
import core.stdc.stdio : fopen, fclose;
import watt.io;
import watt.path;
import watt.conv;
import watt.io.file;
import watt.text.string;
import watt.text.format;

import battery.configuration;
import battery.testing.test;
import build.util.cmdgroup;

class Regular : Test
{
public:
	/// Commands from the test file to execute.
	runs: string[][];

	/// Expected results of commands.
	retvals: i32[];

	/// Temporary file name for this test.
	tempName: string;

	/// Directory name.
	srcDir: string;

	/// Test file name.
	srcFile: string;

	/// Actual test file's name.
	testFileName: string;

	/// What lines containing test commands start with.
	commandPrefix: string;

	cmdGroup: CmdGroup;

private:
	mRunPrefix: string;
	mRetvalPrefix: string;
	mOutDir: string;
	mOutFile: string;
	mCommandStore: Configuration;

public:
	this(srcDir: string, test: string, testFileName: string,
		commandPrefix: string, prefix: string, cs: Configuration)
	{
		this.srcDir = srcDir;
		this.srcFile = srcDir ~ dirSeparator ~ testFileName;
		this.testFileName = testFileName;
		this.name = test;
		this.prefix = prefix;
		this.mCommandStore = cs;

		this.commandPrefix = commandPrefix;
		this.mRunPrefix = commandPrefix ~ "run:";
		this.mRetvalPrefix = commandPrefix ~ "retval:";
	}

	override fn runTest(cmdGroup: CmdGroup)
	{
		this.cmdGroup = cmdGroup;
		mOutDir = ".obj" ~ dirSeparator ~ name;
		mkdir(mOutDir);
		mOutFile = mOutDir ~ dirSeparator ~ "output";
		logFile := mOutDir ~ dirSeparator ~ "log.txt";
		log = fopen(toStringz(logFile), "w");

		ifs := new InputFileStream(srcFile);
		while (!ifs.eof()) {
			line := ifs.readln();
			if (!line.startsWith(commandPrefix)) {
				continue;
			}
			if (line.startsWith(mRunPrefix)) {
				if (!parseRunCommand(line)) {
					return;
				}
			} else if (line.startsWith(mRetvalPrefix)) {
				parseRetvalCommand(line);
			} else {
				testFailure(format("unknown regular test command line: '%s''", line));
				return;
			}
		}
		ifs.close();
		if (runs.length == 0) {
			testFailure("no run command");
			return;
		}
		if (retvals.length == 0) {
			retvals = new i32[](runs.length);
			foreach (ref retval; retvals) {
				retval = 0;
			}
		}
		if (retvals.length != runs.length) {
			testFailure(format("expected %s retval commands, got %s",
				runs.length, retvals.length));
			return;
		}
		runCommand();
	}

private:
	fn runRuns(retval: int)
	{
		if (retval != retvals[0]) {
			testFailure(format("command returned retval %s, expected %s",
				retval, retvals[0]));
			return;
		}
		runs = runs[1 .. $];
		retvals = retvals[1 .. $];
		if (runs.length == 0) {
			testOk();
			return;
		}
		runCommand();
	}

	fn runCommand()
	{
		cmd := runs[0][0];
		args := runs[0][1 .. $];
		c := mCommandStore.getTool(cmd);
		if (c !is null) {
			cmd = c.cmd;
			args = c.args ~ args;
		}
		cmdGroup.run(cmd, args, runRuns, log);
	}

	fn parseRunCommand(line: string) bool
	{
		command := strip(line[mRunPrefix.length .. $]);
		command = command.replace("%s", srcFile);
		command = command.replace("%S", srcDir);
		command = command.replace("%t", mOutFile);
		command = command.replace("%T", mOutDir);
		i := command.indexOf('%');
		if (i >= 0 && (cast(size_t)(i+1) >= command.length ||
			command[i+1] != '%')) {
			testFailure("unknown run command variable");
			return false;
		}
		command = command.replace("%%", "%");
		runs ~= command.split(' ');
		return true;
	}

	fn parseRetvalCommand(line: string)
	{
		retvals ~= toInt(line[mRetvalPrefix.length .. $]);
	}

	fn completelyDone(ok: bool, msg: string)
	{
		this.msg = msg;
		hasPassed := true;

		// Set the result
		if (ok && hasPassed) {
			result = Result.PASS;
		} else if (ok) {
			result = Result.XPASS;
		} else if (hasPassed) {
			result = Result.FAIL;
		} else {
			result = Result.XFAIL;
		}

		// Close the log.
		if (log !is null) {
			fclose(log);
			log = null;
		}
	}

	fn testOk()
	{
		completelyDone(true, "ok");
	}

	fn testFailure(msg: string)
	{
		completelyDone(false, msg);
	}
}

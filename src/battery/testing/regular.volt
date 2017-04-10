// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/tesla/license.volt (BOOST ver. 1.0).
module battery.testing.regular;

import core.exception;
import core.c.stdio;
import watt.path;
import watt.conv;
import watt.io;
import watt.io.file;
import watt.io.streams;

import watt.text.string;
import watt.text.format;

import battery.configuration;
import battery.testing.test;
import battery.testing.project;
import battery.testing.btj;
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

	cmdGroup: CmdGroup;

	btj: BatteryTestsJson;

private:
	mOutDir: string;
	mOutFile: string;
	mCommandStore: Configuration;
	mOutputLog: FILE*;
	mOlogFile: string;
	mErrorLog: FILE*;
	mElogFile: string;
	mExpectFailure: bool;  // has-passed:no
	mCheck: string;

public:
	/**
	 * Construct a new Regular test.
	 * Params:
	 *   srcDir: The directory that contains the test.
	 *   test: The name of the test.
	 *   testFileName: The filename of the primary test file.
	 *   btj: The parsed battery.tests.json.
	 *   project: The Project for this test.
	 *   cs: A Configuration containing the tools and platform/arch information.
	 */
	this(srcDir: string, test: string, testFileName: string,
		btj: BatteryTestsJson, project: Project, cs: Configuration)
	{
		this.srcDir = srcDir;
		this.srcFile = srcDir ~ dirSeparator ~ testFileName;
		this.testFileName = testFileName;
		this.name = test;
		this.project = project;
		this.mCommandStore = cs;
		this.btj = btj;
	}

	// Returns false if this function should cease.
	fn parseCommand(line: string) bool
	{
		if (!line.startsWith(btj.prefix)) {
			return true;
		}
		if (line.startsWith(btj.runPrefix)) {
			return parseRunCommand(line);
		} else if (line.startsWith(btj.retvalPrefix)) {
			parseRetvalCommand(line);
		} else if (line.startsWith(btj.requiresPrefix)) {
			return parseRequiresCommand(line:line, prefix:true);
		} else if (line.startsWith(btj.hasPassedPrefix)) {
			mExpectFailure = true;
		} else if (line.startsWith(btj.macroPrefix)) {
			return parseMacroCommand(line);
		} else if (line.startsWith(btj.checkPrefix)) {
			return parseCheckCommand(line);
		} else if (line.startsWith(btj.noDefaultPrefix)) {
			// Handled specially.
		} else {
			testFailure(format("unknown regular test command line: '%s''", line));
			return false;
		}
		return true;
	}

	override fn runTest(cmdGroup: CmdGroup)
	{
		this.cmdGroup = cmdGroup;
		mOutDir = ".obj" ~ dirSeparator ~ name;
		mkdirP(mOutDir);
		mOutFile = mOutDir ~ dirSeparator ~ "output";
		mOlogFile = mOutDir ~ dirSeparator ~ "outlog.txt";
		mElogFile = mOutDir ~ dirSeparator ~ "errlog.txt";
		mOutputLog = fopen(toStringz(mOlogFile), "w");
		mErrorLog = fopen(toStringz(mElogFile), "w");

		// Check for default:no.
		ifs := new InputFileStream(srcFile);
		noDefault := false;
		while (!ifs.eof() && !noDefault) {
			line := ifs.readln();
			if (!line.startsWith(btj.prefix)) {
				break;
			}
			noDefault = line.startsWith(btj.noDefaultPrefix) != 0;
		}
		ifs.close();

		// Run default commands.
		if (!noDefault) {
			defaults := btj.getMacro("default");
			foreach (defaultCommand; defaults) {
				if (!parseCommand(defaultCommand)) {
					return;
				}
			}
		}

		// Run the commands in the file.
		ifs = new InputFileStream(srcFile);
		while (!ifs.eof()) {
			line := ifs.readln();
			if (!line.startsWith(btj.prefix)) {
				break;
			}
			if (!parseCommand(line)) {
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

	override fn getOutput() string
	{
		return cast(string)read(mOlogFile);
	}

	override fn getError() string
	{
		return cast(string)read(mElogFile);
	}

private:
	fn runRuns(retval: int)
	{
		if (retval != retvals[0]) {
			testFailure(format("command '%s' returned retval %s, expected %s",
				runs[0][0], retval, retvals[0]));
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
		version (Windows) {
			if (!cmd.endsWith(".exe")) {
				cmd ~= ".exe";
			}
		}
		cmdGroup.run(cmd, args, runRuns, mOutputLog, mErrorLog);
	}

	fn parseCheckCommand(line: string) bool
	{
		mCheck = strip(line[btj.checkPrefix.length .. $]);
		assert(mCheck.length > 0);
		return true;
	}

	fn parseMacroCommand(line: string) bool
	{
		macroStr := strip(line[btj.macroPrefix.length .. $]);
		commandsPtr := macroStr in btj.macros;
		if (commandsPtr is null) {
			testFailure("unknown macro");
			return false;
		}
		foreach (command; *commandsPtr) {
			if (!parseCommand(command)) {
				return false;
			}
		}
		return true;
	}

	fn parseRequiresCommand(line: string, prefix: bool) bool
	{
		prefixLength := !prefix ? 0 : btj.requiresPrefix.length;
		command := strip(line[prefixLength .. $]);
		tokens := command.split(' ');
		reqexp: RequireExpression;
		root: RequireExpression;
		foreach (token; tokens) {
			if (reqexp is null) {
				reqexp = new RequireExpression(token, this);
				root = reqexp;
			} else {
				reqexp = reqexp.nextToken(token);
				if (reqexp is null) {
					testFailure("malformed requires command");
					return false;
				}
			}
		}
		if (root is null) {
			testFailure("malformed requires command");
			return false;
		}
		b := root.evaluate(mCommandStore.arch, mCommandStore.platform, btj.requiresAliases);
		if (root.err.length > 0) {
			testFailure("bad requires: " ~ root.err);
			return false;
		}
		if (!b) {
			testSkip();
			return false;
		}
		return true;
	}

	fn parseRunCommand(line: string) bool
	{
		command := strip(line[btj.runPrefix.length .. $]);
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
		retvals ~= toInt(line[btj.retvalPrefix.length .. $]);
	}

	fn completelyDone(ok: bool, msg: string)
	{
		this.msg = msg;

		// Set the result
		if (ok && !mExpectFailure) {
			result = Result.PASS;
		} else if (ok) {
			result = Result.XPASS;
		} else if (!mExpectFailure) {
			result = Result.FAIL;
		} else {
			result = Result.XFAIL;
		}
		closeLogs();
	}

	fn closeLogs()
	{
		// Close the log.
		if (mOutputLog !is null) {
			fclose(mOutputLog);
		}
		mOutputLog = null;
		if (mErrorLog !is null) {
			fclose(mErrorLog);
		}
		mErrorLog = null;
		testCheck();
	}

	fn testCheck()
	{
		if (result == Result.SKIPPED || mCheck.length == 0) {
			return;
		}
		outstr := cast(string)read(mOlogFile);
		if (outstr.indexOf(mCheck) >= 0) {
			return;
		}
		errstr := cast(string)read(mElogFile);
		if (errstr.indexOf(mCheck) >= 0) {
			return;
		}
		msg = "check failed";
		if (!mExpectFailure) {
			result = Result.FAIL;
		} else {
			result = Result.XFAIL;
		}
	}

	fn testSkip()
	{
		this.msg = "skipped";
		result = Result.SKIPPED;
		closeLogs();
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

class RequireExpression
{
	enum Type
	{
		None,
		And,
		Or
	}

	type: Type;
	isNot: bool;
	val: string;
	next: RequireExpression;
	err: string;
	test: Regular;

	this(val: string, test: Regular)
	{
		if (val[0] == '!') {
			isNot = true;
			val = val[1 .. $];
		}
		this.val = val;
		this.test = test;
	}

	fn nextToken(s: string) RequireExpression
	{
		switch (s) {
		case "&&": type = Type.And; return this;
		case "||": type = Type.Or; return this;
		default:
			if (type == Type.None) {
				return null;
			}
			next = new RequireExpression(s, test);
			return next;
		}
	}

	/// Is this entire chain true or false?
	fn evaluate(arch: Arch, platform: Platform, requiresAliases: string[string]) bool
	{
		b := evaluateBase(arch, platform, requiresAliases);
		if (isNot) {
			b = !b;
		}
		final switch (type) with (Type) {
		case None:
			return b;
		case And:
			nb := next.evaluate(arch, platform, requiresAliases);
			if (next.err.length > 0) {
				err = next.err;
			}
			return b && nb;
		case Or:
			nb := next.evaluate(arch, platform, requiresAliases);
			if (next.err.length > 0) {
				err = next.err;
			}
			return b || nb;
		} 
	}

	/// Is the underlying condition true or false, ignore next and isNot.
	fn evaluateBase(arch: Arch, platform: Platform, requiresAliases: string[string]) bool
	{
		aliasedptr := val in requiresAliases;
		if (aliasedptr !is null) {
			return test.parseRequiresCommand(line:*aliasedptr, prefix:false);
		}
		if (!isArch(val) && !isPlatform(val)) {
			err = "unknown requires string";
			return false;
		}
		if (val == "all") {
			return true;
		} else if (val == "none") {
			return false;
		}
		if (isArch(val)) {
			return stringToArch(val) == arch;
		} else {
			return stringToPlatform(val) == platform;
		}
	}
}

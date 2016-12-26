// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/tesla/license.volt (BOOST ver. 1.0).
module battery.testing.regular;

import core.exception;
import core.stdc.stdio;
import watt.io;
import watt.path;
import watt.conv;
import watt.io.file;
import watt.text.string;
import watt.text.format;

import battery.configuration;
import battery.testing.test;
import battery.testing.project;
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

	/// Process these commands before anny specified in the file.
	defaultCommands: string[];

	/// Requires will substitute any keys found with corresponding value.
	requiresAliases: string[string];

	cmdGroup: CmdGroup;

private:
	mRunPrefix: string;
	mRetvalPrefix: string;
	mRequiresPrefix: string;
	mHasPassedPrefix: string;
	mOutDir: string;
	mOutFile: string;
	mCommandStore: Configuration;
	mOutputLog: FILE*;
	mOlogFile: string;
	mErrorLog: FILE*;
	mElogFile: string;
	mExpectFailure: bool;  // has-passed:no

public:
	/**
	 * Construct a new Regular test.
	 * Params:
	 *   srcDir: The directory that contains the test.
	 *   test: The name of the test.
	 *   testFileName: The filename of the primary test file.
	 *   commandPrefix: The string that precedes commands, like "//T ".
	 *   project: The Project for this test.
	 *   cs: A Configuration containing the tools and platform/arch information.
	 *   defaultCommands: A list of commands to run before any of the parsed ones.
	 *	   (these should contain the commandPrefix).
	 *   requiresAliases: Strings to be replaced by other strings in requires.
	 */
	this(srcDir: string, test: string, testFileName: string,
		commandPrefix: string, project: Project, cs: Configuration,
		defaultCommands: string[], requiresAliases: string[string])
	{
		this.srcDir = srcDir;
		this.srcFile = srcDir ~ dirSeparator ~ testFileName;
		this.testFileName = testFileName;
		this.name = test;
		this.project = project;
		this.mCommandStore = cs;

		this.commandPrefix = commandPrefix;
		this.defaultCommands = defaultCommands;
		// TODO: Do these once in the json parser, and pass that whole thing in.
		this.mRunPrefix = commandPrefix ~ "run:";
		this.mRetvalPrefix = commandPrefix ~ "retval:";
		this.mRequiresPrefix = commandPrefix ~ "requires:";
		this.mHasPassedPrefix = commandPrefix ~ "has-passed:no";
		this.requiresAliases = requiresAliases;
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

		// Returns false if this function should cease.
		fn parseCommand(line: string) bool
		{
			if (!line.startsWith(commandPrefix)) {
				return true;
			}
			if (line.startsWith(mRunPrefix)) {
				return parseRunCommand(line);
			} else if (line.startsWith(mRetvalPrefix)) {
				parseRetvalCommand(line);
			} else if (line.startsWith(mRequiresPrefix)) {
				return parseRequiresCommand(line:line, prefix:true);
			} else if (line.startsWith(mHasPassedPrefix)) {
				mExpectFailure = true;
			} else {
				testFailure(format("unknown regular test command line: '%s''", line));
				return false;
			}
			return true;
		}

		foreach (defaultCommand; defaultCommands) {
			if (!parseCommand(defaultCommand)) {
				return;
			}
		}

		ifs := new InputFileStream(srcFile);
		while (!ifs.eof()) {
			line := ifs.readln();
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
		cmdGroup.run(cmd, args, runRuns, mOutputLog, mErrorLog);
	}

	fn parseRequiresCommand(line: string, prefix: bool) bool
	{
		prefixLength := !prefix ? 0 : mRequiresPrefix.length;
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
		b := root.evaluate(mCommandStore.arch, mCommandStore.platform, requiresAliases);
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

		// Close the log.
		fclose(mOutputLog);
		mOutputLog = null;
		fclose(mErrorLog);
		mErrorLog = null;
	}

	fn testSkip()
	{
		this.msg = "skipped";
		result = Result.SKIPPED;
		fclose(mOutputLog);
		mOutputLog = null;
		fclose(mErrorLog);
		mErrorLog = null;
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
		if (isArch(val)) {
			return stringToArch(val) == arch;
		} else {
			return stringToPlatform(val) == platform;
		}
	}
}
import watt.io;
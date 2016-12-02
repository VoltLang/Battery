// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/tesla/license.volt (BOOST ver. 1.0).
module battery.testing.legacy;

import watt.conv;
import watt.path;
import watt.process;
import watt.text.sink;
import watt.text.format : format;
import watt.text.string : indexOf, split, strip, startsWith;
import watt.io.file : read;
import core.stdc.stdio : printf, FILE, fprintf, fopen, fgets, fclose, fflush, stdout, stdin;
import core.stdc.string : strlen;

import battery.configuration;
import battery.util.system;
import battery.testing.test;
import build.util.cmdgroup;


class Legacy : Test
{
public:
	srcDir: string;
	srcDirAppendable: string;
	test: string;

	outFile: string;
	logFile: string;
	srcFile: string;
	args: string[];

	runCmd: string;
	runArgs: string[];

	expectedRetval: int;
	expectedErrorLine: int;
	expectedErrorMessage: string;
	doNotLink: bool;
	hasPassed: bool;

	expectedToCompile: bool;

	cmdGroup: CmdGroup;

	/// If not null, increment then print to stdout.
	completedPointer: int*;


protected:
	mCommandStore: Configuration;


public:
	this(srcDir: string, test: string, cs: Configuration, prefix: string)
	{
		this.srcDir = srcDir;
		this.srcDirAppendable = srcDir ~ dirSeparator;
		this.name = test;
		this.test = test;
		this.mCommandStore = cs;
		this.prefix = prefix;
	}

	override fn runTest(cmdGroup: CmdGroup)
	{
		this.cmdGroup = cmdGroup;
		outDirAppendable: string;
		expectedToCompile = true;
		expectedRetval = 0;
		expectedErrorLine = 0;
		hasPassed = true;

		if (test.length < 6) {
			malformedTest();
			return;
		}

		if (test[test.length - 4] != '/' &&
		    test[test.length - 4] != '\\') {
			malformedTest();
			return;
		}

		srcFile = srcDirAppendable ~ "test.volt\0";
		srcFile = srcFile[0 .. srcFile.length - 1];
		outDirAppendable = ".obj" ~ dirSeparator ~ test ~ dirSeparator;
		outFile = outDirAppendable ~ "output.exe";
		logFile = outDirAppendable ~ "log.txt\0";
		logFile = logFile[0 .. logFile.length - 1];

		mkdirP(outDirAppendable);

		runArgs = new string[](0);
		args = new string[](3);
		args[0] = srcFile;
		args[1] = "-o";
		args[2] = outFile;

		data := fopen(srcFile.ptr, "r".ptr);
		if (data is null) {
			missingTest();
			return;
		}

		array := new char[](500);
		buffer := array.ptr;
		line: char*;

		while ((line = fgets(buffer, 500, data)) !is null) {
			l := line[0 .. strlen(line)];
			if (l.length < 5) {
				continue;
			}
			l = l[0 .. l.length - 1];

			if (l[0 .. 3] != cast(char[])"//T") {
				continue;
			}

			if (startsWith(l, "//T retval:exception")) {
				version (Windows) {
					expectedRetval = -1;
				} else {
					expectedRetval = 255;
				}
				continue;
			} else if (startsWith(l, "//T retval:")) {
				expectedRetval = toInt(strip(l[11 .. $]));
				continue;
			} else if (startsWith(l, "//T compiles:yes")) {
				expectedToCompile = true;
				continue;
			} else if (startsWith(l, "//T compiles:no")) {
				expectedToCompile = false;
				continue;
			} else if (startsWith(l, "//T has-passed:no")) {
				hasPassed = false;
				continue;
			} else if (startsWith(l, "//T has-passed:yes")) {
				hasPassed = true;
				continue;
			} else if (startsWith(l, "//T dependency:")) {
				args ~= srcDirAppendable ~ l[15 .. l.length];
				continue;
			} else if (startsWith(l, "//T feature:debug")) {
				args ~= "-d";
				continue;
			} else if (startsWith(l, "//T feature:nodebug")) {
				continue;
			} else if (startsWith(l, "//T error-line:")) {
				expectedErrorLine = toInt(strip(l[15 .. $]));
				continue;
			} else if (startsWith(l, "//T error-message:")) {
				expectedErrorMessage = new string(l[18 .. $]);
				continue;
			} else if (startsWith(l, "//T do-not-link")) {
				doNotLink = true;
				outFile = outDirAppendable ~ "output.o";
				args[2] = outFile;
				args ~= "-c";
				continue;
			} else if (startsWith(l, "//T syntax-only")) {
				doNotLink = true;
				args ~= "-E";
				continue;
			} else if (startsWith(l, "//T run:")) {
				runCmd = new string(l[8 .. $]);
				runCmd = runArgsExpand(runCmd);
				cmdWords := split(strip(runCmd), ' ');
				runCmd = cmdWords[0];
				runArgs = cmdWords[1 .. $];
				continue;
			}

			malformedTest();
			return;
		}
		fclose(data);
		data = null;

		log = fopen(logFile.ptr, "w".ptr);
		if (log is null) {
			couldNotOpenLog(logFile);
			return;
		}

		// Setup the command.
		cmd: string = "volta";
		if (runCmd != "") {
			cmd = runCmd;
			args = runArgs;
		}

		// Get the command from the store.
		if (runCmd == "") {
			c := mCommandStore.getTool("volta");
			if (c is null) {
				missingCommand(cmd);
			}
			cmd = c.cmd;
			args ~= c.args;
		}

		// Finally run the compliler command.
		cmdGroup.run(cmd, args, compileDone, log);
	}

private:
	/**
	 * Expand %p etc in run: tags.
	 */
	fn runArgsExpand(args: string) string
	{
		sink: StringSink;
		percent: bool;

		foreach (i, c: char; args) {

			if (c != '%' && !percent) {
				sink.sink(args[i .. i+1]);
				continue;
			}
			if (c == '%' && !percent) {
				percent = true;
				continue;
			}
			switch (c) {
			case '%': sink.sink("%"); break;
			case 'p': sink.sink(srcDir); break;
			default:
				sink.sink("%");
				sink.sink(args[i .. i+1]); break;
			}
			percent = false;
		}

		return sink.toString();
	}

	/// Check error-line and error-message.
	fn verifyLogInformation() bool
	{
		if (expectedErrorLine == 0 && expectedErrorMessage.length == 0) {
			return true;
		}
		logtxt := cast(string)read(logFile);
		firstColon := logtxt.indexOf(':');
		if (firstColon == -1) {
			malformedError();
			return false;
		}
		file := logtxt[0 .. firstColon];
		logtxt = logtxt[firstColon+1 .. $];
		secondColon := logtxt.indexOf(':');
		if (secondColon == -1) {
			malformedError();
			return false;
		}
		line := toInt(logtxt[0 .. secondColon]);
		if (expectedErrorLine != 0 && line != expectedErrorLine) {
			lineMismatch(line, expectedErrorLine);
			return false;
		}
		errlen := expectedErrorMessage.length;
		logerr := logtxt;
		if (errlen < logerr.length) {
			logerr = logerr[0 .. errlen];
		}
		if (errlen > 0 && logerr.indexOf(expectedErrorMessage) == -1) {
			messageMismatch(logtxt, expectedErrorMessage);
			return false;
		}
		if (file != srcFile) {
			wrongFile(file);
			return false;
		}
		return true;
	}

	fn compileDone(retval: int)
	{
		/*
		 * Go over the result from the compilation of the test.
		 */

		// Check for invalid return from the compiler.
		if (retval != 0 && retval != 1) {
			return compilationPanic();
		}

		// Check for a expected compilation error.
		if (!expectedToCompile && retval == 1) {
			if (!verifyLogInformation()) {
				return;
			}
			return testOk();
		}

		// Check for missing expected failures
		if (!expectedToCompile && retval == 0) {
			return compilationSucceeded();
		}

		// Check for unexpected compilation failures.
		if (expectedToCompile && retval != 0) {
			return compilationFailed();
		}

		if (doNotLink || runCmd != "") {
			return testOk();
		}

		// Run the outputed file.
		cmdGroup.run(outFile, null, outputDone, log);
	}

	fn outputDone(retval: int)
	{
		// Check for bad retval from the test.
		if (retval != expectedRetval) {
			badRetval(retval, expectedRetval);
			return;
		}

		// Test Passed!
		testOk();
	}

	fn completelyDone(ok: bool, msg: string)
	{
		this.msg = msg;

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

	fn compilationPanic()
	{
		testFailure("compile returned invalid retval");
	}

	fn compilationFailed()
	{
		testFailure("test expected to compile, did not");
	}

	fn compilationSucceeded()
	{
		testFailure("test expected to not compile, did");
	}

	fn badRetval(retval: int, expected: int)
	{
		str := format("test return wrong value %s, expected %s", retval, expected);
		testFailure(str);
	}

	fn missingTest()
	{
		testFailure("missing test");
	}

	fn missingCommand(command: string)
	{
		testFailure(format("missing command '%s'", command));
	}

	fn malformedTest()
	{
		testFailure("malformed test");
	}

	fn malformedError()
	{
		testFailure("test generated a malformed error message");
	}

	fn lineMismatch(line: int, expected: int)
	{
		str := format("test error line was expected at %s was at line %s", expected, line);
		testFailure(str);
	}

	fn messageMismatch(message: string, expectedMessage: string)
	{
		str := format("test error message was '%s' not '%s'", message, expectedMessage);
		testFailure(str);
	}

	fn wrongFile(file: string)
	{
		str := format("test error filename is %s, not %s", file, srcFile);
		testFailure(str);
	}

	fn couldNotOpenLog(logFile: string)
	{
		str := format("could not open logfile '%s'", logFile);
		testFailure(str);
	}
}

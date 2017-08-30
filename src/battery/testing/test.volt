// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/tesla/license.volt (BOOST ver. 1.0).
module battery.testing.test;

import core.c.stdio : FILE;

import build.util.cmdgroup;
import battery.testing.project;


/**
 * Test status 
 */
enum Result
{
	FAIL,  ///< Test failed, regressed, is expected to succeed.
	XFAIL, ///< Test failed, but is expected to fail.
	XPASS, ///< Test passed, improved, but is expected to fail.
	PASS,  ///< Test passed, and that was expected.
	SKIPPED,  ///< Test was skipped.
}

/**
 * Base class for all types of tests.
 */
abstract class Test
{
public:
	name: string;
	msg: string;
	project: TestProject;

	result: Result;


public:
	abstract fn runTest(CmdGroup);
	abstract fn getOutput() string;
	abstract fn getError() string;
}

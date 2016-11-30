// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/tesla/license.volt (BOOST ver. 1.0).
module battery.testing.output.stdio;

import watt.io;
import battery.testing.test;


fn writeToStdio(tests: Test[], out hasRegression: bool)
{
	printOk: bool = false;
	printImprovments: bool = true;
	printFailing: bool = true;
	printRegressions: bool = true;

	total := cast(int)tests.length;
	pass, xpass, xfail, fail: int;

	foreach (test; tests) {
		final switch (test.result) with (Result) {
		case XPASS:
			xpass++;
			if (!printImprovments) {
				break;
			}
			writefln("%s: %s, improved!", test.name, test.msg);
			break;
		case PASS:
			pass++;
			if (!printOk) {
				break;
			}
			writefln("%s: %s.", test.name, test.msg);
			break;
		case XFAIL:
			xfail++;
			if (!printFailing) {
				break;
			}
			writefln("%s: %s", test.name, test.msg);
			break;
		case FAIL:
			fail++;
			if (!printRegressions) {
				break;
			}
			writefln("%s: %s, regressed!", test.name, test.msg);
			break;
		}
		output.flush();
	}

	passed := pass + xpass;
	failed := fail + xfail;

	rate := cast(int)((1000.0 * passed) / total);
	writefln("Summary: %s tests, %s pass%s, %s failure%s, %s.%s%% pass rate, %s regressions, %s improvements.",
	       total,
	       passed, (passed == 1 ? "" : "es"),
	       failed, (failed == 1 ? "" : "s"),
	       rate / 10, rate % 10, fail, xpass);

	hasRegression = fail != 0;
}

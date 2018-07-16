module test;

import semver = watt.text.semver;
import llvmVersion = battery.frontend.llvmVersion;

global tests := [
"6.0.0",
"LlvmVersion6", "LlvmVersion6_0", "LlvmVersion6_0_0",
"7.0.1",
"LlvmVersion7", "LlvmVersion7_0", "LlvmVersion7_0_1",
"3.9.0-svn",
"LlvmVersion3", "LlvmVersion3_9", "LlvmVersion3_9_0",
"1.2.3",
"LlvmVersion1", "LlvmVersion1_2", "LlvmVersion1_2_3",
"7.0.0",
"LlvmVersion7", "LlvmVersion7_0", "LlvmVersion7_0_0",
];

fn pop() string
{
	if (tests.length == 0) {
		return null;
	}
	val := tests[0];
	tests = tests[1 .. $];
	return val;
}

fn main() i32
{
	while (tests.length > 0) {
		testVersionStr := pop();
		if (!semver.Release.isValid(testVersionStr)) {
			return 1;
		}
		testVersion := new semver.Release(testVersionStr);

		a := llvmVersion.identifiers(testVersion);
		b: string[3];
		b[0] = pop(); b[1] = pop(); b[2] = pop();
		if (a[..] != b[..]) {
			return 2;
		}
	}
	return 0;
}


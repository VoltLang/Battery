module test;

import io = watt.io.std;
import semver = watt.text.semver;
import llvmVersion = battery.frontend.llvmVersion;


global tests := [
"3.9.0-svn",
"LlvmVersion3", "LLVMVersion3", "LLVMVersion3_9", "LLVMVersion3_9_0",
"1.2.3",
"LlvmVersion1", "LLVMVersion1", "LLVMVersion1_2", "LLVMVersion1_2_3",
"7.0.1",
"LlvmVersion7", "LLVMVersion7", "LLVMVersion7_0", "LLVMVersion7_0_1",
	"LLVMVersion7AndAbove",
"8.3.0",
"LlvmVersion8", "LLVMVersion8", "LLVMVersion8_3", "LLVMVersion8_3_0",
	"LLVMVersion7AndAbove",
	"LLVMVersion8AndAbove",
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

		as := llvmVersion.identifiers(testVersion);
		foreach (a; as) {
			b := pop();
			if (a != b) {
				io.error.writefln("%s != %s", a, b);
				return 2;
			}
		}
	}
	return 0;
}


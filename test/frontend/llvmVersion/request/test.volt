// Copyright 2026, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
module test;

import io = watt.io.std;
import semver = watt.text.semver;
import llvmVersion = battery.frontend.llvmVersion;


fn checkRequest(requestStr: string, actualStr: string, expected: bool) i32
{
	req: llvmVersion.LLVMVersionRequest;
	if (!llvmVersion.parseRequest(requestStr, out req)) {
		io.error.writefln("failed to parse '%s'", requestStr);
		return 1;
	}

	actual := new semver.Release(actualStr);
	if (req.matches(actual) != expected) {
		io.error.writefln("'%s' match '%s' expected %s", requestStr, actualStr, expected);
		return 2;
	}

	if (req.toString() != requestStr) {
		io.error.writefln("'%s'.toString() == '%s'", requestStr, req.toString());
		return 3;
	}

	return 0;
}

fn main() i32
{
	requests := [
		"14", "14", "14.0", "14.0", "14.0.6", "14.0.6", "14.1", "14.1",
	];
	actuals := [
		"14.0.6", "15.0.0", "14.0.6", "14.1.0", "14.0.6", "14.0.5",
		"14.1.0", "14.0.6",
	];
	expected := [
		true, false, true, true, true, false, true, false,
	];

	foreach (i; 0 .. requests.length) {
		if (checkRequest(requests[i], actuals[i], expected[i]) != 0) {
			return 1;
		}
	}

	req: llvmVersion.LLVMVersionRequest;
	if (!llvmVersion.parseRequest("14.1.6", out req)) {
		return 2;
	}
	if (req.suffix() != "-14") {
		io.error.writefln("suffix() == '%s'", req.suffix());
		return 3;
	}

	if (llvmVersion.parseRequest("14.a", out req)) {
		return 4;
	}

	return 0;
}

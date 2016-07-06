// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.d;

import watt.process : searchPath;
import battery.configuration;


version (MSVC) {
	enum RdmdCommand = "rdmd.exe";
	enum DmdCommand = "dmd.exe";
} else version (Linux) {
	enum RdmdCommand = "rdmd";
	enum DmdCommand = "dmd";
} else version (OSX) {
	enum RdmdCommand = "rdmd";
	enum DmdCommand = "dmd";
} else {
	static assert(false, "native platform not supported");
}

Rdmd getRdmd(string path)
{
	rdmd := new Rdmd();
	rdmd.rdmd = searchPath(RdmdCommand, path);
	rdmd.dmd = searchPath(DmdCommand, path);
	return rdmd;
}

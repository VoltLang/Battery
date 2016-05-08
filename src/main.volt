// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module main;

import watt.io : writefln;
import watt.process : getEnv;

import uni = uni.core;

import battery.license;
import battery.compile;
import battery.configuration;
import battery.policy.host : getHostConfig;
import battery.policy.rt : getRtCompile;


int main(string[] args)
{
	foreach (arg; args[1 .. $]) {
		if (arg == "--license") {
			printLicense();
			return 0;
		}
	}

	doBuild();

	return 0;
}

void doBuild()
{
	auto path = getEnv("PATH");
	auto config = getHostConfig(path);
	auto vrt = getRtCompile(config);


	auto c = new Compile();
	c.deps = [vrt];
	c.name = "a.out";
	c.srcRoot = "src";
	c.src = ["src/main.volt"];
	c.derivedTarget = "a.out";

	auto ret = buildCmd(config, c);

	auto ins = new uni.Instance();
	auto t = ins.fileNoRule(c.derivedTarget);
	t.deps = new uni.Target[](c.src.length);

	foreach (i, src; c.src) {
		t.deps[i] = ins.file(src);
	}

	t.rule = new uni.Rule();
	t.rule.cmd = ret[0];
	t.rule.print = "  VOLTA  " ~ c.name;
	t.rule.args = ret[1 .. $];

	uni.build(t, 2);
}

void printLicense()
{
	foreach (l; licenseArray) {
		writefln(l);
	}
}

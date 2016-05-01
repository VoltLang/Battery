// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.configuration;

import battery.defines;


/**
 * Holds information about the Volta compiler and runtime.
 */
class Volta
{
	string cmd;

	string rtBin;
	string rtDir;

	string[][4] rtLibs;
}

/**
 * A build configuration for one or more builds.
 *
 * This can be shared between multiple builds. When cross-compiling there will
 * be multiple configurations, one for the target and another for the host.
 */
class Configuration
{
public:
	Volta volta;

	Arch arch;
	Platform platform;

	string[] defs;

	string buildDir;

	uint hash;


public:
	string buildDirDerived;


public:
	this(Volta volta)
	{
		this.volta = volta;
	}
}

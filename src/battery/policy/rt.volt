// Copyright © 2015-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.policy.rt;

import battery.backend.compile;
import battery.configuration;


Compile getRtCompile(Configuration config)
{
	vrt := new Compile();
	vrt.library = true;
	vrt.derivedTarget = config.volta.rtBin;
	vrt.srcRoot = config.volta.rtDir;
	vrt.libs = config.volta.rtLibs[config.platform];
	vrt.name = "vrt";

	return vrt;
}

// Copyright 2018, Bernard Helyer.
// Copyright 2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Helper code for Visual Studio detection.
 */
module battery.detect.msvc.util;

import watt = [watt.io.file, watt.text.path];

import battery.detect.msvc;
import battery.detect.msvc.windows;


fn addLinkAndCL(ref result: Result, extraPath: string)
{
	// Add the extra path to the install directory.
	binPath := watt.concatenatePath(result.vcInstallDir, extraPath);

	linkCmd := watt.concatenatePath(binPath, "link.exe");
	if (watt.exists(linkCmd)) {
		result.linkCmd = linkCmd;
	}

	clCmd := watt.concatenatePath(binPath, "cl.exe");
	if (watt.exists(clCmd)) {
		result.clCmd = clCmd;
	}
}

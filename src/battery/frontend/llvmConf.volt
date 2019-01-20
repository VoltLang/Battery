// Copyright 2018, Bernard Helyer.
// Copyright 2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Code for handling a small config file that declares information regarding LLVM.
 *
 * This is for building the compiler on Windows systems, where we can't use
 * `llvm-config`.
 */
module battery.frontend.llvmConf;

import getopt = watt.text.getopt;
import   file = watt.io.file;
import   path = [watt.path, watt.text.path];


/*!
 * Parse llvmConf-related command line arguments.
 *
 * This parses the argument `--llvmconf` from `args` and also scans any directories.
 */
fn parseArguments(ref args: string[], out llvmConf: string)
{
	configPath: string;
	if (!getopt.getopt(ref args, "llvmconf", ref llvmConf)) {
		scan(args, out llvmConf);
	}
}


private:

enum DefaultLlvmTomlName = "llvm.toml";

fn scan(args: string[], out llvmConf: string) bool
{
	foreach (arg; args) {
		if (arg[0] == '-') {
			continue;
		}
		if (scan(arg, out llvmConf)) {
			return true;
		}
	}
	return false;
}

fn scan(fpath: string, out llvmConf: string) bool
{
	proposedPath := path.concatenatePath(fpath, DefaultLlvmTomlName);
	if (file.exists(proposedPath)) {
		llvmConf = proposedPath;
		return true;
	}
	return false;
}

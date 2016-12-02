// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.testing.tester;

import watt.path : dirSeparator;
import watt.text.string : endsWith;

import battery.interfaces;
import battery.configuration;
import battery.policy.tools;
import battery.backend.command;
import battery.testing.project;
import battery.testing.main;

class Tester
{
private:
	mDrv: Driver;
	mLib: Lib[];
	mExe: Exe[];
	mConfig: Configuration;
	mHostConfig: Configuration;


public:
	this(Driver drv)
	{
		mDrv = drv;
	}

	fn test(config: Configuration, hostConfig: Configuration,
		libs: Lib[], exes: Exe[])
	{
		mConfig = config;
		mHostConfig = hostConfig;
		mLib = libs;
		mExe = exes;

		projects: Project[];

		foreach (exe; exes) {
			if (exe.testDir is null) {
				continue;
			}

			exeTool := getCommandFromExe(exe);
			voltaTool := getVoltaCommand(exe);
			projects ~= new Project(exe.name, exe.testDir);
			projects[$-1].addCommand("volta", voltaTool);
			projects[$-1].addCommand(exe.name, exeTool);
		}

		foreach (lib; libs) {
			if (lib.testDir is null) {
				continue;
			}

			voltaTool := getVoltaCommand(lib);
			projects ~= new Project(lib.name, lib.testDir);
			projects[$-1].addCommand("volta", voltaTool);
		}

		if (projects.length == 0) {
			return;
		}

		testMain(projects);
	}

	fn getCommandFromExe(exe: Exe) Command
	{
		cmd := new Command();
		cmd.name = exe.name;
		cmd.print = "  " ~ exe.name ~ " ";
		cmd.cmd = exe.bin;
		return cmd;
	}

	fn getVoltaCommand(testProj: Base) Command
	{
		gen: ArgsGenerator;
		gen.setup(mHostConfig is null ? mConfig : mHostConfig, mLib, mExe);

		volta := new Command();
		volta.name = "volta";
		volta.print = VoltaPrint;
		volta.cmd = gen.genVolted();

		// Should we replace the command with the one given on the command line.
		tool := mDrv.getTool(false, "volta");
		if (tool !is null) {
			volta.cmd = tool.cmd;
			volta.args = volta.args;
		}

		// Add deps and return files to be added to arguments.
		fn cb(base: Base) string[] {
			// Completely skip Exes.
			exe := cast(Exe)base;
			if (exe !is null) {
				return null;
			}

			files: string[];
			foreach (asmpath; base.srcAsm) {
				files ~= gen.genFileO(asmpath);
			}

			files ~= gen.genVoltLibraryO(base.name);

			return files;
		}

		// Generate arguments and collect files.
		volta.args ~= gen.genVoltaArgs(testProj, cb);

		return volta;
	}
}

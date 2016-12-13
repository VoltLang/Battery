// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
module battery.testing.tester;

import watt.path : dirSeparator;
import watt.text.string : endsWith;
import watt.process;

import battery.interfaces;
import battery.configuration;
import battery.policy.tools;
import battery.backend.command;
import battery.util.system;
import build.util.cmdgroup;
import battery.testing.project;
import battery.testing.test;
import battery.testing.searcher;
import battery.testing.output.stdio;
import battery.testing.output.xml;


private enum DEFAULT_DIR = "test";
private enum DEFAULT_RESULTS = "results.xml";

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

	fn testMain(projects: Project[])
	{
		cmdGroup := new CmdGroup(retrieveEnvironment(), processorCount());
		tests: Test[];
		foreach (i, project; projects) {
			mDrv.info("  TEST     %s", project.path);
			cfg := new Configuration();
			foreach (k, v; project.commands) {
				cfg.addTool(k, v.cmd, v.args);
			}

			s := new Searcher(cfg);
			tests ~= s.search(project, project.path);
		}

		foreach (test; tests) {
			test.runTest(cmdGroup);
		}

		cmdGroup.waitAll();

		hasRegression: bool;
		host := getBuiltIdent();
		writeXmlFile(host, DEFAULT_RESULTS, tests);
		writeToStdio(tests, out hasRegression);
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

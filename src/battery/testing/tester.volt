// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
module battery.testing.tester;

import watt.io;
import watt.path : dirSeparator;
import watt.text.string : endsWith, indexOf;
import watt.process;

import battery.interfaces;
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
	mFilter: string;


public:
	this(Driver drv)
	{
		mDrv = drv;
	}

	fn test(config: Configuration, hostConfig: Configuration,
		libs: Lib[], exes: Exe[],
		filter: string)
	{
		mConfig = config;
		mHostConfig = hostConfig;
		mLib = libs;
		mExe = exes;
		mFilter = filter;

		projects: TestProject[];

		foreach (exe; exes) {
			if (exe.testFiles.length == 0) {
				continue;
			}

			exeTool := getCommandFromExe(exe);
			voltaTool := getVoltaCommand(exe);
			projects ~= new TestProject(exe.name, exe.testFiles);
			projects[$-1].addCommand("volta", voltaTool);
			if (exe.name != "volta") {
				projects[$-1].addCommand(exe.name, exeTool);
			}
		}

		foreach (lib; libs) {
			if (lib.testFiles.length == 0) {
				continue;
			}

			voltaTool := getVoltaCommand(lib);
			projects ~= new TestProject(lib.name, lib.testFiles);
			projects[$-1].addCommand("volta", voltaTool);
		}

		if (projects.length == 0) {
			return;
		}

		testMain(projects);
	}

	fn testMain(projects: TestProject[])
	{
		cmdGroup := new CmdGroup(mConfig.env, processorCount());
		tests: Test[];
		foreach (i, project; projects) {
			foreach (path; project.paths) {
				mDrv.info("  TEST     %s", path);
				cfg := new Configuration();
				cfg.arch = mConfig.arch;
				cfg.platform = mConfig.platform;
				foreach (name, command; mConfig.tools) {
					cfg.tools[name] = command;
				}
				foreach (name, command; project.commands) {
					cfg.tools[name] = command;
				}

				s := new Searcher(cfg);
				tests ~= s.search(project, path);
			}
		}

		foreach (test; tests) {
			if (mFilter is null || test.name.indexOf(mFilter) >= 0) {
				test.runTest(cmdGroup);
			} else {
				test.result = Result.SKIPPED;
			}
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

	fn getVoltaCommand(testProj: Project) Command
	{
		gen: ArgsGenerator;
		gen.setup(mHostConfig is null ? mConfig : mHostConfig, mLib, mExe);

		volta := new Command();
		volta.name = VoltaName;
		volta.print = VoltaPrint;
		volta.cmd = gen.genVolted();

		// Should we replace the command with the one given on the command line.
		tool := gen.config.getTool(VoltaName);
		if (tool !is null) {
			volta.cmd = tool.cmd;
			volta.args = tool.args;
		}

		// Add deps and return files to be added to arguments.
		fn cb(base: Project) string[] {
			// Completely skip Exes.
			exe := cast(Exe)base;
			if (exe !is null) {
				return null;
			}

			// Start with the object files.
			files := base.srcObj;

			foreach (asmpath; base.srcAsm) {
				files ~= gen.genAsmO(asmpath);
			}

			foreach (spath; base.srcS) {
				files ~= gen.genSO(spath);
			}

			foreach (cpath; base.srcC) {
				files ~= gen.genCO(cpath);
			}

			if (gen.config.isLTO) {
				files ~= gen.genVoltA(base.name);
			} else {
				files ~= gen.genVoltO(base.name);
			}

			return files;
		}

		// Generate arguments and collect files.
		flags := ArgsGenerator.Kind.VoltaSrc | ArgsGenerator.Kind.VoltaLink;
		volta.args ~= gen.genVoltArgs(testProj, flags, cb);

		return volta;
	}
}

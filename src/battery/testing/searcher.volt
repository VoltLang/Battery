// Copyright © 2012-2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module battery.testing.searcher;

import watt.path;
import watt.io;
import watt.io.file;
import watt.text.format;
import watt.text.string;
import json = watt.json;
import core.exception;
import core.c.stdio;

import battery.configuration;
import battery.testing.test;
import battery.testing.project;
import battery.testing.regular;
import battery.testing.btj;


/**
 * Searches for tests cases.
 */
class Searcher
{
public:
	mTests: Test[];
	mCommandStore: Configuration;


public:
	this(cs: Configuration)
	{
		mCommandStore = cs;
	}

	fn search(project: Project, dir: string) Test[]
	{
		searchBase(project, dir, dir);

		return mTests;
	}


private:
	fn searchBase(project: Project, base: string, dir: string)
	{
		fn hit(file: string)
		{
			switch (file) {
			case "", ".", "..":
				return;
			case "battery.tests.json":
				btj := new BatteryTestsJson();
				btj.parse(format("%s%s%s", dir, dirSeparator, file));
				searchJson(project, dir, dir, btj);
				return;
			default:
				fullpath := format("%s%s%s", dir, dirSeparator, file);
				if (!isDir(fullpath)) {
					return;
				}
				searchBase(project, base, fullpath);
				return;
			}
		}

		searchDir(dir, "*", hit);
	}

	fn searchJson(project: Project, base: string, dir: string, btj: BatteryTestsJson)
	{
		fn hit(file: string) {
			switch (file) {
			case "", ".", "..":
				return;
			default:
				if (globMatch(file, btj.pattern)) {
					test := dir[base.length + 1 .. $];
					mTests ~= new Regular(dir, test, file,
						btj, project, mCommandStore);
					return;
				}
				fullpath := format("%s%s%s", dir, dirSeparator, file);
				if (!isDir(fullpath)) {
					return;
				}
				searchJson(project, base, fullpath, btj);
			}
		}

		searchDir(dir, "*", hit);
	}
}

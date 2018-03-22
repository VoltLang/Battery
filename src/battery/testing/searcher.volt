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

	fn search(project: TestProject, dir: string) Test[]
	{
		btj := new BatteryTestsJson();
		btj.parse(dir);
		dirnam := dirName(dir);
		searchJson(project, dirnam, dirnam, btj);

		return mTests;
	}


private:
	fn searchJson(project: TestProject, base: string, dir: string, btj: BatteryTestsJson)
	{
		fn hit(file: string) SearchStatus {
			switch (file) {
			case "", ".", "..":
				return SearchStatus.Continue;
			default:
				if (globMatch(file, btj.pattern)) {
					test := dir[base.length + 1 .. $];
					mTests ~= new Regular(dir, test, file,
						btj, project, mCommandStore);
					return SearchStatus.Continue;
				}
				fullpath := format("%s%s%s", dir, dirSeparator, file);
				if (!isDir(fullpath)) {
					return SearchStatus.Continue;
				}
				searchJson(project, base, fullpath, btj);
			}
			return SearchStatus.Continue;
		}

		searchDir(dir, "*", hit);
	}
}

module battery.testing.searcher;

import watt.path;
import watt.io;
import watt.io.file;
import core.stdc.stdio;

import battery.configuration;
import battery.testing.test;
import battery.testing.legacy;


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

	fn search(dir: string, prefix: string) Test[]
	{
		search(dir, dir, prefix);

		return mTests;
	}


private:
	fn search(base: string, dir: string, prefix: string)
	{
		fn hit(file: string)
		{
			switch (file) {
			case "", ".", "..":
				return;
			case "tesla.simple.txt":
				searchSimple(dir, dir, prefix);
				return;
			default:
				fullpath := dir ~ dirSeparator ~ file;
				if (!isDir(fullpath)) {
					return;
				}
				search(base, fullpath, prefix);
				return;
			}
		}

		searchDir(dir, "*", hit);
	}

	fn searchSimple(base: string, dir: string, prefix: string)
	{
		fn hit(file: string) {
			switch (file) {
			case "", ".", "..", "deps", "mixin":
				return;
			case "test.volt":
				test := dir[base.length + 1 .. $];
				mTests ~= new Legacy(dir, test, mCommandStore, prefix);
				return;
			default:
				fullpath := dir ~ dirSeparator ~ file;
				if (!isDir(fullpath)) {
					return;
				}
				searchSimple(base, fullpath, prefix);
			}
		}

		searchDir(dir, "*", hit);
	}
}

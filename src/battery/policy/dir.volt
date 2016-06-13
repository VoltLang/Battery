// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds the code for searching a directory and automatically creating
 * a project from that.
 */
module battery.policy.dir;

import io = watt.io;
import watt.io.file : exists, searchDir, isDir;
import watt.path : baseName, dirName, dirSeparator;
import watt.text.string : endsWith, replace;
import watt.conv : toLower;

import battery.interfaces;
import battery.configuration;
import battery.util.path;
import battery.util.file : getLinesFromFile;
import battery.policy.cmd : ArgParser;


enum PathSrc        = "src";
enum PathRes        = "res";
enum PathMain       = "src/main.volt";
enum PathBatteryCmd = "battery.cmd";

/**
 * Scan a directory and see what it holds.
 */
Base scanDir(Driver drv, string path)
{
	Scanner s;

	s.scan(drv, fixPath(path));

	if (!s.hasPath) {
		drv.abort("path '%s' not found", s.path);
	}

	if (!s.hasSrc) {
		drv.abort("path '%s' does not have a '%s' folder", s.path, PathSrc);
	}

	if (s.filesVolt is null) {
		drv.abort("path '%s' has no volt files", s.pathSrc);
	}

	// Setup binary name.
	if (s.hasMain) {
		s.bin = s.path ~ dirSeparator ~ s.name;
	}

	// Create exectuable or library.
	ret : Base;
	if (s.hasMain) {
		drv.info("scanned '%s' found executable", s.path);
		ret = s.buildExe();
	} else {
		drv.info("scanned '%s' found library", s.path);
		ret = s.buildLib();
	}

	if (s.hasBatteryCmd) {
		libs : Lib[];
		exes : Exe[];
		args : string[];
		getLinesFromFile(s.pathBatteryCmd, ref args);
		ap := new ArgParser(drv);
		ap.parse(args, path ~ dirSeparator, ret, out libs, out exes);
	}

	return ret;
}

struct Scanner
{
public:
	Driver drv;

	string bin;
	string name;

	bool hasSrc;
	bool hasRes;
	bool hasPath;
	bool hasMain;
	bool hasBatteryCmd;

	string path;
	string pathSrc;
	string pathRes;
	string pathMain;
	string pathBatteryCmd;

	string[] filesC;
	string[] filesVolt;


public:



public:
	void scan(Driver drv, string path)
	{
		this.drv = drv;
		this.path = path;

		name           = toLower(baseName(path));
		pathSrc        = path ~ dirSeparator ~ PathSrc;
		pathRes        = path ~ dirSeparator ~ PathRes;
		pathMain       = path ~ dirSeparator ~ PathMain;
		pathBatteryCmd = path ~ dirSeparator ~ PathBatteryCmd;

		hasPath        = isDir(path);
		hasSrc         = isDir(pathSrc);
		hasRes         = isDir(pathRes);
		hasMain        = exists(pathMain);
		hasBatteryCmd  = exists(pathBatteryCmd);

		if (!hasSrc) {
			return;
		}

		filesC    = drv.deepScan(pathSrc, "c");
		filesVolt = drv.deepScan(pathSrc, "volt");
	}

	Exe buildExe()
	{
		exe := new Exe();
		exe.name = name;
		exe.srcDir = pathSrc;
		exe.srcVolt = [pathMain];
		exe.bin = bin;

		return exe;
	}

	Lib buildLib()
	{
		lib := new Lib();
		lib.name = name;
		lib.srcDir = pathSrc;

		return lib;
	}
}

string[] deepScan(Driver drv, string path, string ending)
{
	ret : string[];

	void hit(string p) {
		switch (p) {
		case ".", "..": return;
		default:
		}

		auto full = path ~ dirSeparator ~ p;

		if (isDir(full)) {
			ret ~= deepScan(drv, full, ending);
		} else if (endsWith(p, ending)) {
			ret ~= full;
		}
	}

	searchDir(path, "*", hit);

	return ret;
}

string fixPath(string path)
{
	version (Windows) {
		return replace(path, "/", dirSeparator);
	} else {
		return path;
	}
}

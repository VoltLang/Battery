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
import watt.text.path : normalizePath;
import watt.text.string : endsWith, replace;
import watt.conv : toLower;

import battery.interfaces;
import battery.configuration;
import battery.util.file : getLinesFromFile;
import battery.policy.cmd : ArgParser;


enum PathSrc        = "src";
enum PathRes        = "res";
enum PathMainD      = "main.d";
enum PathMainVolt   = "main.volt";
enum PathBatteryTxt = "battery.txt";

/**
 * Scan a directory and see what it holds.
 */
Base scanDir(Driver drv, string path)
{
	Scanner s;

	s.scan(drv, normalizePath(path));

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
	if (s.hasMainVolt) {
		s.bin = s.path ~ dirSeparator ~ s.name;
	}

	// Create exectuable or library.
	ret : Base;
	if (s.hasMainVolt) {
		drv.info("scanned '%s' found executable", s.path);
		exe := s.buildExe();
		drv.add(exe);
		ret = exe;
	} else {
		drv.info("scanned '%s' found library", s.path);
		lib := s.buildLib();
		drv.add(lib);
		ret = lib;
	}

	if (s.hasBatteryCmd) {
		args : string[];
		getLinesFromFile(s.pathBatteryTxt, ref args);
		ap := new ArgParser(drv);
		ap.parse(args, path ~ dirSeparator, ret);
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
	bool hasMainD;
	bool hasMainVolt;
	bool hasBatteryCmd;

	string path;
	string pathSrc;
	string pathRes;
	string pathMainD;
	string pathMainVolt;
	string pathBatteryTxt;

	string[] filesC;
	string[] filesVolt;


public:
	void scan(Driver drv, string path)
	{
		this.drv = drv;
		this.path = path;

		name           = toLower(baseName(path));
		pathSrc        = path ~ dirSeparator ~ PathSrc;
		pathRes        = path ~ dirSeparator ~ PathRes;
		pathMainD      = pathSrc ~ dirSeparator ~ PathMainD;
		pathMainVolt   = pathSrc ~ dirSeparator ~ PathMainVolt;
		pathBatteryTxt = path ~ dirSeparator ~ PathBatteryTxt;

		hasPath        = isDir(path);
		hasSrc         = isDir(pathSrc);
		hasRes         = isDir(pathRes);
		hasMainD       = exists(pathMainD);
		hasMainVolt    = exists(pathMainVolt);
		hasBatteryCmd  = exists(pathBatteryTxt);

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
		exe.srcC = filesC;
		exe.srcVolt = [pathMainVolt];
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

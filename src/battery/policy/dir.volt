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


enum PathSrc = "src";
enum PathRes = "res";
enum PathMain = "src/main.volt";



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
		version (Windows) {
			s.bin ~= ".exe";
		}
	}

	// Create exectuable or library.
	if (s.hasMain) {
		drv.info("scanned '%s' found executable", s.path);
		return s.buildExe();
	} else {
		drv.info("scanned '%s' found library", s.path);
		return s.buildLib();
	}
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

	string path;
	string pathSrc;
	string pathRes;
	string pathMain;

	string[] filesC;
	string[] filesVolt;


public:
	void scan(Driver drv, string path)
	{
		this.drv = drv;
		this.path = path;

		name     = toLower(baseName(path));
		pathSrc  = path ~ dirSeparator ~ PathSrc;
		pathRes  = path ~ dirSeparator ~ PathRes;
		pathMain = path ~ dirSeparator ~ PathMain;

		hasPath  = isDir(path);
		hasSrc   = isDir(pathSrc);
		hasRes   = isDir(pathRes);
		hasMain  = exists(pathMain);

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
		exe.src = [pathMain];
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

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
import battery.util.file : getLinesFromFile;
import battery.policy.cmd : ArgParser;


enum PathRt         = "rt";
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

	s.scan(drv, path);

	if (s.name == "volta") {
		return scanVolta(drv, ref s);
	}

	if (!s.hasPath) {
		drv.abort("path '%s' not found", s.inputPath);
	}

	if (!s.hasSrc) {
		drv.abort("path '%s' does not have a '%s' folder", s.inputPath, PathSrc);
	}

	if (s.filesVolt is null) {
		drv.abort("path '%s' has no volt files", s.pathSrc);
	}

	// Create exectuable or library.
	ret : Base;
	if (s.hasMainVolt) {
		drv.info("detected executable project in folder '%s'", s.inputPath);
		exe := s.buildExe();
		ret = exe;
	} else {
		drv.info("detected library project in folder '%s'", s.inputPath);
		lib := s.buildLib();
		ret = lib;
	}

	processBatteryCmd(drv, ret, ref s);

	return ret;
}

Base scanVolta(Driver drv, ref Scanner s)
{
	if (!s.hasRt) {
		drv.abort("volta needs a 'rt' folder");
	}

	if (!s.hasMainD) {
		drv.abort("volta needs 'src/main.d'");
	}

	drv.info("detected Volta compiler in folder '%s'", s.inputPath);

	// Scan the runtime.
	rt := cast(Lib)scanDir(drv, s.inputPath ~ dirSeparator ~ PathRt);
	if (rt is null) {
		drv.abort("Volta '%s' runtime must be a library", s.inputPath);
	}
	drv.add(rt);

	exe := new Exe();
	exe.name = s.name;
	exe.srcDir = s.pathSrc;
	exe.bin = s.pathDerivedBin;

	processBatteryCmd(drv, exe, ref s);

	return exe;
}

void processBatteryCmd(Driver drv, Base b, ref Scanner s)
{
	if (s.hasBatteryCmd) {
		args : string[];
		getLinesFromFile(s.pathBatteryTxt, ref args);
		ap := new ArgParser(drv);
		ap.parse(args, s.path ~ dirSeparator, b);
	}
}

struct Scanner
{
public:
	Driver drv;
	string inputPath;

	string name;

	bool hasRt;
	bool hasSrc;
	bool hasRes;
	bool hasPath;
	bool hasMainD;
	bool hasMainVolt;
	bool hasBatteryCmd;

	string path;
	string pathRt;
	string pathSrc;
	string pathRes;
	string pathMainD;
	string pathMainVolt;
	string pathBatteryTxt;
	string pathDerivedBin;

	string[] filesC;
	string[] filesVolt;


public:
	void scan(Driver drv, string inputPath)
	{
		this.drv = drv;
		this.inputPath = inputPath;
		this.path = drv.normalizePath(inputPath);

		if (path is null) {
			return;
		}

		name           = toLower(baseName(path));
		pathRt         = getInPath(PathRt);
		pathSrc        = getInPath(PathSrc);
		pathRes        = getInPath(PathRes);
		pathMainD      = pathSrc ~ dirSeparator ~ PathMainD;
		pathMainVolt   = pathSrc ~ dirSeparator ~ PathMainVolt;
		pathBatteryTxt = getInPath(PathBatteryTxt);
		pathDerivedBin = getInPath(name);

		hasPath        = isDir(path);
		hasRt          = isDir(pathRt);
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

	string getInPath(string file)
	{
		return drv.removeWorkingDirectoryPrefix(
			path ~ dirSeparator ~ file);
	}

	Exe buildExe()
	{
		exe := new Exe();
		exe.name = name;
		exe.srcDir = pathSrc;
		exe.srcC = filesC;
		exe.srcVolt = [pathMainVolt];
		exe.bin = pathDerivedBin;

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

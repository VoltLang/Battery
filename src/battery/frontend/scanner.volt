// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds the code for searching a directory and automatically creating
 * a project from that.
 */
module battery.frontend.scanner;

import io = watt.io;
import watt.io.file : exists, searchDir, isDir;
import watt.path : baseName, dirName, dirSeparator;
import watt.text.string : endsWith, replace;
import watt.conv : toLower;

import battery.interfaces;
import battery.configuration;
import battery.util.file : getLinesFromFile;
import battery.frontend.parameters : ArgParser;


enum PathRt         = "rt";
enum PathSrc        = "src";
enum PathRes        = "res";
enum PathTest       = "test";
enum PathMainD      = "main.d";
enum PathMainVolt   = "main.volt";
enum PathBatteryTxt = "battery.txt";

/**
 * Scan a directory and see what it holds.
 */
fn scanDir(drv: Driver, path: string) Base
{
	s: Scanner;
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
	ret: Base;
	if (s.hasMainVolt) {
		drv.info("detected executable project in folder '%s'", s.inputPath);
		exe := s.buildExe();
		ret = exe;
	} else {
		drv.info("detected library project in folder '%s'", s.inputPath);
		lib := s.buildLib();
		ret = lib;
	}

	if (s.hasTest) {
		drv.info("%s detected tests in folder '%s'", ret.name, s.pathTest);
		ret.testDir = s.pathTest;
	}

	if (s.hasRes) {
		drv.info("%s detected resources in folder '%s'", ret.name, s.pathRes);
		ret.stringPaths ~= s.pathRes;
	}

	processBatteryCmd(drv, ret, ref s);

	return ret;
}

fn scanVolta(drv: Driver, ref s: Scanner) Base
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
	exe.isInternalD = true;
	exe.srcVolt ~= s.pathMainD;

	processBatteryCmd(drv, exe, ref s);

	return exe;
}

fn processBatteryCmd(drv: Driver, b: Base, ref s: Scanner)
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
	drv: Driver;
	inputPath: string;

	name: string;

	hasRt: bool;
	hasSrc: bool;
	hasRes: bool;
	hasPath: bool;
	hasMainD: bool;
	hasMainVolt: bool;
	hasBatteryCmd: bool;
	hasTest: bool;

	path: string;
	pathRt: string;
	pathSrc: string;
	pathRes: string;
	pathMainD: string;
	pathMainVolt: string;
	pathBatteryTxt: string;
	pathDerivedBin: string;
	pathTest: string;

	filesC: string[];
	filesVolt: string[];


public:
	fn scan(drv: Driver, inputPath: string)
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
		pathTest       = getInPath(PathTest);

		hasPath        = isDir(path);
		hasRt          = isDir(pathRt);
		hasSrc         = isDir(pathSrc);
		hasRes         = isDir(pathRes);
		hasMainD       = exists(pathMainD);
		hasMainVolt    = exists(pathMainVolt);
		hasBatteryCmd  = exists(pathBatteryTxt);
		hasTest        = isDir(pathTest);

		if (!hasSrc) {
			return;
		}

		filesC    = drv.deepScan(pathSrc, "c");
		filesVolt = drv.deepScan(pathSrc, "volt");
	}

	fn getInPath(file: string) string
	{
		return drv.removeWorkingDirectoryPrefix(
			path ~ dirSeparator ~ file);
	}

	fn buildExe() Exe
	{
		exe := new Exe();
		exe.name = name;
		exe.srcDir = pathSrc;
		exe.srcC = filesC;
		exe.srcVolt = [pathMainVolt];
		exe.bin = pathDerivedBin;

		return exe;
	}

	fn buildLib() Lib
	{
		lib := new Lib();
		lib.name = name;
		lib.srcDir = pathSrc;

		return lib;
	}
}

fn deepScan(drv: Driver, path: string, ending: string) string[]
{
	ret: string[];

	fn hit(p: string) {
		switch (p) {
		case ".", "..": return;
		default:
		}

		full := path ~ dirSeparator ~ p;

		if (isDir(full)) {
			ret ~= deepScan(drv, full, ending);
		} else if (endsWith(p, ending)) {
			ret ~= full;
		}
	}

	searchDir(path, "*", hit);

	return ret;
}

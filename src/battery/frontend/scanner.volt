// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds the code for searching a directory and automatically creating
 * a project from that.
 */
module battery.frontend.scanner;

import io = watt.io;
import watt.io.file : exists, searchDir, isDir;
import watt.path : baseName, dirName, dirSeparator, fullPath;
import watt.text.format : format;
import watt.text.string : endsWith, replace;
import watt.conv : toLower;

import battery.interfaces;
import battery.configuration;
import battery.util.file : getLinesFromFile;
import battery.frontend.parameters : ArgParser;


enum PathRt         = "rt";
enum PathSrc        = "src";
enum PathRes        = "res";
enum PathMainD      = "main.d";
enum PathMainVolt   = "main.volt";
enum PathBatteryTxt = "battery.txt";
enum PathTestJson   = "battery.tests.json";
enum PathTestSimple = "battery.tests.simple";

/**
 * Scan a directory and see what it holds.
 */
fn scanDir(drv: Driver, c: Configuration, path: string) Project
{
	s: Scanner;
	s.scan(drv, path);

	if (s.name == "volta") {
		return scanVolta(drv, c, ref s);
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
	ret: Project; exe: Exe; lib: Lib;
	if (s.hasMainVolt) {
		ret = exe = s.buildExe();
		drv.info("executable %s: '%s'", ret.name, s.inputPath);
	} else {
		ret = lib = s.buildLib();
		drv.info("library %s: '%s'", ret.name, s.inputPath);
	}

	foreach (p; s.pathJsonTests) {
		ret.testFiles ~= p;
	}

	if (s.hasRes) {
		ret.stringPaths ~= s.pathRes;
	}

	processBatteryCmd(drv, c, ret, ref s);

	foreach (p; s.pathSimpleTests) {
		drv.info("\ttest: '%s'", rootify(s.path, p));
	}

	foreach (p; s.pathJsonTests) {
		drv.info("\ttest: '%s'", rootify(s.path, p));
	}

	if (s.hasRes) {
		drv.info("\tres: '%s'", rootify(s.path, s.pathRes));
	}

	foreach (p; s.pathSubProjects) {
		ret.children ~= scanDir(drv, c, dirName(p));
		ret.children[$-1].name = format("%s.%s", s.name, ret.children[$-1].name);
	}

	return ret;
}

fn rootify(root: string, path: string) string
{
	if (path.length <= root.length) {
		return path;
	} else {
		return format("$%s%s", dirSeparator, path[root.length + 1 .. $]);
	}
}

fn scanVolta(drv: Driver, c: Configuration, ref s: Scanner) Project
{
	if (!s.hasRt) {
		drv.abort("volta needs a 'rt' folder");
	}

	if (!s.hasMainD) {
		drv.abort("volta needs 'src/main.d'");
	}

	drv.info("compiler volta: '%s'", s.inputPath);

	exe := new Exe();
	exe.name = s.name;
	exe.srcDir = s.pathSrc;
	exe.bin = s.pathDerivedBin;
	exe.isInternalD = true;
	exe.srcVolt ~= s.pathMainD;

	processBatteryCmd(drv, c, exe, ref s);

	// Scan the runtime.
	rt := cast(Lib)scanDir(drv, c, s.inputPath ~ dirSeparator ~ PathRt);
	if (rt is null) {
		drv.abort("Volta '%s' runtime must be a library", s.inputPath);
	}
	drv.add(rt);

	return exe;
}

fn processBatteryCmd(drv: Driver, c: Configuration, b: Project, ref s: Scanner)
{
	if (s.hasBatteryCmd) {
		args : string[];
		getLinesFromFile(s.pathBatteryTxt, ref args);
		ap := new ArgParser(drv);
		ap.parseProjects(c, args, s.path ~ dirSeparator, b);
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

	path: string;
	pathRt: string;
	pathSrc: string;
	pathRes: string;
	pathMainD: string;
	pathMainVolt: string;
	pathBatteryTxt: string;
	pathDerivedBin: string;
	pathSimpleTests: string[];
	pathJsonTests: string[];
	pathSubProjects: string[];

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

		name            = toLower(baseName(path));
		pathRt          = getInPath(PathRt);
		pathSrc         = getInPath(PathSrc);
		pathRes         = getInPath(PathRes);
		pathMainD       = pathSrc ~ dirSeparator ~ PathMainD;
		pathMainVolt    = pathSrc ~ dirSeparator ~ PathMainVolt;
		pathBatteryTxt  = getInPath(PathBatteryTxt);
		pathDerivedBin  = getInPath(name);
		pathSimpleTests = deepScan(path, PathTestSimple);
		pathJsonTests   = deepScan(path, PathTestJson);
		pathSubProjects = deepScan(path, PathBatteryTxt, pathBatteryTxt);

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

		filesC    = deepScan(pathSrc, ".c");
		filesVolt = deepScan(pathSrc, ".volt");
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

fn deepScan(path: string, ending: string, omissions: string[]...) string[]
{
	ret: string[];

	fn hit(p: string) {
		switch (p) {
		case ".", "..", ".git": return;
		default:
		}

		full := format("%s%s%s", path, dirSeparator, p);

		foreach (omission; omissions) {
			if (fullPath(omission) == fullPath(full)) {
				return;
			}
		}

		if (isDir(full)) {
			ret ~= deepScan(full, ending);
		} else if (endsWith(p, ending)) {
			ret ~= full;
		}
	}

	searchDir(path, "*", hit);

	return ret;
}

import watt.io.std;
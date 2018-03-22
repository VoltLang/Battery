// Copyright © 2016, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/**
 * Holds the code for searching a directory and automatically creating
 * a project from that.
 */
module battery.frontend.scanner;

import io = watt.io;
import watt.io.file : exists, searchDir, isDir, SearchStatus;
import watt.path : baseName, dirName, dirSeparator, fullPath;
import watt.text.format : format;
import watt.text.string : endsWith, replace;
import watt.conv : toLower;

import battery.interfaces;
import battery.configuration;
import battery.util.file : getLinesFromFile;
import battery.frontend.parameters : ArgParser;
import battery.frontend.conf : parseTomlConfig;


enum PathRt          = "rt";
enum PathSrc         = "src";
enum PathRes         = "res";
enum PathTest        = "test";
enum PathMainD       = "main.d";
enum PathMainVolt    = "main.volt";
enum PathBatteryTxt  = "battery.txt";
enum PathBatteryToml = "battery.toml";
enum PathTestJson    = "battery.tests.json";
enum PathTestSimple  = "battery.tests.simple";

/**
 * Scan a directory and see what it holds.
 */
fn scanDir(drv: Driver, c: Configuration, path: string) Project
{
	return scanDir(drv, c, path, null);
}

fn scanDir(drv: Driver, c: Configuration, path: string, parent: string) Project
{
	s: Scanner;
	s.scan(drv, path);

	// First sanity check.
	if (!s.hasPath) {
		drv.abort("path '%s' not found", s.inputPath);
	}

	if (!s.hasSrc) {
		drv.abort("path '%s' does not have a '%s' folder", s.inputPath, PathSrc);
	}

	// Because of DMD
	if (s.name == "volta" && !s.hasMainD) {
		drv.abort("volta needs 'src/main.d'");
	}

	// Create exectuable or library.
	ret: Project; exe: Exe; lib: Lib;
	if (s.hasMainD && s.hasMainVolt) {
		drv.abort("Project can not have both '%s' and '%s'",
			s.pathMainD, s.pathMainVolt);
	} else if (s.hasMainVolt || s.hasMainD) {
		ret = exe = s.buildExe();
	} else {
		ret = lib = s.buildLib();
	}

	if (parent.length != 0) {
		ret.name = format("%s.%s", parent, ret.name);
	}

	processBatteryCmd(drv, c, ret, ref s);

	if (!ret.scanForD && s.filesVolt.length == 0) {
		drv.abort("path '%s' has no volt files", s.pathSrc);
	}

	if (ret.scanForD && s.filesD.length == 0) {
		drv.abort("path '%s' has no D files", s.pathSrc);
	}

	if (lib !is null) {
		printInfo(drv, lib, ref s);
	}

	if (exe !is null) {
		printInfo(drv, exe, ref s);
	}

	foreach (sub; s.pathSubProjects) {
		ret.children ~= scanDir(drv, c, dirName(sub), ret.name);
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

fn printInfo(drv: Driver, lib: Lib, ref s: Scanner)
{
	drv.info("library %s: '%s'", lib.name, s.inputPath);

	printInfoCommon(drv, lib, ref s);
}

fn printInfo(drv: Driver, exe: Exe, ref s: Scanner)
{
	drv.info("executable %s: '%s'", exe.name, s.inputPath);

	printInfoCommon(drv, exe, ref s);
}

fn printInfoCommon(drv: Driver, p: Project, ref s: Scanner)
{
	foreach (path; s.pathSimpleTests) {
		drv.info("\ttest: '%s'", rootify(s.path, path));
	}

	foreach (path; s.pathJsonTests) {
		drv.info("\ttest: '%s'", rootify(s.path, path));
	}

	foreach (path; p.stringPaths) {
		drv.info("\tres: '%s'", rootify(s.path, path));
	}
}

fn processBatteryCmd(drv: Driver, c: Configuration, b: Project, ref s: Scanner)
{
	parseTomlConfig(s.pathBatteryToml, s.path ~ dirSeparator, drv, c, b);
}

struct Scanner
{
public:
	drv: Driver;
	inputPath: string;

	name: string;

	hasSrc: bool;
	hasRes: bool;
	hasPath: bool;
	hasTest: bool;
	hasMainD: bool;
	hasMainVolt: bool;
	hasBatteryToml: bool;

	path: string;
	pathRt: string;
	pathSrc: string;
	pathRes: string;
	pathTest: string;
	pathMainD: string;
	pathMainVolt: string;
	pathBatteryToml: string;
	pathDerivedBin: string;
	pathSimpleTests: string[];
	pathJsonTests: string[];
	pathSubProjects: string[];

	filesC: string[];
	filesD: string[];
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
		pathTest        = getInPath(PathTest);
		pathMainD       = pathSrc ~ dirSeparator ~ PathMainD;
		pathMainVolt    = pathSrc ~ dirSeparator ~ PathMainVolt;
		pathBatteryToml = getInPath(PathBatteryToml);
		pathDerivedBin  = getInPath(name);
		pathSubProjects = deepScan(path, PathBatteryToml, pathBatteryToml);

		hasPath        = isDir(path);
		hasSrc         = isDir(pathSrc);
		hasRes         = isDir(pathRes);
		hasTest        = isDir(pathTest);
		hasMainD       = exists(pathMainD);
		hasMainVolt    = exists(pathMainVolt);
		hasBatteryToml = exists(pathBatteryToml);

		if (hasTest) {
			pathSimpleTests = deepScan(pathTest, PathTestSimple);
			pathJsonTests   = deepScan(pathTest, PathTestJson);
		}

		if (hasSrc) {
			filesC    = deepScan(pathSrc, ".c");
			filesD    = deepScan(pathSrc, ".d");
			filesVolt = deepScan(pathSrc, ".volt");
		}
	}

	fn getInPath(file: string) string
	{
		return drv.removeWorkingDirectoryPrefix(
			path ~ dirSeparator ~ file);
	}

	fn buildExe() Exe
	{
		exe := new Exe();
		exe.bin = pathDerivedBin;

		if (hasMainD) {
			exe.srcVolt ~= pathMainD;
		}

		if (hasMainVolt) {
			exe.srcVolt ~= pathMainVolt;
		}

		buildCommon(exe);

		return exe;
	}

	fn buildLib() Lib
	{
		lib := new Lib();

		buildCommon(lib);

		return lib;
	}

	fn buildCommon(p: Project)
	{
		p.name = name;
		p.srcC = filesC;
		p.srcDir = pathSrc;
		p.batteryToml = pathBatteryToml;

		foreach (path; pathJsonTests) {
			p.testFiles ~= path;
		}

		if (hasRes) {
			p.stringPaths ~= pathRes;
		}
	}
}

fn deepScan(path: string, ending: string, omissions: string[]...) string[]
{
	ret: string[];

	fn hit(p: string) SearchStatus {
		switch (p) {
		case ".", "..", ".git": return SearchStatus.Continue;
		default:
		}

		full := format("%s%s%s", path, dirSeparator, p);

		foreach (omission; omissions) {
			if (fullPath(omission) == fullPath(full)) {
				return SearchStatus.Continue;
			}
		}

		if (isDir(full)) {
			ret ~= deepScan(full, ending);
		} else if (endsWith(p, ending)) {
			ret ~= full;
		}

		return SearchStatus.Continue;
	}

	searchDir(path, "*", hit);

	return ret;
}

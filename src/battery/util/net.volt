module battery.util.net;

import io   = watt.io;
import http = watt.http;
import conv = watt.conv;
import path = [watt.path, watt.text.path];
import text = watt.text.string;
import file = watt.io.file;

import interfaces = battery.interfaces;
import config     = battery.configuration;
import extract    = battery.util.extract;
import github     = battery.util.github;
import scanner    = battery.frontend.scanner;
import params     = battery.frontend.parameters;

enum ProgressBarLength = 30;
enum SrcDir     = ".battery${path.dirSeparator}src";
enum ToolDir    = ".battery${path.dirSeparator}tools";

enum NasmExe   = "nasm.exe";
enum ClangExe  = "clang.exe";
enum VoltaExe  = "volta.exe";

/*!
 * Download what was needed for --netboot parameter.
 */
fn boot(drv: interfaces.Driver, cfg: config.Configuration, arg: params.ArgParser)
{
	downloadDependency(drv, cfg, arg, "volta");
	toolPath := downloadTool("volta");
	if (toolPath !is null) {
		drv.addCmd(false, "volta", toolPath);
	}

	toolchainArchive := github.downloadLatestReleaseFile("VoltLang", "Toolchain", "win_x86-64.zip");
	toolchainDir     := path.dirName(toolchainArchive.path);
	if (!toolchainArchive.preExisting) {
		extract.archive(toolchainArchive.path, toolchainDir);
	}

	nasmPath := path.concatenatePath(toolchainDir, NasmExe);
	if (file.exists(nasmPath)) {
		drv.addCmd(false, "nasm", nasmPath);
	}

	clangPath := path.concatenatePath(toolchainDir, ClangExe);
	if (file.exists(clangPath)) {
		drv.addCmd(false, "clang", clangPath);
	}
}

fn downloadTool(name: string) string
{
	// @todo Merge what we can with the downloadDependency(string) code.
	name = conv.toLower(name);
	downloadDir := path.concatenatePath(ToolDir, name);
	path.mkdirP(downloadDir);
	exeName: string;
	archiveFilename: github.Path;
	archiveFilename.failure = true;
	io.writeln(new "Downloading tool executable ${name}");
	switch (name) {
	case "volta":
		archiveFilename = github.downloadLatestReleaseFile("VoltLang", "Volta", "win_x86-64.zip");
		exeName = VoltaExe;
		break;
	default:
		break;
	}
	if (archiveFilename.failure) {
		io.writeln(new "Couldn't download tool '${name}'"); io.output.flush();
		return null;
	}
	finalPath := path.concatenatePath(downloadDir, exeName);
	if (file.exists(finalPath) && archiveFilename.preExisting) {
		return finalPath;
	}
	extract.archive(archiveFilename.path, downloadDir);
	if (!file.exists(finalPath)) {
		io.writeln(new "Couldn't download tool '${name}'"); io.output.flush();
		return null;
	}
	return finalPath;
}

fn downloadDependency(drv: interfaces.Driver, cfg: config.Configuration, arg: params.ArgParser, name: string) interfaces.Project
{
	extractedPath := downloadDependency(name);
	if (extractedPath !is null) {
		p := scanner.scanDir(drv, cfg, extractedPath);
		arg.process(cfg, p);
		if (auto lib = cast(interfaces.Lib)p) {
			drv.add(lib);
		} else if (auto exe = cast(interfaces.Exe)p) {
			drv.add(exe);
		}
		return p;
	}
	return null;
}

/*!
 * Download and extract a dependency.
 *
 * @Returns The path to the extracted dependency
 * or `null` on failure.
 */
fn downloadDependency(name: string) string
{
	name = conv.toLower(name);
	downloadDir := path.concatenatePath(SrcDir, name);
	path.mkdirP(downloadDir);
	archiveFilename: github.Path;
	io.writeln(new "Downloading ${name}");
	switch (name) {
	case "watt":
		archiveFilename = github.downloadLatestSource("VoltLang", "Watt");
		break;
	case "volta":
		archiveFilename = github.downloadLatestSource("VoltLang", "Volta");
		break;
	default:
		break;
	}
	if (archiveFilename.failure) {
		return null;
	}

	extractedPath := extract.findRoot(downloadDir);
	if (extractedPath is null && archiveFilename.preExisting) {
		extractedPath = extract.archive(archiveFilename.path, downloadDir);
	}

	if (extractedPath !is null) {
		io.writeln(new "Extracted to '${extractedPath}'"); io.output.flush();
	} else {
		io.writeln(new "Failed to extract '${archiveFilename.path}'"); io.output.flush();
	}
	return extractedPath;
}

fn downloadSource(server: string, url: string, useHttps: bool) string
{
	return download(server, url, useHttps, SrcDir);
}

fn download(server: string, url: string, useHttps: bool, destinationDirectory: string) string
{
	components := text.split(url, '/');
	if (components.length == 0) {
		return null;
	}
	filename := path.concatenatePath(destinationDirectory, components[$-1]);
	h   := new http.Http();
	req := new http.Request(h);
	req.server = server;
	req.url = url;
	req.port = useHttps ? 443 : 80;
	req.secure = useHttps;

	fn progressBar() http.Status
	{
		if (req.contentLength() == 0) {
			io.write(new "${req.bytesDownloaded()} bytes\r");
			io.output.flush();
			return http.Status.Continue;
		}
		downloaded := cast(f64)req.bytesDownloaded();
		maximum    := cast(f64)req.contentLength();
		ratio      := (downloaded / maximum);
		pips       := cast(i32)(ProgressBarLength * ratio);
		spaces     := ProgressBarLength - pips;
		io.write("[");
		foreach (i; 0 .. pips) {
			io.write("#");
		}
		foreach (i; 0 .. spaces) {
			io.write(" ");
		}
		io.write(new "] ${cast(i32)(ratio * 100)}%\r");
		io.output.flush();
		return http.Status.Continue;
	}

	h.loop(progressBar);
	io.output.writeln("");
	if (req.errorGenerated()) {
		io.error.writeln(new "Download failed: ${req.errorString()}");
		return null;
	} else {
		file.write(req.getData(), filename);
		io.writeln(new "Downloaded ${filename}");
		return filename;
	}
}

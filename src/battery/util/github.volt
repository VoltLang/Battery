// Copyright © 2016-2017, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/battery/license.volt (BOOST ver. 1.0).
/*!
 * Holds code for interacting with github.
 */
module battery.util.github;

import battery.interfaces;

import watt.text.string;

import net = battery.util.net;


class Repo
{
	original: string;
	org: string;
	proj: string;
}

import io = watt.io;
import json = watt.json;
import http = watt.http;
import text = watt.text.string;
import path = [watt.path, watt.text.path];

fn parseUrl(drv: Driver, url: string) Repo
{
	// Strip any whitespace.
	// >github.com/Org/Proj<
	url = strip(url);
	original := url;

	// Remove the prefix.
	// >github.com/<Org/Proj
	if (!startsWith(url, Prefix)) {
		drv.abort("Doesn't start with prefix '%s'", original);
		return null;
	}
	url = url[Prefix.length .. $];


	// Find the first slash.
	// githun.com/Org>/<Proj
	slashIndex := indexOf(url, '/');

	// Org name needs to be at least one character.
	if (slashIndex < 1) {
		drv.abort("no slash found '%s'", original);
		return null;
	}

	// We have the organization.
	// github.com/>Org</Proj
	org := url[0 .. slashIndex];

	// Need to be at least one character in project name.
	// (one for / and one for the character).
	// github.com/Org/>Proj<
	if (cast(size_t)slashIndex + 2 >= url.length) {
		drv.abort("not enough characters for project name '%s'", original);
		return null;
	}
	proj := url[slashIndex + 1 .. $];

	repo := new Repo();
	repo.original = original;
	repo.org = org;
	repo.proj = proj;

	return repo;
}

/*!
 * Download a file from a GitHub project's latest release.
 *
 * If the latest release from `owner/repo` contains a release asset with a 
 * name of `filename`, download it and return the path to the downloaded
 * file. Otherwise, return `null`.
 */
fn downloadLatestReleaseFile(owner: string, repo: string, filename: string) string
{
	latestReleaseJson   := apiGetLatestReleaseJson(owner, repo);
	if (latestReleaseJson is null) {
		return null;
	}
	jsonRoot      := json.parse(latestReleaseJson);
	latestRelease := filterReleaseAssets(jsonRoot, filename);
	if (latestRelease is null) {
		return null;
	}
	return downloadRelease(latestRelease.url, owner, repo);
}

//! Get the latest release JSON for a given project, or `null` on failure.
fn apiGetLatestReleaseJson(owner: string, repo: string) string
{
	h := new http.Http();
	r := new http.Request(h);
	r.server = "api.github.com";
	r.url    = new "/repos/${owner}/${repo}/releases/latest";
	r.port   = 443;
	r.secure = true;
	h.loop();
	if (r.errorGenerated()) {
		return null;
	}
	return r.getString();
}

class Release
{
public:
	this(url: string, tag: string)
	{
		this.url = url;
		this.tag = tag;
	}

public:
	url: string;
	tag: string;
}

//! If the release JSON `root` has an asset `targetName`, return its URL, or `null` otherwise.
fn filterReleaseAssets(root: json.Value, targetName: string) Release
{
	// Get the version tag.
	/+
	if (!root.hasObjectKey("tag_name")) {
		return null;
	}
	tagNameVal := root.lookupObjectKey("tag_name");
	if (tagNameVal.type() != json.DomType.STRING) {
		return null;
	}
	tagStr := tagNameVal.str();+/

	// Get the assets.
	if (!root.hasObjectKey("assets")) {
		return null;
	}
	assetsArrayVal := root.lookupObjectKey("assets");
	if (assetsArrayVal.type() != json.DomType.ARRAY) {
		return null;
	}

	// Go through the assets and look for our target.
	assetsArray := assetsArrayVal.array();
	foreach (assetRoot; assetsArray) {
		if (!assetRoot.hasObjectKey("name")) {
			continue;
		}
		name := assetRoot.lookupObjectKey("name");
		if (name.type() != json.DomType.STRING || name.str() != targetName) {
			continue;
		}
		if (!assetRoot.hasObjectKey("browser_download_url")) {
			return null;
		}
		url := assetRoot.lookupObjectKey("browser_download_url");
		if (url.type() != json.DomType.STRING) {
			return null;
		}
		return new Release(url.str(), "");
	}
	return null;
}

//! Download the file at `url` to the tools dir, and return the path, or `null` otherwise.
fn downloadRelease(url: string, owner: string, repo: string) string
{
	if (url is null) {
		return null;
	}
	destination := path.concatenatePath(net.ToolDir, new "github/${owner}/${repo}");
	path.mkdirP(destination);
	prefix := "https://github.com";
	if (!text.startsWith(url, prefix)) {
		return null;
	}
	theUrl := url[prefix.length .. $];
	return net.download(server:`github.com`, url:cast(string)theUrl, useHttps:true, destinationDirectory:destination);
}

private:

enum Prefix = "github.com/";

// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Holds to interact with github, like parsing a url.
 */
module battery.frontend.github;

import watt.text.string;
import battery.commonInterfaces;


class Repo
{
	original: string;
	org: string;
	proj: string;
}

import io = watt.io;

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


private:

enum Prefix = "github.com/";

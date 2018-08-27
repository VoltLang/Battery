// Copyright 2016-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Code that does the inital discovering of projects and configurations.
 */
module battery.frontend.discoverer;

import battery.interfaces;
import battery.frontend.interfaces;


/*!
 *
 */
class Result
{
	boot: Configuration;
	target: Configuration;

	projectByName: Project[string];
}

fn discover(drv: Driver, args: string[]) Result
{
	res := new Result();

	return res;
}

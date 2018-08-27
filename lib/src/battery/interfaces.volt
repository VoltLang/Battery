// Copyright 2015-2018, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
module battery.interfaces;

static import watt.text.sink;


/*!
 * Interface to the main class that controles the entire process.
 */
abstract class Driver
{
public:
	/*!
	 * Helper alias
	 */
	alias Fmt = watt.text.sink.SinkArg;


public:
	/*!
	 * Normalise a path, target must exsist.
	 */
	abstract fn normalisePath(path: string) string;

	/*!
	 * As the function name imples.
	 */
	abstract fn removeWorkingDirectoryPrefix(path: string) string;

	/*!
	 * Prints a action string.
	 *
	 * By default it is formated like this:
	 *
	 * ```
	 *   BATTERY  <fmt>
	 * ```
	 * @param fmt The format string, same formatting as @ref watt.text.format.
	 */
	abstract fn action(fmt: Fmt, ...);

	/*!
	 * Prints a info string.
	 *
	 * @param fmt The format string, same formatting as @ref watt.text.format.
	 */
	abstract fn info(fmt: Fmt, ...);

	/*!
	 * Error encoutered, print error then abort operation.
	 *
	 * May terminate program with exit, or throw an exception to resume.
	 *
	 * @param fmt The format string, same formatting as @ref watt.text.format.
	 */
	abstract fn abort(fmt: Fmt, ...);
}

// Copyright 2019, Jakob Bornecrantz.
// SPDX-License-Identifier: BSL-1.0
/*!
 * Somewhat simple logging core.
 */
module battery.util.log;

import watt = [watt.text.sink, watt.io.streams];


alias Sink = dg(watt.SinkArg);

/*!
 * Super simple logger.
 *
 * ### Usage:
 *
 * ```volt
 * import battery.util.log : Logger;
 *
 * private global log: Logger = {"my.prefix"};
 * ``` 
 */
struct Logger
{
private:
	prefix: string;


public:
	fn info(str: watt.SinkArg)
	{
		if (gStream is null) {
			return;
		}

		gStream.write(prefix);
		gStream.write(": ");
		gStream.write(str);
		gStream.write("\n");
		gStream.flush();
	}
}

/*!
 * Opens a new OutputFileStream for logging and sets it as the active logging
 * file.
 */
fn newLog(filename: string)
{
	gStream = new watt.OutputFileStream(filename);
}

/*!
 * Set the active logging file.
 */
fn setLog(stream: watt.OutputStream)
{
	gStream = stream;
}

private:

global gStream: watt.OutputStream;

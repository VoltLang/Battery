// Copyright © 2012-2013, Jakob Bornecrantz.  All rights reserved.
// See copyright notice in src/volt/license.d (BOOST ver. 1.0).
module battery.testing.cmd;

import core.stdc.stdio : FILE;
import core.exception;

version(Windows) {
	import core.windows.windows;
}

import watt.conv;
import watt.process;


/**
 * Helper class to launch one or more processes
 * to run along side the main process.
 */
class CmdGroup
{
public:
	alias DoneDg = void delegate(int);  // Is called with the retval of the completed command.
	printProgress: bool;
	printInteger: i32;

private:
	cmdStore: Cmd[];

	/// For Windows waitOne, to avoid unneeded allocations.
	version (Windows) __handles: Pid.NativeID[];

	/// Number of simultanious jobs.
	maxWaiting: uint;

	/// Number of running jobs at this moment.
	waiting: uint;

	/**
	 * Small container representing a executed command, is recycled.
	 */
	class Cmd
	{
	public:
		/// Executable.
		cmd: string;

		/// Arguments to be passed.
		args: string[];

		/// Called when command has completed.
		done: DoneDg;

		/// System specific process handle.
		handle: Pid.NativeID;

		/// In use.
		used: bool;


	public:
		/**
		 * Initialize all the fields.
		 */
		fn set(cmd: string, args: string[], dgt: DoneDg,
		       handle: Pid.NativeID)
		{
			used = true;
			this.cmd = cmd;
			this.args = args;
			this.done = dgt;
			this.handle = handle;
		}

		/**
		 * Reset to a unused state.
		 */
		fn reset()
		{
			used = false;
			cmd = null;
			args = null;
			done = null;
			version (Windows) {
				handle = null;
			} else {
				handle = 0;
			}
		}
	}

public:
	this(maxWaiting: uint, printProgress: bool)
	{
		waiting = 0;
		this.maxWaiting = maxWaiting;
		this.printProgress = printProgress;
		cmdStore = new Cmd[](maxWaiting);
		version (Windows) __handles = new Pid.NativeID[](maxWaiting);

		foreach (ref cmd; cmdStore) {
			cmd = new Cmd();
		}
	}

	fn run(cmd: string, args: string[], dgt: DoneDg, log: FILE*)
	{
		count: int;
		while (waiting >= maxWaiting) {
			waitOne();
		}

		pid := spawnProcess(cmd, args, null, log, log);
		newCmd(cmd, args, dgt, pid.nativeID);
		waiting++;
	}

	fn waitOne()
	{
		if (waiting == 0) {
			return;
		}

		version(Windows) {

			hCount: uint;
			foreach (cmd; cmdStore) {
				if (cmd.used) {
					__handles[hCount++] = cmd.handle;
				}
			}

			ptr := __handles.ptr;
			uRet := WaitForMultipleObjects(hCount, ptr, FALSE, cast(uint)-1);
			if (uRet == cast(DWORD)-1 || uRet >= hCount) {
				throw new Exception("Wait failed with error code " ~ .toString(cast(int)GetLastError()));
			}

			hProcess := __handles[uRet];

			// Retrieve the command for the returned wait, and remove it from the lists.
			c: Cmd;
			foreach (cmd; cmdStore) {
				if (hProcess !is cmd.handle) {
					continue;
				}
				c = cmd;
				break;
			}

			result := -1;
			bRet := GetExitCodeProcess(hProcess, cast(uint*)&result);
			cRet := CloseHandle(hProcess);
			if (bRet == 0) {
				c.reset();
				throw new CmdException(c.cmd, c.args,
					"abnormal application termination");
			}
			if (cRet == 0) {
				throw new Exception("CloseHandle failed with error code " ~ .toString(cast(int)GetLastError()));
			}

		} else version(Posix) {

			result: int;
			pid: pid_t;

			c: Cmd;
			// Because stopped processes doesn't count.
			while(true) {
				result = waitManyPosix(out pid);

				foundPid: bool;
				foreach (cmd; cmdStore) {
					if (cmd.handle != pid) {
						continue;
					}

					c = cmd;
					foundPid = true;
					break;
				}

				if (foundPid) {
					break;
				}

				if (pid > 0) {
					throw new Exception("PID waited on but not cleared!\n");
				}
				continue;
			}

		} else {
			static assert(false);
		}

		// Grab the delegate before resetting the command.
		dgt := c.done;

		// Do the resetting and accounting here.
		c.reset();
		waiting--;

		// Call the dgt if it is valid.
		if ((dgt !is null)) {
			dgt(result);
		}
	}

	fn waitAll()
	{
		while (waiting > 0) {
			waitOne();
		}
	}

private:
	fn newCmd(cmd: string, args: string[], dgt: DoneDg, handle: Pid.NativeID) Cmd
	{
		foreach (c; cmdStore) {
			if (c is null) {
				throw new Exception("null cmdStore.");
			}
			if (!c.used) {
				c.set(cmd, args, dgt, handle);
				return c;
			}
		}
		throw new Exception("newCmd failure");
	}
}

/**
 * Exception form and when execquting commands.
 */
class CmdException : Exception
{
	this(cmd: string, reason: string)
	{
		super("The below command failed due to: " ~ reason ~ "\n" ~ cmd);
	}

	this(cmd: string, args: string[], reason: string)
	{
		foreach (a; args) {
			cmd ~= " " ~ a;
		}
		this(cmd, reason);
	}

	this(cmd: string, result: int)
	{
		super("The below command returned: " ~ .toString(result) ~ " \n" ~ cmd);
	}

	this(cmd: string, args: string[], result: int)
	{
		foreach (a; args) {
			cmd ~= " " ~ a;
		}
		this(cmd, result);
	}
}

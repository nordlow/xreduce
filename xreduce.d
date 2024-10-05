#!/usr/bin/rdmd

alias Line = string;

enum Op {
	rdc, ///< Reduce.
	all, ///< All.
}

enum TaskType {
	rdc, ///< Reduce.
}

/++ CLI command including leading process name/path. +/
alias Cmd = const(string)[];

/++ CLI arguments exludding leading process name/path. +/
alias CmdArgs = const(string)[];

/++ CLI switches. +/
alias CmdSwitches = const(string)[];

/++ Process Environment.. +/
alias Environment = string[string];

static immutable dExt = `.d`;
static immutable dbgFlag = false; // Flags for debug logging via `dbg`.

import std.process : ProcessPipes, Redirect, pipeProcess, wait;
import std.algorithm : count, filter, endsWith, startsWith, skipOver, canFind, findSplitAfter, skipOver, findSplit, either;
import std.array : array, join, replace;
import std.path : expandTilde, baseName, stripExtension, buildPath;
import std.file : exists, getcwd, dirEntries, SpanMode, getSize, remove, readText, tempDir, mkdirRecurse;
import std.stdio : stdout, stderr, File, writeln;
import std.exception : enforce;
import std.uuid : randomUUID;

struct Task {
	this(TaskType tt, FileName exe, Cmd cmd, CmdSwitches switches, DirPath cwd, Redirect redirect) {
		CmdArgs cmdArgs = cmd[1 .. $];
		const ddmPath = findExecutable(FileName("ddemangled"));

		this.tt = tt;
		this.exe = exe;
		final switch (tt) {
		case TaskType.rdc:
			this.use = true;
			break;
		}

		this.cwd = cwd;
		auto ppArgs = (ddmPath ? [ddmPath.str] : []) ~ [exe.str] ~ this.cmdArgs;
		debug writeln("args:", ppArgs.join(' '));
		this.redirect = redirect;

		Environment env;
		this.pp = pipeProcess(ppArgs, redirect, env);
	}
	TaskType tt;
	FileName exe;
	CmdArgs cmdArgs;
	bool use;
	DirPath cwd;
	ProcessPipes pp;
	char[] outLines;
	char[] errLines;
	Redirect redirect;
}

int main(scope Cmd cmd_) {
	// analyze CLI arguments
	CmdSwitches switches;
	string matchingOutput;
	Cmd cmd = ["dustmite"]; // filtered command
	foreach (string arg; cmd_[1 .. $]) {
		if (arg.skipOver("--output=")) {
			matchingOutput = arg;
		} else {
			cmd ~= arg;
		}
	}

	const op = Op.rdc;
	const cwd = DirPath(getcwd);
	const exeRdc = FileName(findExecutable(FileName(`dustmite`)) ? `dustmite` : []);
	const onRdc = (op == Op.rdc || op == Op.all);
	const numOn = onRdc;
	const onRdr = numOn >= 2;
	const redirect = onRdr ? Redirect.all : Redirect.init;

	if (dbgFlag && onRdc) dbg("xreduce: Checking on: using ", exeRdc);
	if (dbgFlag && onRdr) dbg("xreduce: Redirecting on");

	auto rdc = onRdc ? Task(TaskType.rdc, exeRdc, cmd, switches, cwd, redirect) : Task.init;

	const bool rdcExitEarlyUponFailure = false; // TODO: Doesn't seem to be needed at the moment.
	int rdcES;
	if (rdc.use) {
		rdcES = rdc.pp.pid.wait();
		if (dbgFlag) dbg("xreduce: Reduce exit status: ", rdcES);
		if (redirect != Redirect.init) {
			if (dbgFlag) dbg("xreduce: Check is redirected");
			rdc.outLines = rdc.pp.stdout.byLine.join('\n');
			rdc.errLines = rdc.pp.stderr.byLine.join('\n');
			if (rdc.outLines.length)
				stdout.writeln(rdc.outLines);
			if (rdc.errLines.length)
				stderr.writeln(rdc.errLines);
		}
		if (rdcExitEarlyUponFailure && rdcES) {
			if (dbgFlag) dbg("xreduce: Exiting eagerly because check failed, potentially aborting other phases");
			return rdcES; // early failure return
		}
	}

	if (rdcES != 0)
		return rdcES;

	return 0;
}

void dbg(Args...)(scope auto ref Args args, in string file = __FILE_FULL_PATH__, const uint line = __LINE__) {
	stderr.writeln(file, "(", line, "):", " Debug: ", args, "");
}

void warn(Args...)(scope auto ref Args args, in string file = __FILE_FULL_PATH__, const uint line = __LINE__) {
	stderr.writeln(file, "(", line, "):", " Warning: ", args, "");
}

private string mkdirRandom() {
    const dirName = buildPath(tempDir(), "xreduce-" ~ randomUUID().toString());
    dirName.mkdirRecurse();
    return dirName;
}

/++ Path.

	The concept of a "pure path" doesn't need to be modelled in D as
	it has `pure` functions.  See
	https://docs.python.org/3/library/pathlib.html#pure-paths.

	See: SUMO:`ComputerPath`.
 +/
struct Path {
	this(string str) pure nothrow @nogc {
		this.str = str;
	}
	string str;
pure nothrow @nogc:
	bool opCast(T : bool)() const scope => str !is null;
	string toString() const @property => str;
}

/++ File (local) name.
 +/
struct FileName {
	this(string str, in bool normalize = false) pure nothrow @nogc {
		this.str = str;
	}
	string str;
	bool opCast(T : bool)() const scope pure nothrow @nogc => str !is null;
	string toString() inout return scope @property pure nothrow @nogc => str;
}

/++ (Regular) File path.
	See: https://hackage.haskell.org/package/filepath-1.5.0.0/docs/System-FilePath.html#t:FilePath
 +/
struct FilePath {
	this(string str) pure nothrow @nogc {
		this.path = Path(str);
	}
	Path path;
	alias path this;
}

struct DirPath {
	this(string str) pure nothrow @nogc {
		this.path = Path(str);
	}
	Path path;
	alias path this;
}

/++ Find path for `a` (or `FilePath.init` if not found) in `pathVariableName`.
	TODO: Add caching of result and detect changes via inotify.
 +/
private FilePath findExecutable(FileName a, scope const(char)[] pathVariableName = "PATH") {
	return findFileInPath(a, "PATH");
}

/++ Find path for `a` (or `FilePath.init` if not found) in `pathVariableName`.
	TODO: Add caching of result and detect changes via inotify.
 +/
FilePath findFileInPath(FileName a, scope const(char)[] pathVariableName) {
	import std.algorithm : splitter;
	import std.process : environment;
	const envPATH = environment.get(pathVariableName, "");
	foreach (const p; envPATH.splitter(':')) {
		import std.path : buildPath;
		const path = p.buildPath(a.str);
		if (path.exists)
			return FilePath(path); // pick first match
	}
	return typeof(return).init;
}

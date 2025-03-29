module app;

import std.path : expandTilde;
import std.file : exists, mkdir;
import std.stdio : writeln;
import assol;

// log header
enum lh = "#jobby: ";
auto jobbyLog(Args...)(Args args) => logPrint!(" ", "\n", lh)(args);
auto jobbyLogf(Args...)(in string format, Args args) => logPrintf!(lh)(format, args);

void main(string[] args)
{
    if (args.length < 2)
    {
        jobbyLog("No commands specified! See 'help' for more information.");
        return;
    }

    // configure config dir
    string configDir = "~/.jobby".expandTilde;
    string configFile = "~/.jobby/jobs.cfg".expandTilde;
    if (!configDir.exists) configDir.mkdir;
    if (!configFile.exists) configFile.mkdir;

    // parse command line arguments
    string command = args[1];
    string jobFile = args.length > 2 ? args[2] : configFile;
    writeln(command, " ", jobFile);
}

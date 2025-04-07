module app;

import std.conv : to;
import std.path : expandTilde, baseName;
import std.file : exists,
                  mkdir,
                  fileWrite = write,
                  readText;
import std.array : split, array, join;
import std.stdio : write, writef;
import std.string : splitLines, isNumeric, strip;
import std.format : format;
import std.algorithm : canFind, startsWith, any, filter;
import assol;

// log header
enum lh = "#jobby: ";
auto log(Args...)(Args args) => logPrint!(" ", "\n", lh)(args);
auto logf(Args...)(in string format, Args args) => logPrintf!(lh)(format, args);

// usage manual
enum version_ = "1.0.0";
enum usage = q{jobby v%s -- A simple task scheduler and executor supporting multiple job files.
USAGE: jobby [command] <jobs.cfg>
COMMANDS:
    serve  launch in background with custom jobs.cfg
     stop  stop daemon identified with custom jobs.cfg or PID
     list  list running jobs
 validate  validate jobs.cfg format
 help-fmt  job configuration file format documentation and examples.
     help  This help message.
NOTE:
    By default `~/.jobby/jobs.cfg` is used, unless a custom one is specified.
}.format(version_);
enum jobComponents = 8;
enum commandDelimiter = "|";
enum jobsFmt = q{jobby v%s -- A simple task scheduler and executor supporting multiple job files.
ANNOTATIONS:
    r - repeat
    y - year
    o - month
    w - week
    d - day
    h - hour
    m - minute
    s - second
    cmd - command
REPEATITION:
    r - stands for repetition. Substiture the value to execute task every y, o, d, h, m, s.
EXAMPLE:
    There are %s components in total in the configuration file. It follows the following format:
    ```jobs.cfg
  # r y o d h m s | cmd - this is a comment
    * * * * * * * | echo "Execute once when `jobby` is launched."
    * * * * 8 7 5 | echo "Execute once at 08:07:05. Ignore the next day, unless `jobby` is restarted."
    s * * * * * * | echo "Execute every second."
    m * * * * * * | echo "Execute every minute."
    m * * * * * 5 | echo "Execute every 5th second of a minute."
    h * * * * * * | echo "Execute every hour."
    h * * * * 5 * | echo "Execute every hour at 5th minute."
    h * * * * 5 7 | echo "Execute every hour at 5th minute and 7th second of that hour."
    d * * * * * * | echo "Execute every day at 00:00:00."
    d * * * 8 * * | echo "Execute every day at 08:00:00."
    d * * * 8 5 * | echo "Execute every day at 08:05:00."
    w * * * * * * | echo "Execute every monday at 00:00:00."
    w * * 1 * * * | echo "Execute every monday at 00:00:00. Weekdays numeration starts with Monday (1) - Sunday (7)."
    o * * * * * * | echo "Execute at the begining of every month at 00:00:00."
    o * * 9 8 * * | echo "Execute every 9th of month at 08:00:00."
    y * * * * * * | echo "Execute on 1st of January every year at 00:00:00."
    y * 2 9 8 7 5 | echo "Execute on 9th of February every year at 08:07:05. Months numeration starts with January (1) - December (12)."
    * 2027 2 9 8 7 5 | echo "Execute once on 2027-02-09 at 08:07:05."
    ```
    When repetition is set to weekdays `r=w`, the day field `d` is treated as weekday (Monday to Sunday 1-7).
    Otherwise the day field is treated as month day.
}.format(version_, jobComponents);

// jobby initialization
string configDir, defaultJobFile, lockFile;
static this()
{
    // configure config dir
    configDir = "~/.jobby".expandTilde;
    defaultJobFile = "~/.jobby/jobs.cfg".expandTilde;
    lockFile = "~/.jobby/jobs.lock".expandTilde;

    // create neccessary files and directories
    if (!configDir.exists) configDir.mkdir;
    if (!defaultJobFile.exists) fileWrite(defaultJobFile, "");
    if (!lockFile.exists) fileWrite(lockFile, "");
}

void main(string[] args)
{
    if (args.length < 2)
    {
        log("No commands specified! See 'help' for more information.");
        return;
    }

    // parse command line arguments
    string command = args[1];
    string argFileOrPid = args.length > 2 ? args[2].expandTilde : defaultJobFile;
    if (!argFileOrPid.isNumeric && !argFileOrPid.exists)
    {
        logf("File does not exist: <%s>!\n", argFileOrPid);
        return;
    }

    // execute command
    switch (command)
    {
        case "serve":
            serve(argFileOrPid);
            break;
        case "stop":
            stop(argFileOrPid);
            break;
        case "list":
            list(lockFile);
            break;
        case "validate":
            validate(argFileOrPid);
            break;
        case "help":
            write(usage);
            break;
        case "help-fmt":
            write(jobsFmt);
            break;
        default: log("Unknown command specified! See 'help' for more information.");
    }
}

struct Task
{
    char repeat = '*';
    int year, month, day, hour, minute, second;
    string cmd;

    static Task[] parseFile(in string jobFile)
    {
        // read file and split tasks to lines
        auto lines = jobFile
            .readText
            .splitLines
            .filter!(x => x[0] != '#')
            .array;

        // no tasks found
        if (!lines.length) return [];

        // parse jobs
        Task[] tasks;
        foreach (line; lines)
        {
            auto args = line.strip.split("|");
            auto schedule = args[0].strip.split(" ");
            auto commands = args[1].strip;
            tasks ~= Task(
                repeat: schedule[0][0],
                year:   schedule[1] == "*" ? -1 : schedule[1].to!uint,
                month:  schedule[2] == "*" ? -1 : schedule[2].to!uint,
                day:    schedule[3] == "*" ? -1 : schedule[3].to!uint,
                hour:   schedule[4] == "*" ? -1 : schedule[4].to!uint,
                minute: schedule[5] == "*" ? -1 : schedule[5].to!uint,
                second: schedule[6] == "*" ? -1 : schedule[6].to!uint,
                cmd:    commands,
            );
        }

        return tasks;
    }
}

void serve(in string jobFile)
{
    auto tasks = Task.parseFile(jobFile);
    write(tasks, "\n");
}

void stop(in string jobFileOrPid) {}

void list(in string lockFile) {
    // split tasks to lines
    auto lines = lockFile
        .readText
        .splitLines;

    // no jobs are running
    if (!lines.length)
    {
        log("No jobs are running!");
        return;
    }

    // output running job files
    writef("%5s\t%s\n", "PID", "Jobs file");
    foreach (i; lines)
    {
        auto s = i.strip.split(" ");
        writef("%5s\t%s\n", s[0], s[1]);
    }
}

void validate(in string jobFile)
{
    // split tasks to lines
    auto tasks = jobFile
        .readText
        .splitLines;

    void logError(in string jobFile, in string task, in size_t line, in string msg = "")
    {
        log(msg);
        logPrintf("%s:%s: \n    --> %s\n", jobFile.baseName, line, task);
    }

    // verify format
    bool statusOk = true;
    foreach (i, task; tasks)
    {
        // skip comments
        if (task.startsWith("#")) continue;

        // check items
        if (!task.canFind(commandDelimiter))
        {
            logError(jobFile, task, i+1, "Command delimiter `%s` not found.".format(commandDelimiter));
            statusOk = false;
            continue;
        }

        // check for valid number of components
        auto args = task.split(commandDelimiter)[0].strip.split(" ");
        if (args.length < jobComponents - 1)
        {
            logError(jobFile, task, i+1,
                "Schedule specified is invalid. There must be %s components before delimeter `%s`, but %s found: r y o d h m s | cmd".format(
                    jobComponents - 1, commandDelimiter, args.length
                ));
            statusOk = false;
            continue;
        }
        else if (args[0] != "*" && args[0].isNumeric)
        {
            logError(jobFile, task, i,
                "First schedule component denotes repetition: y, o, d, w, h, m, s. It cannot be numeric.");
            statusOk = false;
            continue;
        }
        else if (args[1 .. $].any!(a => a != "*" && !a.isNumeric))
        {
            logError(jobFile, task, i+1,
                "Time components of schedule starting with `y` up to `cmd` must be numeric: r y o d h m s cmd");
            statusOk = false;
            continue;
        }
    }

    if (statusOk) log("All good.");
    else log("Maybe see 'help-fmt' for more information.");
}

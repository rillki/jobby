module app;

import core.time : dur;
import core.thread : Thread;

import std.conv : to;
import std.path : expandTilde, 
                  baseName, 
                  buildPath,
                  setExtension, 
                  absolutePath;
import std.file : exists,
                  mkdir,
                  getSize,
                  fileWrite = write,
                  readText,
                  thisExePath;
import std.ascii : newline, isAlpha;
import std.array : split, array, join, empty;
import std.stdio : write, writef, File;
import std.string : splitLines, isNumeric, strip;
import std.format : format, formattedRead;
import std.process : spawnShell, 
                     spawnProcess, 
                     tryWait, 
                     kill,
                     Pid;
import std.datetime : Clock, DayOfWeek, SysTime;
import std.algorithm : canFind, find, findSplit, startsWith, any, filter, map;
import std.parallelism : parallel;

import asol;

// log header
enum lh = "jobby :: ";
auto log(Args...)(Args args) => logPrint!(" ", "\n", lh)(args);
auto logf(Args...)(in string format, Args args) => logPrintf!(lh)(format, args);

// usage manual
enum version_ = "1.2.0";
enum usage = q{jobby v%s -- A simple task scheduler and executor supporting multiple job files.
USAGE: jobby [command] <jobs.cfg>
COMMANDS:
      run  run with custom job.cfg file.
    serve  launch in background with custom jobs.cfg file.
     stop  stop daemon identified with custom jobs.cfg or PID.
      log  display log output related to the specified job.cfg file.
     list  list all launched jobs.
    check  check all dead daemon jobs.
  restart  restart all previously running daemons that are not running.
 validate  validate jobs.cfg format.
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
    r - stands for repetition. Substitute the value to execute task every y, o, d, h, m, s.
EXAMPLE:
    There are %s components in total in the configuration file. It follows the following format:
    ```jobs.cfg
  # r y o d h m s | cmd - this is a comment
    * * * * * * * | echo "Execute once when `jobby` is launched."
    * * * * 8 7 5 | echo "Execute once at 08:07:05. Ignore the next day, unless `jobby` is restarted."
    s * * * * * * | echo "Execute every second."
    s * * * * * 5 | echo "Execute every 5 seconds."
    m * * * * * * | echo "Execute every minute."
    m * * * * 3 * | echo "Execute every 3 minutes."
    m * * * * * 5 | echo "Execute every 5th second of a minute."
    h * * * * * * | echo "Execute every hour."
    h * * * 6 * * | echo "Execute every 6 hours."
    h * * * * 5 * | echo "Execute every hour at 5th minute."
    h * * * * 5 7 | echo "Execute every hour at 5th minute and 7th second of that hour."
    d * * * * * * | echo "Execute every day at 00:00:00."
    d * * 4 * * * | echo "Execute every 4 days."
    d * * * 8 * * | echo "Execute every day at 08:00:00."
    d * * * 8 5 * | echo "Execute every day at 08:05:00."
    w * * * * * * | echo "Execute every monday at 00:00:00."
    w * * 2 * * * | echo "Execute every Tuesday at 00:00:00. Weekdays numeration starts with Monday (1) - Sunday (7)."
    o * * * * * * | echo "Execute at the begining of every month at 00:00:00."
    o * 3 * * * * | echo "Execute every 3 months."
    o * * 9 8 * * | echo "Execute every 9th day of month at 08:00:00."
    y * * * * * * | echo "Execute on 1st of January every year at 00:00:00."
    y 2 * * * * * | echo "Execute every 2 years on 1st of January at 00:00:00."
    y * 2 9 8 7 5 | echo "Execute on 9th of February every year at 08:07:05. Months numeration starts with January (1) - December (12)."
    * 2027 2 9 8 7 5 | echo "Execute once on 2027-02-09 at 08:07:05."
    ```
    When repetition is set to weekdays `r=w`, the day field `d` is treated as weekday (Monday to Sunday 1-7).
    Otherwise the day field is treated as month day.
}.format(version_, jobComponents); // @suppress(dscanner.style.long_line)

// jobby initialization
int logFileSize = 2;
string configDir, configFile, defaultJobFile, lockFile;
static this()
{
    // configure config dir
    configDir = "~/.jobby".expandTilde;
    configFile = configDir.buildPath("config.yaml");
    defaultJobFile = configDir.buildPath("jobs.cfg");
    lockFile = configDir.buildPath("jobs.lock");

    // create neccessary files and directories
    if (!configDir.exists) configDir.mkdir;
    if (!configFile.exists) 
    {
        fileWrite(configFile, "# k, m, g\nlog-file-size: 2m");
    }
    else // try to parse
    {
        try
        {
            // parse file
            immutable config = configFile
                .readText
                .splitLines
                .filter!(line => line[0] != '#' && !line.strip.empty)
                .array[0]
                .split(":");
            immutable unit = config[1][$-1];
            
            // validate
            if (!isAlpha(unit)) throw new Exception("Unit not specified (k, m, g).");

            // convert to bytes
            enum kb = 1024;
            immutable value = config[1][0 .. $-1].strip.to!int;
            if (unit == 'k') logFileSize = value * kb;
            else if (unit == 'm') logFileSize = value * kb * kb;
            else logFileSize = value * kb * kb * kb; // gb
        }
        catch (Exception e)
        {
            log("Config file uses YAML format! Fallback to default values.");
            log("Parsing error:", e.msg);
        }
    }
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
        case "run":
            run(argFileOrPid);
            break;
        case "serve":
            serve(argFileOrPid);
            break;
        case "stop":
            stop(argFileOrPid);
            break;
        case "log":
            displayLog(argFileOrPid);
            break;
        case "list":
            list(lockFile);
            break;
        case "check":
            check(lockFile); // @suppress(dscanner.unused_result)
            break;
        case "restart":
            restart(lockFile);
            break;
        case "validate":
            validate(argFileOrPid); // @suppress(dscanner.unused_result)
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
    // this field is required for tasks that should be executed only once every time `jobby` is launched
    bool ignore = false;

    char repeat;
    int year, month, day, hour, minute, second;
    string cmd;
    SysTime lastRun;

    static Task[] parseFile(in string jobFile)
    {
        // ensure job file format is correct
        if (!validate(jobFile, false)) return null;

        // read file and split tasks to lines
        auto lines = jobFile
            .readText
            .splitLines
            .map!(line => line.strip)
            .filter!(line => !line.empty && line[0] != '#')
            .array;

        // no tasks found
        if (!lines.length) return [];

        // parse tasks from jobFile
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

    bool shouldRun()
    {
        // get current time
        auto currTime = Clock.currTime();

        // check if non-repeating task has been executed already
        // (a task that runs only once every startup if time matches)
        if (ignore) return false;

        /*
            REPEATING TASKS
            (tasks that run repeatedly with 'r'-field set to specific value)
        */

        // prevent running tasks multiple times in the same time unit
        // (for the tasks that have already been executed at least once)
        if (lastRun != SysTime.init) switch (repeat)
        {
            case 's':
                if ((currTime - lastRun).total!"seconds" == 0) return false;
                break;
            case 'm':
                if ((currTime - lastRun).total!"minutes" == 0) return false;
                break;
            case 'h':
                if ((currTime - lastRun).total!"hours" == 0) return false;
                break;
            case 'd':
                if ((currTime - lastRun).total!"days" == 0) return false;
                break;
            case 'w':
                if (lastRun.dayOfWeek == currTime.dayOfWeek && 
                    (currTime - lastRun).total!"days" < 7) 
                    return false;
                break;
            case 'o':
                if (lastRun.year == currTime.year && 
                    lastRun.month == currTime.month) 
                    return false;
                break;
            case 'y':
                if (lastRun.year == currTime.year) 
                    return false;
                break;
            default: // one-time execution
                break;
        }

        // check if time matches the schedule
        // (task should run)
        bool timeMatches = false;
        switch (repeat)
        {
            case '*': // one-time execution - exact time match
                timeMatches = 
                    (year < 0 || currTime.year == year) &&
                    (month < 0 || cast(int)currTime.month == month) &&
                    (day < 0 || currTime.day == day) &&
                    (hour < 0 || currTime.hour == hour) &&
                    (minute < 0 || currTime.minute == minute) &&
                    (second < 0 || currTime.second == second);
                break;

            case 's': // every second (with optional repetition every N seconds)
                if (second > 0)
                {
                    // execute every N seconds: check if enough time has passed since last run
                    if (lastRun == SysTime.init)
                    {
                        // first run - execute immediately
                        timeMatches = true;
                    }
                    else
                    {
                        // check if N seconds have passed since last run
                        timeMatches = (currTime - lastRun).total!"seconds" >= second;
                    }
                }
                else
                {
                    // execute every second
                    timeMatches = true;
                }
                break;

            case 'm': // every minute
                if (minute > 0)
                {
                    // execute every N minutes at specified second (or any second if not specified)
                    if (lastRun == SysTime.init)
                    {
                        // first run - check if we're at the right second
                        timeMatches = (second < 0 || currTime.second == second);
                    }
                    else
                    {
                        // check if N minutes have passed and we're at the right second
                        timeMatches = (currTime - lastRun).total!"minutes" >= minute &&
                                    (second < 0 || currTime.second == second);
                    }
                }
                else
                {
                    // execute every minute at specified second (or at second 0 if not specified)
                    timeMatches = (second < 0 ? currTime.second == 0 : currTime.second == second);
                }
                break;

            case 'h': // every hour
                if (hour > 0)
                {
                    // execute every N hours at specified minute:second
                    if (lastRun == SysTime.init)
                    {
                        timeMatches = (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                    (second < 0 ? currTime.second == 0 : currTime.second == second);
                    }
                    else
                    {
                        timeMatches = (currTime - lastRun).total!"hours" >= hour &&
                                    (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                    (second < 0 ? currTime.second == 0 : currTime.second == second);
                    }
                }
                else
                {
                    // execute every hour at specified minute:second (or 00:00 if not specified)
                    timeMatches = (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                (second < 0 ? currTime.second == 0 : currTime.second == second);
                }
                break;

            case 'd': // every day
                if (day > 0)
                {
                    // execute every N days at specified time
                    if (lastRun == SysTime.init)
                    {
                        timeMatches = (hour < 0 ? currTime.hour == 0 : currTime.hour == hour) &&
                                    (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                    (second < 0 ? currTime.second == 0 : currTime.second == second);
                    }
                    else
                    {
                        timeMatches = (currTime - lastRun).total!"days" >= day &&
                                    (hour < 0 ? currTime.hour == 0 : currTime.hour == hour) &&
                                    (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                    (second < 0 ? currTime.second == 0 : currTime.second == second);
                    }
                }
                else
                {
                    // execute every day at specified time (or 00:00:00 if not specified)
                    timeMatches = (hour < 0 ? currTime.hour == 0 : currTime.hour == hour) &&
                                (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                (second < 0 ? currTime.second == 0 : currTime.second == second);
                }
                break;

            case 'w': // every week (weekday-based)
                {
                    // convert Sunday=0 to Sunday=7 for consistency with config
                    auto currentWeekday = currTime.dayOfWeek == DayOfWeek.sun ? 7 : cast(int)currTime.dayOfWeek;
                    auto targetWeekday = day < 0 ? 1 : day; // default to Monday if not specified
                    
                    // every week on specified weekday
                    timeMatches = (currentWeekday == targetWeekday) &&
                                  (hour < 0 ? currTime.hour == 0 : currTime.hour == hour) &&
                                  (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                  (second < 0 ? currTime.second == 0 : currTime.second == second);
                }
                break;

            case 'o': // every month
                if (month > 0 && lastRun != SysTime.init)
                {
                    // execute every N months on specified day at specified time
                    auto monthsPassed = (currTime.year - lastRun.year) * 12 + (cast(int)currTime.month - cast(int)lastRun.month);
                    timeMatches = monthsPassed >= month &&
                                (day < 0 ? currTime.day == 1 : currTime.day == day) &&
                                (hour < 0 ? currTime.hour == 0 : currTime.hour == hour) &&
                                (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                (second < 0 ? currTime.second == 0 : currTime.second == second);
                }
                else
                {
                    // execute every month on specified day at specified time (or 1st at 00:00:00)
                    timeMatches = (day < 0 ? currTime.day == 1 : currTime.day == day) &&
                                (hour < 0 ? currTime.hour == 0 : currTime.hour == hour) &&
                                (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                (second < 0 ? currTime.second == 0 : currTime.second == second);
                }
                break;
                
            case 'y': // every year
                if (year > 0 && lastRun != SysTime.init)
                {
                    // execute every N years on specified date/time
                    timeMatches = (currTime.year - lastRun.year) >= year &&
                                (month < 0 ? cast(int)currTime.month == 1 : cast(int)currTime.month == month) &&
                                (day < 0 ? currTime.day == 1 : currTime.day == day) &&
                                (hour < 0 ? currTime.hour == 0 : currTime.hour == hour) &&
                                (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                (second < 0 ? currTime.second == 0 : currTime.second == second);
                }
                else
                {
                    // execute every year on specified date/time (or Jan 1st 00:00:00)
                    timeMatches = (month < 0 ? cast(int)currTime.month == 1 : cast(int)currTime.month == month) &&
                                (day < 0 ? currTime.day == 1 : currTime.day == day) &&
                                (hour < 0 ? currTime.hour == 0 : currTime.hour == hour) &&
                                (minute < 0 ? currTime.minute == 0 : currTime.minute == minute) &&
                                (second < 0 ? currTime.second == 0 : currTime.second == second);
                }
                break;
                
            default:
                timeMatches = false;
                break;
        }

        // update last run
        if (timeMatches)
        {
            lastRun = currTime;
            if (repeat == '*') ignore = true;
        }
        
        return timeMatches;
    }
}

struct LockedJob
{
    string pid, jobFile;

    static LockedJob[] parseFile(in string lockFile)
    {
        // read file and split jobs to lines
        auto lines = lockFile
            .readText
            .splitLines
            .map!(line => line.strip)
            .filter!(line => !line.empty && line[0] != '#')
            .array;

        // no jobs found
        if (!lines.length) return [];

        // parse jobs from lockFile
        LockedJob[] jobs;
        foreach (line; lines)
        {
            LockedJob job;
            formattedRead(line, "%s %s", job.pid, job.jobFile);
            jobs ~= job;
        }

        return jobs;
    }

    static void writeFile(in LockedJob[] jobs, in string lockFile)
    {
        // join file contents into string
        auto contents = jobs
            .map!(job => job.pid ~ " " ~ job.jobFile)
            .join(newline);

        // write to file
        fileWrite(lockFile, contents);
    }

    static bool isLocked(in LockedJob[] jobs, in string pidOrJobFile)
    {
        return jobs.any!(job => job.pid == pidOrJobFile || job.jobFile == pidOrJobFile);
    }
}

void executeCommand(in string command)
{
    if (!command.strip.length) return;

    try
    {
        spawnShell(command);
    }
    catch (Exception e)
    {
        logf("Error spawning command '%s': %s\n", command, e.msg);
    }
}

void run(in string jobFile)
{
    // parse tasks
    auto tasks = Task.parseFile(jobFile);
    if (!tasks)
    {
        logf("The parsed file `%s` is invalid. Try 'validate' for more information.\n", jobFile);
        return;
    }

    // loop
    while (true)
    {
        foreach (ref task; tasks.parallel)
        {
            if (task.shouldRun) executeCommand(task.cmd);
        }
        Thread.sleep(dur!"seconds"(1));
    }
}

void displayLog(in string jobFile)
{
    // setup log file
    immutable logFilePath = configDir.buildPath(jobFile.baseName.setExtension(".log"));
    
    // check if log file exists
    if (!exists(logFilePath))
    {
        log("Log file not found:", logFilePath);
        log("Make sure the job has been served with 'jobby serve %s'", jobFile);
        return;
    }

    // open file
    auto file = File(logFilePath, "r");
    if (!file.size) 
    {
        log("Log file is empty:", logFilePath);
        return;
    }

    // display header
    logf("=== Log for job file: %s ===\n", jobFile.baseName);
    log("Log file:", logFilePath);
    log("Log size:", formatFileSize(file.size));
    log("--- Log Contents ---");
    
    // display file contents
    write("<<<\n");
    foreach (line; file.byLine)
    {
        writef("%s\n", line);
    }
    write(">>>\n");
    log("--- End of Log ---");
}

void serve(in string jobFile)
{
    // parse running jobs
    auto jobs = LockedJob.parseFile(lockFile);

    // check if the current job is already running
    if (LockedJob.isLocked(jobs, jobFile))
    {
        log("This job is already running! Doing nothing.");
        return;
    }

    // setup
    immutable executablePath = thisExePath();
    immutable args = [executablePath, "run", jobFile.absolutePath()];
    immutable logFilePath = configDir.buildPath(jobFile.baseName.setExtension(".log"));
    if (exists(logFilePath) && logFilePath.getSize() >= logFileSize) fileWrite(logFilePath, "");
    auto logFile = File(logFilePath, "a");

    // serve job file
    try 
    {
        // spawn process
        auto pid = spawnProcess(
            args, 
            stdout: logFile, 
            stderr: logFile,
        );

        // validate that the process started
        Thread.sleep(dur!"msecs"(300));
        auto ret = tryWait(pid);
        if (ret.terminated)
        {
            log("Process failed to start, exited with code:", ret.status);
            return;
        }

        // save to lock file
        auto pidString = pid.processID.to!string;
        jobs = LockedJob.parseFile(lockFile); // read the latest changes
        jobs ~= LockedJob(pidString, jobFile);
        LockedJob.writeFile(jobs, lockFile);

        // report to user
        logf("Started jobby daemon with PID %s for job file: %s\n", pidString, jobFile);
        logf("Daemon output will be logged to: %s\n", logFilePath);
        logf("Use 'jobby stop %s' to stop the daemon.\n", pidString);
    }
    catch (Exception e)
    {
        log("Error starting daemon:", e.msg);
    }
}

void stop(in string jobFileOrPid) 
{
    // parse running jobs
    auto jobs = LockedJob.parseFile(lockFile);

    // no jobs
    if (!jobs.length)
    {
        log("No jobs found!");
        return;
    }

    // find job we need to stop
    auto tmp = jobs.find!(job => job.pid == jobFileOrPid || job.jobFile == jobFileOrPid);
    if (tmp.empty())
    {
        log("Job not found:", jobFileOrPid);
        log("Maybe use 'jobby list' to see running jobs.");
        return;
    }
    auto jobToStop = tmp[0];

    // terminate process
    if (killProcess(jobToStop.pid.to!int))
    {
        logf("Stopped daemon with PID=%s: %s\n", jobToStop.pid, jobToStop.jobFile);
    }
    else 
    {
        logf("Failed to stop process with PID=%s: %s\n", jobToStop.pid, jobToStop.jobFile);
        log("Removed dead process from lock file.");
    }

    // remove from lock file
    auto remainingJobs = jobs.filter!(job => job.pid != jobToStop.pid).array;
    LockedJob.writeFile(remainingJobs, lockFile);
}

void list(in string lockFile) {
    // parse running jobs
    auto jobs = LockedJob.parseFile(lockFile);

    // no jobs
    if (!jobs.length)
    {
        log("No jobs found!");
        return;
    }

    // output running job files
    writef("%5s\t%s\n", "PID", "Jobs file");
    foreach (job; jobs)
    {
        writef("%5s\t%s\n", job.pid, job.jobFile);
    }
}

LockedJob[] check(in string lockFile)
{
    // parse running jobs
    auto jobs = LockedJob.parseFile(lockFile);

    // no jobs
    if (!jobs.length)
    {
        log("No jobs found! Nothing to check.");
        return [];
    }

    // filter out dead jobs
    LockedJob[] deadJobs = jobs.filter!(job => !processIsRunning(job.pid.to!int)).array;
    if (deadJobs.empty)
    {
        log("All good.");
        return [];
    }
    
    // output running job files
    writef("%5s\t%s\n", "PID", "Jobs file (dead daemon)");
    foreach (job; deadJobs)
    {
        writef("%5s\t%s\n", job.pid, job.jobFile);
    }

    return deadJobs;
}

void restart(in string lockFile)
{
    // find dead daemons
    auto deadJobs = check(lockFile);

    // restart jobs
    foreach (job; deadJobs)
    {
        log("Restarting daemon:", job.jobFile);
        stop(job.jobFile);
        serve(job.jobFile);
    }
}

bool validate(in string jobFile, in bool verbose = true)
{
    // split tasks to lines
    auto tasks = jobFile
        .readText
        .splitLines
        .map!(line => line.strip)
        .array;
    bool statusOk = true;

    void logError(in string jobFile, in string task, in size_t line, in string msg = "")
    {
        if (verbose)
        {
            log(msg);
            logPrintf("%s:%s: \n    --> %s\n\n", jobFile.baseName, line, task);
        }
    }

    // check if file is empty
    if (!tasks) 
    {
        log("No tasks found in the job file:", jobFile);
        statusOk = false;
    }

    // verify format
    if (statusOk) foreach (i, task; tasks)
    {
        immutable line = i + 1;

        // skip comments
        if (task.startsWith("#") || task.empty) continue;

        // check items
        if (!task.canFind(commandDelimiter))
        {
            logError(jobFile, task, line, "Command delimiter `%s` not found.".format(commandDelimiter));
            statusOk = false;
            continue;
        }

        // split into components
        auto components = task
            .findSplit(commandDelimiter)
            .array
            .map!(component => component.strip)
            .filter!(a => a.length && a != commandDelimiter)
            .array;
        
        // check number of components: datetime and command
        if (components.length != 2)
        {
            logError(jobFile, task, line, "Command was not specified!");
            statusOk = false;
            continue;
        }

        // check for valid number of components
        auto args = components[0].strip.split(" ");
        if (args.length < jobComponents - 1)
        {
            logError(jobFile, task, line,
                "Schedule specified is invalid. Found only %s components before the delimeter `%s`, but %s is required: r y o d h m s | cmd".format(
                    args.length, commandDelimiter, jobComponents - 1
                ));
            statusOk = false;
            continue;
        }
        else if (args[0] != "*" && args[0].isNumeric)
        {
            logError(jobFile, task, line,
                "First schedule component denotes repetition: y, o, d, w, h, m, s. It cannot be numeric.");
            statusOk = false;
            continue;
        }
        else if (args[1 .. $].any!(a => a != "*" && !a.isNumeric))
        {
            logError(jobFile, task, line,
                "Time components of schedule starting with `y` up to `cmd` must be numeric: r y o d h m s cmd");
            statusOk = false;
            continue;
        }
    }

    if (verbose)
    {
        if (statusOk) log("All good.");
        else log("Maybe see 'help-fmt' for more information.");
    }

    return statusOk;
}


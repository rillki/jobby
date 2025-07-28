# Jobby
A simple task scheduler and executor supporting multiple job files.

## Features
- Custom cron-like syntax with second-level resolution
- Multiple job files supported
- Simple YAML-based config
- Background daemon mode
- Auto-restart dead jobs
- Logging with rotation support
- Lightweight and portable

## Installation

### From Source
You’ll need the [D compiler](https://dlang.org/) (`dmd` or `ldc2`).

**NOTE:** Use `ldc2` if you are on mac.

```sh
$ git clone https://github.com/rillki/jobby.git
$ cd jobby && dub build --build=release
```

The binary will be located in the `./bin` folder.

## Usage
```sh
jobby v1.2.0 -- A simple task scheduler and executor supporting multiple job files.
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
```

### Define jobs
Create `~/.jobby/jobs.cfg` or provide a custom file with your job definitions:
```sh
# r y o d h m s | cmd - this is a comment
* * * * * * * | echo "Execute once when 'jobby' is launched."
s * * * * * * | echo "Execute every second."
s * * * * * 5 | echo "Execute every 5 seconds."
s * * * * * 29 | echo "Execute every 29 seconds."
m * * * * 3 0 | echo "Execute every 3 minutes."
m * * * * * * | echo "Execute every minute."
```
Run `jobby help-fmt` to view additional examples and syntax details. 

### Log file size
Specify the maximum log file size in `~/.jobby/config.yaml`:
```yaml
# k (kilobytes), m (megabytes), g (gigabytes)
log-file-size: 2m
```

### Serve as daemon
Start a job file as a background process:
```sh
$ jobby serve <jobsFileName.cfg>
jobby :: Started jobby daemon with PID 34019 for job file: /home/user/.jobby/jobs.cfg
jobby :: Daemon output will be logged to: /home/user/.jobby/jobs.log
jobby :: Use 'jobby stop 34019' to stop the daemon.
```

### View logs
You can view the log output associated with a specific `job.cfg` file:
```sh
$ jobby log <jobsFileName.cfg>
jobby :: === Log for job file: jobs.cfg ===
jobby :: Log file: /home/user/.jobby/jobs.log
jobby :: Log size: 54 B
jobby :: --- Log Contents ---
<<<
Execute once when 'jobby' is launched.
Execute every second.
Execute every 5 seconds.
Execute every 29 seconds.
Execute every second.
>>>
jobby :: --- End of Log ---
```

Log output (`stdout/stderr`) for each job is written to individual log files located at:
```sh
~/.jobby/<jobsFileName>.log
```

### See running daemons
Check all jobs started by jobby:
```sh
$ jobby list
  PID   Jobs file
34019   /home/user/.jobby/jobs.cfg
```
**NOTE:** This list is tracked in `~/.jobby/jobs.lock`. It does not guarantee the processes are still running.

### Check for dead deamons
Identify jobs whose daemons are no longer running:
```sh
$ jobby check
  PID   Jobs file (dead daemon)
40047   /home/user/.jobby/jobs.cfg
```

### Restart dead jobs
Restart jobs that were previously running but are now dead:
```sh
$ jobby restart
  PID   Jobs file (dead daemon)
40047   /home/user/.jobby/jobs.cfg
jobby :: Restarting daemon: /home/user/.jobby/jobs.cfg
jobby :: Failed to stop process with PID=40047: /home/user/.jobby/jobs.cfg
jobby :: Removed dead process from lock file.
jobby :: Started jobby daemon with PID 40193 for job file: /home/user/.jobby/jobs.cfg
jobby :: Daemon output will be logged to: /home/user/.jobby/jobs.log
jobby :: Use 'jobby stop 40193' to stop the daemon.
```

### Stop job
Stop a running job by providing the job file or PID:
```sh
$ jobby stop <jobsFileName.cfg or PID>
jobby :: Stopped daemon with PID=34019: /home/user/.jobby/jobs.cfg
```

## LICENSE
All code is licensed under the MIT license.

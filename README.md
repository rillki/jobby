# Jobby
A simple task scheduler and executor supporting multiple job files.

## Usage
```sh
jobby v1.0.0 -- A simple task scheduler and executor supporting multiple job files.
USAGE: jobby [command] <jobs.cfg>
COMMANDS:
      run  run with custom job.cfg
    serve  launch in background with custom jobs.cfg
     stop  stop daemon identified with custom jobs.cfg or PID
     list  list running jobs
 validate  validate jobs.cfg format
 help-fmt  job configuration file format documentation and examples.
     help  This help message.
NOTE:
    By default `~/.jobby/jobs.cfg` is used, unless a custom one is specified.
```

### Configuration
Create `~/.jobby/jobs.cfg` or a custom file listing your tasks:
```sh
# r y o d h m s | cmd - this is a comment
* * * * * * * | echo "Execute once when 'jobby' is launched."
s * * * * * * | echo "Execute every second."
s * * * * * 5 | echo "Execute every 5 seconds."
s * * * * * 29 | echo "Execute every 29 seconds."
m * * * * 3 0 | echo "Execute every 3 minutes."
m * * * * * * | echo "Execute every minute."
```
Execute `jobby help-fmt` to see more examples. 

Any `stdout` or `stderr` output will be logged to `~/.jobby/jobsFileName.log`:
```sh
Execute once when 'jobby' is launched.
Execute every second.
Execute every 5 seconds.
Execute every 29 seconds.
Execute every second.
Execute every second.
Execute every second.
Execute every second.
Execute every second.
Execute every 5 seconds.
Execute every second.
...
```

### Serve as daemon
Run your custom jobs file as daemon process:
```sh
# By default `~/.jobby/jobs.cfg` is used, unless a custom one is specified.
$ jobby serve <jobsFileName.cfg>
jobby :: Started jobby daemon with PID 34019 for job file: /home/user/.jobby/jobs.cfg
jobby :: Daemon output will be logged to: /home/user/.jobby/jobs.log
jobby :: Use 'jobby stop 34019' to stop the daemon.
```

### See running daemons
Track all running jobs:
```sh
$ jobby list
  PID   Jobs file
34019   /home/user/.jobby/jobs.cfg
```
This information is logged into an internal `~/.jobby/jobs.lock` file. 

### Stop running daemon
```sh
# By default `~/.jobby/jobs.cfg` is used, unless a custom one is specified.
$ jobby stop <jobsFileName.cfg or PID>
jobby :: Stopped daemon with PID=34019: /home/user/.jobby/jobs.cfg
```

## Planned
* `restart` - restart all previously running daemon jobs. Useful upon system reboot. 

## LICENSE
All code is licensed under the MIT license.

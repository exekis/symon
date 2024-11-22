# Mac System Monitor

A super light-weight Perl script that monitors and logs your Mac's system stats into a JSON. It tells you way more than what Activity Monitor displays. Activity Monitor can be misleading at times. The swap memory used combined with the actual memory usage is never shown and the overall usage can be hard to understand just by reading the values from Activity Monitor. The point of Symon is to make it easier to log your system's stats, so that they can be examined later.

## Features

- Real-time CPU, memory, and disk monitoring
- CPU temperature tracking
- JSON logging
- CPU usage alerts (>90%)
- Terminal display
- More to come :)

## Requirements

- Perl modules: JSON, File::Slurp, Time::HiRes, POSIX
- osx-cpu-temp
- macOS

## Install

```bash
# Perl modules
cpan JSON File::Slurp Time::HiRes

# CPU temperature tool
brew install osx-cpu-temp
```

## Usage

```bash
chmod +x system_monitor.pl
./system_monitor.pl
```

## Output Example

```
===== System Usage at 2024-03-21 15:30:45 =====
CPU Usage:
  User: 25.50%, System: 15.20%, Idle: 59.30%
CPU Temperature: 45.20°C
Memory Usage:
  Used: 8.5 GB (65.38%), Free: 4.5 GB
Disk Usage (/):
  Used: 350GB/500GB (70%)
```

## Files

- `system_usage_log.json`: Main log file
- `cpu_alerts.log`: High CPU usage alerts

## Configuration

Edit these variables at the top of the script:
- `$log_file`: Change log location
- `$monitor_interval`: Adjust check frequency (seconds)

## Help

Check terminal output for errors and verify each command works:
- `top`
- `vm_stat`
- `df`
- `osx-cpu-temp`
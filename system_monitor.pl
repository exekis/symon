#!/usr/bin/perl

use strict;
use warnings;
use JSON;
use File::Slurp;
use Time::HiRes qw(sleep);
use POSIX qw(strftime);
use Sys::Info;
use Sys::Info::OS;
use Sys::Info::Device;

my $log_file = "system_usage_log.json";
my $monitor_interval = 10;
my $history_file = "system_history.json";
my $config_file = "symon_config.json";
my $os = Sys::Info::OS->new();
my $os_name = $os->name();
my $is_linux = ($os_name =~ /linux/i);
my $is_arch = 0;

if ($is_linux) {
    if (-f "/etc/arch-release" || -f "/etc/pacman.conf") {
        $is_arch = 1;
        print "Detected Arch Linux environment\n";
    } else {
        print "Detected Linux environment\n";
    }
} else {
    print "Detected macOS environment\n";
}
my %default_config = (
    monitor_interval => 10,
    cpu_alert_threshold => 90,
    memory_alert_threshold => 85,
    disk_alert_threshold => 90,
    temp_alert_threshold => 80,
    log_file => "system_usage_log.json",
    history_file => "system_history.json",
    enable_alerts => 1,
    enable_network_monitoring => 1,
    enable_process_monitoring => 1,
    max_history_entries => 1000,
);

sub load_config {
    my %config = %default_config;
    if (-f $config_file) {
        eval {
            my $json_text = read_file($config_file);
            my $loaded_config = decode_json($json_text);
            %config = (%config, %$loaded_config);
        };
        if ($@) {
            warn "Failed to load config file: $@\n";
        }
    } else {
        eval {
            write_file($config_file, encode_json(\%config));
        };
    }
    return %config;
}

my %config = load_config();

sub get_cpu_usage {
    print "Collecting CPU usage...\n";
    
    if ($is_linux) {
        my @stat_lines = read_file("/proc/stat");
        my $cpu_line = (grep /^cpu\s/, @stat_lines)[0];
        chomp $cpu_line;
        
        my @cpu_times = split(/\s+/, $cpu_line);
        shift @cpu_times;
        
        my ($user, $nice, $system, $idle, $iowait, $irq, $softirq, $steal) = @cpu_times;
        
        my $total = $user + $nice + $system + $idle + $iowait + $irq + $softirq + ($steal || 0);
        my $user_pct = sprintf("%.2f", ($user + $nice) / $total * 100);
        my $system_pct = sprintf("%.2f", ($system + $irq + $softirq) / $total * 100);
        my $idle_pct = sprintf("%.2f", $idle / $total * 100);
        my $iowait_pct = sprintf("%.2f", ($iowait || 0) / $total * 100);
        
        print "Parsed CPU usage - User: $user_pct%, System: $system_pct%, Idle: $idle_pct%, IOWait: $iowait_pct%\n";
        return {
            user    => $user_pct,
            system  => $system_pct,
            idle    => $idle_pct,
            iowait  => $iowait_pct,
            total_usage => sprintf("%.2f", 100 - $idle_pct),
    } else {
        my @top_output = `top -l 1 -n 0 2>/dev/null`;
        
        if (!$?) {
            print "top command executed successfully.\n";
        } else {
            warn "top command failed to execute.\n";
        }

        print "top output:\n", join("\n", @top_output), "\n";

        my ($user, $system, $idle);
        foreach my $line (@top_output) {
            if ($line =~ /CPU usage:\s+(\d+\.\d+)% user, (\d+\.\d+)% sys, (\d+\.\d+)% idle/) {
                ($user, $system, $idle) = ($1, $2, $3);
                last;
            }
        }

        if (defined $user && defined $system && defined $idle) {
            print "Parsed CPU usage - User: $user%, System: $system%, Idle: $idle%\n";
            return {
                user    => $user,
                system  => $system,
                idle    => $idle,
                iowait  => 0,
                total_usage => sprintf("%.2f", $user + $system),
            };
        } else {
            warn "Failed to parse CPU usage from top output.\n";
            return { user => 0, system => 0, idle => 0, iowait => 0, total_usage => 0 };
        }
    }
}

sub get_cpu_temperature {
    print "Collecting CPU temperature...\n";
    
    if ($is_linux) {
        my $temp = 0;
        
        my @sensors_output = `sensors 2>/dev/null`;
        if (!$? && @sensors_output) {
            print "sensors command executed successfully.\n";
            print "sensors output:\n", join("\n", @sensors_output), "\n";
            
            foreach my $line (@sensors_output) {
                if ($line =~ /(?:Core|CPU|Package|Tdie).*?(\d+\.\d+)°C/) {
                    $temp = $1;
                    last;
                }
            }
        }
        
        if ($temp == 0) {
            my @thermal_zones = glob("/sys/class/thermal/thermal_zone*/temp");
            if (@thermal_zones) {
                eval {
                    my $thermal_temp = read_file($thermal_zones[0]);
                    chomp $thermal_temp;
                    $temp = sprintf("%.2f", $thermal_temp / 1000);
                };
                if ($@) {
                    warn "Failed to read thermal zone: $@\n";
                }
            }
        }
        
        if ($temp == 0) {
            my @acpi_output = `acpi -t 2>/dev/null`;
            if (!$? && @acpi_output) {
                foreach my $line (@acpi_output) {
                    if ($line =~ /(\d+\.\d+) degrees C/) {
                        $temp = $1;
                        last;
                    }
                }
            }
        }
        
    } else {
        my @temp_output = `osx-cpu-temp 2>/dev/null`;
        
        if (!$?) {
            print "osx-cpu-temp command executed successfully.\n";
        } else {
            warn "osx-cpu-temp command failed to execute.\n";
        }

        print "osx-cpu-temp output:\n", join("\n", @temp_output), "\n";

        my $temp = 0;
        if (@temp_output && $temp_output[0] =~ /(\d+\.\d+)°C/) {
            $temp = $1;
        } else {
            warn "Failed to parse CPU temperature.\n";
        }
        print "Parsed CPU temperature: ${temp}°C\n";
        return $temp;
    }
}


sub get_memory_usage {
    print "Collecting Memory usage...\n";
    
    if ($is_linux) {
        my @meminfo_lines = read_file("/proc/meminfo");
        my %mem_data;
        
        foreach my $line (@meminfo_lines) {
            if ($line =~ /^(\w+):\s+(\d+)\s+kB/) {
                $mem_data{$1} = $2 * 1024;
            }
        }
        
        my $total = $mem_data{MemTotal} || 0;
        my $free = $mem_data{MemFree} || 0;
        my $available = $mem_data{MemAvailable} || $free;
        my $buffers = $mem_data{Buffers} || 0;
        my $cached = $mem_data{Cached} || 0;
        my $used = $total - $available;
        my $percent_used = sprintf("%.2f", ($used / $total) * 100);
        
        print "Parsed Memory usage - Total: $total bytes, Used: $used bytes, Available: $available bytes, Percent Used: $percent_used%\n";
        return {
            total        => $total,
            used         => $used,
            free         => $free,
            available    => $available,
            buffers      => $buffers,
            cached       => $cached,
            percent_used => $percent_used,
    } else {
        my @vm_stat_output = `vm_stat 2>/dev/null`;
        if (!$?) {
            print "vm_stat command executed successfully.\n";
        } else {
            warn "vm_stat command failed to execute.\n";
        }
        print "vm_stat output:\n", join("\n", @vm_stat_output), "\n";
        
        my %memory;
        foreach my $line (@vm_stat_output) {
            if ($line =~ /^Pages free:\s+(\d+)\./) {
                $memory{free} = $1 * 4096;
            }
            elsif ($line =~ /^Pages active:\s+(\d+)\./) {
                $memory{active} = $1 * 4096;
            }
            elsif ($line =~ /^Pages inactive:\s+(\d+)\./) {
                $memory{inactive} = $1 * 4096;
            }
            elsif ($line =~ /^Pages speculative:\s+(\d+)\./) {
                $memory{speculative} = $1 * 4096;
            }
            elsif ($line =~ /^Pages wired down:\s+(\d+)\./) {
                $memory{wired} = $1 * 4096;
            }
            elsif ($line =~ /^Pages purgeable:\s+(\d+)\./) {
                $memory{purgeable} = $1 * 4096;
            }
        }
        
        # "actual" used memory
        my $used = $memory{active} + $memory{inactive} + $memory{wired} + $memory{speculative};
        my $total = $used + $memory{free} + $memory{purgeable};
        my $percent_used = sprintf("%.2f", ($used / $total) * 100);
        
        print "Parsed Memory usage - Total: $total, Used: $used, Free: $memory{free}, Percent Used: $percent_used\n";
        return {
            total        => $total,
            used         => $used,
            free         => $memory{free},
            available    => $memory{free} + $memory{purgeable},
            buffers      => 0,
            cached       => 0,
            percent_used => $percent_used,
        };
    }
}

sub get_disk_usage {
    print "Collecting Disk usage...\n";
    my @df_output = `df -h / 2>/dev/null`;
    if (!$?) {
        print "df command executed successfully.\n";
    } else {
        warn "df command failed to execute.\n";
    }
    print "df output:\n", join("\n", @df_output), "\n";
    
    if (@df_output < 2) {
        warn "Unexpected df output format.\n";
        return {
            filesystem  => "N/A",
            size        => "N/A",
            used        => "N/A",
            available   => "N/A",
            use_percent => "N/A",
            mounted_on  => "N/A",
        };
    }
    
    my ($filesystem, $size, $used, $avail, $use_perc, $mounted_on) = split(/\s+/, $df_output[1]);
    
    print "Parsed Disk usage - Filesystem: $filesystem, Size: $size, Used: $used, Available: $avail, Use%: $use_perc, Mounted on: $mounted_on\n";
    return {
        filesystem  => $filesystem,
        size        => $size,
        used        => $used,
        available   => $avail,
        use_percent => $use_perc,
        mounted_on  => $mounted_on,
    };
}

sub get_network_stats {
    print "Collecting Network statistics...\n";
    
    if ($is_linux) {
        my @net_lines = read_file("/proc/net/dev");
        my %network_data;
        
        foreach my $line (@net_lines) {
            next if $line !~ /:/;
            $line =~ s/^\s+//;
            my ($interface, $stats) = split(/:/, $line, 2);
            next if $interface eq 'lo';
            
            my @stats_array = split(/\s+/, $stats);
            $network_data{$interface} = {
                rx_bytes => $stats_array[0],
                rx_packets => $stats_array[1],
                rx_errors => $stats_array[2],
                tx_bytes => $stats_array[8],
                tx_packets => $stats_array[9],
                tx_errors => $stats_array[10],
            };
        }
        
    } else {
        my @netstat_output = `netstat -ib 2>/dev/null`;
        my %network_data;
        
        foreach my $line (@netstat_output) {
            next if $line !~ /^\w/;
            my @fields = split(/\s+/, $line);
            next if @fields < 10;
            next if $fields[0] eq 'lo0';
            
            $network_data{$fields[0]} = {
                rx_bytes => $fields[6],
                rx_packets => $fields[4],
                rx_errors => $fields[5],
                tx_bytes => $fields[9],
                tx_packets => $fields[7],
                tx_errors => $fields[8],
            };
        }
        
        print "Parsed Network stats for interfaces: " . join(", ", keys %network_data) . "\n";
        return \%network_data;
    }
}

sub get_system_load {
    print "Collecting System load...\n";
    
    if ($is_linux) {
        my $loadavg = read_file("/proc/loadavg");
        chomp $loadavg;
        my ($load1, $load5, $load15, $processes) = split(/\s+/, $loadavg);
        my ($running, $total) = split(/\//, $processes);
        
        return {
            load_1min => $load1,
            load_5min => $load5,
            load_15min => $load15,
            processes_running => $running,
            processes_total => $total,
        };
    } else {
        my $uptime_output = `uptime 2>/dev/null`;
        my ($load1, $load5, $load15);
        if ($uptime_output =~ /load averages: (\d+\.\d+) (\d+\.\d+) (\d+\.\d+)/) {
            ($load1, $load5, $load15) = ($1, $2, $3);
        }
        
        return {
            load_1min => $load1 || 0,
            load_5min => $load5 || 0,
            load_15min => $load15 || 0,
            processes_running => 0,
            processes_total => 0,
        };
    }
}

sub get_top_processes {
    print "Collecting Top processes...\n";
    
    my @processes;
    if ($is_linux) {
        my @ps_output = `ps aux --sort=-%cpu | head -10 2>/dev/null`;
        shift @ps_output;
        
        foreach my $line (@ps_output) {
            my @fields = split(/\s+/, $line, 11);
            next if @fields < 11;
            
            push @processes, {
                user => $fields[0],
                pid => $fields[1],
                cpu => $fields[2],
                memory => $fields[3],
                command => $fields[10],
            };
        }
    } else {
        my @ps_output = `ps aux -r | head -10 2>/dev/null`;
        shift @ps_output;
        
        foreach my $line @ps_output {
            my @fields = split(/\s+/, $line, 11);
            next if @fields < 11;
            
            push @processes, {
                user => $fields[0],
                pid => $fields[1],
                cpu => $fields[2],
                memory => $fields[3],
                command => $fields[10],
            };
        }
    }
    
    print "Collected " . scalar(@processes) . " top processes\n";
    return \@processes;
}

sub get_disk_io_stats {
    print "Collecting Disk I/O statistics...\n";
    
    if ($is_linux) {
        my @diskstats_lines = read_file("/proc/diskstats");
        my %disk_io;
        
        foreach my $line (@diskstats_lines) {
            chomp $line;
            my @fields = split(/\s+/, $line);
            next if @fields < 14;
            
            my $device = $fields[2];
            next if $device =~ /^(loop|ram|sr)/;
            
            $disk_io{$device} = {
                reads_completed => $fields[3],
                reads_merged => $fields[4],
                sectors_read => $fields[5],
                time_reading => $fields[6],
                writes_completed => $fields[7],
                writes_merged => $fields[8],
                sectors_written => $fields[9],
                time_writing => $fields[10],
            };
        }
        
    } else {
        my @iostat_output = `iostat -d 2>/dev/null`;
        my %disk_io;
        
        foreach my $line (@iostat_output) {
            if ($line =~ /^(\w+)\s+(\d+\.\d+)\s+(\d+\.\d+)/) {
                $disk_io{$1} = {
                    reads_per_sec => $2,
                    writes_per_sec => $3,
                };
            }
        }
        
        print "Parsed Disk I/O stats for devices: " . join(", ", keys %disk_io) . "\n";
        return \%disk_io;
    }
}

sub get_system_uptime {
    print "Collecting System uptime...\n";
    
    if ($is_linux) {
        my $uptime_data = read_file("/proc/uptime");
        chomp $uptime_data;
        my ($uptime_seconds, $idle_seconds) = split(/\s+/, $uptime_data);
        
        my $days = int($uptime_seconds / 86400);
        my $hours = int(($uptime_seconds % 86400) / 3600);
        my $minutes = int(($uptime_seconds % 3600) / 60);
        
        return {
            uptime_seconds => $uptime_seconds,
            uptime_formatted => "${days}d ${hours}h ${minutes}m",
            idle_seconds => $idle_seconds,
        };
    } else {
        my $uptime_output = `sysctl -n kern.boottime 2>/dev/null`;
        my $uptime_seconds = 0;
        if ($uptime_output =~ /sec = (\d+)/) {
            $uptime_seconds = time() - $1;
        }
        
        my $days = int($uptime_seconds / 86400);
        my $hours = int(($uptime_seconds % 86400) / 3600);
        my $minutes = int(($uptime_seconds % 3600) / 60);
        
        return {
            uptime_seconds => $uptime_seconds,
            uptime_formatted => "${days}d ${hours}h ${minutes}m",
            idle_seconds => 0,
        };
    }
}

sub log_data {
    my ($data) = @_;
    my $timestamp = strftime "%Y-%m-%d %H:%M:%S", localtime;
    $data->{timestamp} = $timestamp;
    
    eval {
        write_file($config{log_file}, { append => 1 }, encode_json($data) . "\n");
        print "Logged data to $config{log_file}\n";
    };
    if ($@) {
        warn "Failed to write to log file: $@\n";
    }
}

sub display_data {
    my ($data) = @_;
    
    system("clear") if $is_linux;
    system("clear") unless $is_linux;
    
    print "\n" . "="x80 . "\n";
    print "  SYMON - Advanced System Monitor for " . ($is_arch ? "Arch Linux" : ($is_linux ? "Linux" : "macOS")) . "\n";
    print "  Time: $data->{timestamp}\n";
    print "="x80 . "\n";
    
    print "\nSYSTEM OVERVIEW:\n";
    print "   Uptime: $data->{uptime}{uptime_formatted}\n" if $data->{uptime};
    
    print "\nCPU USAGE:\n";
    printf "   User: %.2f%%, System: %.2f%%, Idle: %.2f%%\n", 
        $data->{cpu}{user}, $data->{cpu}{system}, $data->{cpu}{idle};
    printf "   IOWait: %.2f%%, Total Usage: %.2f%%\n", 
        $data->{cpu}{iowait}, $data->{cpu}{total_usage};
    printf "   Temperature: %.2f°C\n", $data->{cpu_temp};
    
    if ($data->{load}) {
        print "\nSYSTEM LOAD:\n";
        printf "   1min: %.2f, 5min: %.2f, 15min: %.2f\n",
            $data->{load}{load_1min}, $data->{load}{load_5min}, $data->{load}{load_15min};
        printf "   Processes: %d running, %d total\n",
            $data->{load}{processes_running}, $data->{load}{processes_total};
    }
    
    print "\nMEMORY USAGE:\n";
    printf "   Used: %.2f GB (%.2f%%), Available: %.2f GB\n", 
        $data->{memory}{used} / (1024**3),
        $data->{memory}{percent_used},
        $data->{memory}{available} / (1024**3);
    printf "   Total: %.2f GB, Free: %.2f GB\n",
        $data->{memory}{total} / (1024**3),
        $data->{memory}{free} / (1024**3);
    if ($is_linux) {
        printf "   Buffers: %.2f GB, Cached: %.2f GB\n",
            $data->{memory}{buffers} / (1024**3),
            $data->{memory}{cached} / (1024**3);
    }
    
    print "\nDISK USAGE:\n";
    printf "   %s: %s used, %s available (%s)\n", 
        $data->{disk}{mounted_on},
        $data->{disk}{used},
        $data->{disk}{available},
        $data->{disk}{use_percent};
    printf "   Filesystem: %s, Size: %s\n",
        $data->{disk}{filesystem},
        $data->{disk}{size};
    
    if ($data->{network} && %{$data->{network}}) {
        print "\nNETWORK STATISTICS:\n";
        foreach my $interface (keys %{$data->{network}}) {
            my $net = $data->{network}{$interface};
            printf "   %s: RX: %.2f MB, TX: %.2f MB\n", 
                $interface, 
                $net->{rx_bytes} / (1024**2), 
                $net->{tx_bytes} / (1024**2);
        }
    }
    
    if ($data->{processes} && @{$data->{processes}}) {
        print "\nTOP PROCESSES (by CPU):\n";
        printf "   %-10s %-8s %-6s %-6s %s\n", "USER", "PID", "CPU%", "MEM%", "COMMAND";
        printf "   %s\n", "-" x 60;
        foreach my $proc (@{$data->{processes}}[0..4]) {
            last unless $proc;
            my $cmd = length($proc->{command}) > 25 ? substr($proc->{command}, 0, 25) . "..." : $proc->{command};
            printf "   %-10s %-8s %-6.1f %-6.1f %s\n", 
                $proc->{user}, $proc->{pid}, $proc->{cpu}, $proc->{memory}, $cmd;
        }
    }
    
    if ($data->{trends}) {
        print "\nPERFORMANCE TRENDS (last $data->{trends}{data_points} samples):\n";
        printf "   Avg CPU: %.2f%%, Avg Memory: %.2f%%, Avg Temp: %.2f°C\n",
            $data->{trends}{avg_cpu}, $data->{trends}{avg_memory}, $data->{trends}{avg_temp};
    }
    
    if ($data->{alerts} && @{$data->{alerts}}) {
        print "\nACTIVE ALERTS:\n";
        foreach my $alert (@{$data->{alerts}}) {
            my $icon = $alert->{level} eq 'critical' ? '[!]' : '[*]';
            printf "   %s %s: %s\n", $icon, uc($alert->{level}), $alert->{message};
        }
    }
    
    print "\n" . "="x80 . "\n";
    print "Press Ctrl+C to stop monitoring | Next update in $config{monitor_interval} seconds\n";
    print "="x80 . "\n\n";
}

sub check_alerts {
    my ($data) = @_;
    my @alerts;
    
    if ($config{enable_alerts}) {
        if ($data->{cpu}{total_usage} > $config{cpu_alert_threshold}) {
            push @alerts, {
                type => 'cpu',
                level => 'warning',
                message => "High CPU usage: $data->{cpu}{total_usage}%",
                threshold => $config{cpu_alert_threshold},
                current => $data->{cpu}{total_usage},
            };
        }
        
        if ($data->{memory}{percent_used} > $config{memory_alert_threshold}) {
            push @alerts, {
                type => 'memory',
                level => 'warning',
                message => "High memory usage: $data->{memory}{percent_used}%",
                threshold => $config{memory_alert_threshold},
                current => $data->{memory}{percent_used},
            };
        }
        
        if ($data->{disk}{use_percent} =~ /(\d+)%/ && $1 > $config{disk_alert_threshold}) {
            push @alerts, {
                type => 'disk',
                level => 'warning',
                message => "High disk usage: $data->{disk}{use_percent}",
                threshold => $config{disk_alert_threshold},
                current => $1,
            };
        }
        
        if ($data->{cpu_temp} > $config{temp_alert_threshold}) {
            push @alerts, {
                type => 'temperature',
                level => 'critical',
                message => "High CPU temperature: $data->{cpu_temp}°C",
                threshold => $config{temp_alert_threshold},
                current => $data->{cpu_temp},
            };
        }
        
        if ($is_linux && $data->{load}) {
            my $cpu_count = `nproc 2>/dev/null` || 1;
            chomp $cpu_count;
            if ($data->{load}{load_1min} > $cpu_count * 1.5) {
                push @alerts, {
                    type => 'load',
                    level => 'warning',
                    message => "High system load: $data->{load}{load_1min}",
                    threshold => $cpu_count * 1.5,
                    current => $data->{load}{load_1min},
                };
            }
        }
    }
    
    return \@alerts;
}

sub log_alerts {
    my ($alerts) = @_;
    return unless @$alerts;
    
    my $alert_file = "system_alerts.log";
    my $timestamp = strftime "%Y-%m-%d %H:%M:%S", localtime;
    
    foreach my $alert (@$alerts) {
        my $log_entry = "[$timestamp] $alert->{level}: $alert->{message}\n";
        eval {
            write_file($alert_file, { append => 1 }, $log_entry);
        };
        if ($@) {
            warn "Failed to write alert to log: $@\n";
        }
    }
}

sub update_history {
    my ($data) = @_;
    my @history;
    
    if (-f $config{history_file}) {
        eval {
            my $json_text = read_file($config{history_file});
            @history = @{decode_json($json_text)};
        };
        if ($@) {
            warn "Failed to load history file: $@\n";
        }
    }
    
    push @history, $data;
    
    if (@history > $config{max_history_entries}) {
        shift @history;
    }
    
    eval {
        write_file($config{history_file}, encode_json(\@history));
    };
    if ($@) {
        warn "Failed to write history file: $@\n";
    }
}

sub get_performance_trends {
    my @history;
    
    if (-f $config{history_file}) {
        eval {
            my $json_text = read_file($config{history_file});
            @history = @{decode_json($json_text)};
        };
        if ($@) {
            warn "Failed to load history for trends: $@\n";
            return {};
        }
    }
    
    return {} if @history < 2;
    
    my $entries = @history >= 10 ? 10 : @history;
    my @recent = @history[-$entries..-1];
    
    my ($cpu_sum, $mem_sum, $temp_sum) = (0, 0, 0);
    foreach my $entry (@recent) {
        $cpu_sum += $entry->{cpu}{total_usage} || 0;
        $mem_sum += $entry->{memory}{percent_used} || 0;
        $temp_sum += $entry->{cpu_temp} || 0;
    }
    
    return {
        avg_cpu => sprintf("%.2f", $cpu_sum / $entries),
        avg_memory => sprintf("%.2f", $mem_sum / $entries),
        avg_temp => sprintf("%.2f", $temp_sum / $entries),
        data_points => $entries,
    };
}
sub monitor_system {
    print "Starting enhanced system monitoring...\n";
    print "OS: " . ($is_arch ? "Arch Linux" : ($is_linux ? "Linux" : "macOS")) . "\n";
    print "Monitoring interval: $config{monitor_interval} seconds\n";
    print "Features enabled: CPU, Memory, Disk, Temperature";
    print ", Network" if $config{enable_network_monitoring};
    print ", Processes" if $config{enable_process_monitoring};
    print ", Alerts" if $config{enable_alerts};
    print "\n\n";
    
    while (1) {
        print "Starting new monitoring cycle...\n";
        my %data;
        
        $data{cpu} = get_cpu_usage();
        $data{cpu_temp} = get_cpu_temperature();
        $data{memory} = get_memory_usage();
        $data{disk} = get_disk_usage();
        $data{uptime} = get_system_uptime();
        $data{load} = get_system_load() if $is_linux;
        
        if ($config{enable_network_monitoring}) {
            $data{network} = get_network_stats();
        }
        
        if ($config{enable_process_monitoring}) {
            $data{processes} = get_top_processes();
        }
        
        $data{timestamp} = strftime "%Y-%m-%d %H:%M:%S", localtime;
        
        $data{trends} = get_performance_trends();
        
        $data{alerts} = check_alerts(\%data);
        
        log_alerts($data{alerts}) if @{$data{alerts}};
        
        display_data(\%data);
        
        log_data(\%data);
        
        update_history(\%data);
        
        sleep($config{monitor_interval});
    }
}

$SIG{INT} = sub {
    print "\nSystem monitoring terminated by user.\n";
    print "Final statistics saved to log files.\n";
    exit 0;
};

print "Starting SYMON - Advanced System Monitor\n";
print "Platform: " . ($is_arch ? "Arch Linux" : ($is_linux ? "Linux" : "macOS")) . "\n";
print "Monitoring interval: $config{monitor_interval} seconds\n";
print "Log files: $config{log_file}, $config{history_file}\n";
print "Configuration: $config_file\n";
print "Press Ctrl+C to stop monitoring\n";
print "="x60 . "\n\n";

monitor_system();
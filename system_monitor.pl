#!/usr/bin/perl

use strict;
use warnings;
use JSON;
use File::Slurp;
use Time::HiRes qw(sleep);
use POSIX qw(strftime);

my $log_file = "system_usage_log.json";
my $monitor_interval = 60; # in seconds

sub get_cpu_usage {
    print "Collecting CPU usage...\n";
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
        print "Parsed CPU usage - User: $user, System: $system, Idle: $idle\n";
        return {
            user    => $user,
            system  => $system,
            idle    => $idle,
        };
    } else {
        warn "Failed to parse CPU usage from top output.\n";
        return { user => 0, system => 0, idle => 0 };
    }
}

# uses osx-cpu-temp
sub get_cpu_temperature {
    print "Collecting CPU temperature...\n";
    my @temp_output = `osx-cpu-temp 2>/dev/null`;
    
    if (!$?) {
        print "osx-cpu-temp command executed successfully.\n";
    } else {
        warn "osx-cpu-temp command failed to execute.\n";
    }

    print "osx-cpu-temp output:\n", join("\n", @temp_output), "\n";

    my $temp;
    if ($temp_output[0] =~ /(\d+\.\d+)°C/) {
        $temp = $1;
    } else {
        warn "Failed to parse CPU temperature.\n";
        $temp = 0;
    }
    print "Parsed CPU temperature: $temp°C\n";
    return $temp;
}


sub get_memory_usage {
    print "Collecting Memory usage...\n";
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
            $memory{free} = $1 * 4096; # pages to bytes
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
        percent_used => $percent_used,
    };
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
    
    # parsing
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

# logging
sub log_data {
    my ($data) = @_;
    my $timestamp = strftime "%Y-%m-%d %H:%M:%S", localtime;
    $data->{timestamp} = $timestamp;
    
    eval {
        write_file($log_file, { append => 1 }, encode_json($data) . "\n");
        print "Logged data to $log_file\n";
    };
    if ($@) {
        warn "Failed to write to log file: $@\n";
    }
}

# print in terminal
sub display_data {
    my ($data) = @_;
    print "\n===== System Usage at $data->{timestamp} =====\n";
    print "CPU Usage:\n";
    printf "  User: %.2f%%, System: %.2f%%, Idle: %.2f%%\n", $data->{cpu}{user}, $data->{cpu}{system}, $data->{cpu}{idle};
    print "CPU Temperature:\n";
    printf "  Temperature: %.2f°C\n", $data->{cpu_temp};
    print "Memory Usage:\n";
    printf "  Used: %.2f GB (%.2f%%), Free: %.2f GB\n", 
        $data->{memory}{used} / (1024**3),
        $data->{memory}{percent_used},
        $data->{memory}{free} / (1024**3);
    print "Disk Usage (Mounted on $data->{disk}{mounted_on}):\n";
    printf "  Size: %s, Used: %s, Available: %s, Usage: %s\n", 
        $data->{disk}{size},
        $data->{disk}{used},
        $data->{disk}{available},
        $data->{disk}{use_percent};
    print "===========================================\n\n";
}

# main function
sub monitor_system {
    while (1) {
        print "Starting new monitoring cycle...\n";
        my %data;
        $data{cpu}      = get_cpu_usage();
        print "Got CPU usage.\n";
        $data{cpu_temp} = get_cpu_temperature();
        print "Got CPU temperature.\n";
        $data{memory}   = get_memory_usage();
        print "Got Memory usage.\n";
        $data{disk}     = get_disk_usage();
        print "Got Disk usage.\n";
        $data{timestamp} = strftime "%Y-%m-%d %H:%M:%S", localtime;
        
        display_data(\%data);
        log_data(\%data);
        
        my $total_cpu = $data{cpu}{user} + $data{cpu}{system};
        if ($total_cpu > 90) {
            print "ALERT: High CPU usage detected! User + System = $total_cpu%\n";
            write_file("cpu_alerts.log", { append => 1 }, strftime("%Y-%m-%d %H:%M:%S", localtime) . " - High CPU usage: $total_cpu%\n");
        }
        
        print "Sleeping for $monitor_interval seconds...\n";
        sleep($monitor_interval);
    }
}

# termination
$SIG{INT} = sub {
    print "\nMonitoring terminated by user.\n";
    exit 0;
};


print "Starting system monitoring. Press Ctrl + C to stop.\n";
monitor_system();
#!/usr/bin/perl

use strict;
use warnings;
use FindBin qw($Bin);
use lib "$Bin/lib";
use JSON;
use Getopt::Long;
use SystemMonitor::Config;
use SystemMonitor::Display;
use SystemMonitor::Logger;

# options
my %options = (
    'help'       => 0,
    'config'     => 'monitor_config.json',
    'interval'   => 5,
    'duration'   => 0,
    'cpu-threshold' => 90.0,
    'memory-threshold' => 85.0,
    'temp-threshold' => 80.0,
    'alerts'     => 1,
    'log-file'   => 'system_monitor.log',
    'rust-core'  => 1,
    'compact'    => 0,
    'no-color'   => 0,
);

GetOptions(
    'help|h'              => \$options{help},
    'config|c=s'          => \$options{config},
    'interval|i=i'        => \$options{interval},
    'duration|d=i'        => \$options{duration},
    'cpu-threshold=f'     => \$options{'cpu-threshold'},
    'memory-threshold=f'  => \$options{'memory-threshold'},
    'temp-threshold=f'    => \$options{'temp-threshold'},
    'alerts|a!'           => \$options{alerts},
    'log-file=s'          => \$options{'log-file'},
    'rust-core!'          => \$options{'rust-core'},
    'compact'             => \$options{compact},
    'no-color'            => \$options{'no-color'},
) or die("Error parsing command line options\n");

if ($options{help}) {
    show_help();
    exit 0;
}

my $monitor = SystemMonitor::Core->new(\%options);
$monitor->run();

sub show_help {
    print <<'EOF';
System Monitor - Perl/Rust Hybrid

USAGE:
    system_monitor_modular.pl [OPTIONS]

OPTIONS:
    -h, --help                    Show this help message
    -c, --config FILE             Configuration file (default: monitor_config.json)
    -i, --interval SECONDS        Update interval in seconds (default: 5)
    -d, --duration SECONDS        Run duration in seconds (0 = infinite)
    --cpu-threshold PERCENT       CPU usage alert threshold (default: 90.0)
    --memory-threshold PERCENT    Memory usage alert threshold (default: 85.0)
    --temp-threshold CELSIUS      Temperature alert threshold (default: 80.0)
    --alerts / --no-alerts        Enable/disable alerts (default: enabled)
    --log-file FILE               Log file path (default: system_monitor.log)
    --rust-core / --no-rust-core  Use Rust core or fallback to Perl (default: enabled)
    --compact                     Compact display mode
    --no-color                    Disable colored output

EXAMPLES:
    system_monitor_modular.pl                           # Use default settings
    system_monitor_modular.pl -i 10 -d 300             # 10s interval, 5min duration
    system_monitor_modular.pl --no-rust-core --compact # Perl mode, compact display
    system_monitor_modular.pl -c custom_config.json    # Use custom config

EOF
}

package SystemMonitor::Core;

use strict;
use warnings;
use JSON;
use POSIX qw(strftime);
use FindBin qw($Bin);

sub new {
    my ($class, $options) = @_;
    my $self = {
        options => $options || {},
        config => SystemMonitor::Config->new(),
        display => SystemMonitor::Display->new(),
        logger => SystemMonitor::Logger->new(),
        rust_available => 0,
        ffi => undef,
    };
    
    bless $self, $class;
    
    $self->{display}->set_color_mode(!$self->{options}{'no-color'});
    $self->{display}->set_compact_mode($self->{options}{compact});
    
    $self->{logger}->set_log_file($self->{options}{'log-file'});
    
    if ($self->{options}{'rust-core'}) {
        $self->_load_rust_core();
    }
    
    return $self;
}

sub _load_rust_core {
    my ($self) = @_;
    
    eval {
        require FFI::Platypus;
        my $ffi = FFI::Platypus->new( api => 1 );
        
        my $lib_path = "$Bin/target/release/libsymon_core.so";
        unless (-f $lib_path) {
            die "Rust library not found at $lib_path";
        }
        
        $ffi->lib($lib_path);
        
        $ffi->attach( run_system_monitor_with_config => ['string'] => 'int' );
        $ffi->attach( get_system_stats_json => [] => 'opaque' );
        $ffi->attach( free_string => ['opaque'] => 'void' );
        
        $ffi->attach( get_cpu_usage_c => [] => 'float' );
        $ffi->attach( get_memory_total_c => [] => 'uint64' );
        $ffi->attach( get_memory_used_c => [] => 'uint64' );
        $ffi->attach( get_cpu_temperature_c => [] => 'float' );
        
        $self->{ffi} = $ffi;
        $self->{rust_available} = 1;
        
        print "✓ Rust core loaded successfully\n";
    };
    
    if ($@) {
        warn "⚠ Failed to load Rust core: $@\n";
        warn "⚠ Falling back to Perl implementation\n";
        $self->{rust_available} = 0;
    }
}

sub run {
    my ($self) = @_;
    
    if ($self->{rust_available}) {
        $self->_run_rust_core();
    } else {
        $self->_run_perl_fallback();
    }
}

sub _run_rust_core {
    my ($self) = @_;
    
    print "Starting System Monitor (Rust Core)\n";
    print "Press Ctrl+C to stop\n\n";
    
    my $config = {
        interval => $self->{options}{interval},
        duration => $self->{options}{duration},
        cpu_threshold => $self->{options}{'cpu-threshold'},
        memory_threshold => $self->{options}{'memory-threshold'},
        temperature_threshold => $self->{options}{'temp-threshold'},
        enable_alerts => $self->{options}{alerts} ? JSON::true : JSON::false,
        log_file => $self->{options}{'log-file'},
    };
    
    my $config_json = encode_json($config);
    
    my $result = $self->{ffi}->run_system_monitor_with_config($config_json);
    
    if ($result != 0) {
        die "Rust monitor exited with error code: $result\n";
    }
}

sub _run_perl_fallback {
    my ($self) = @_;
    
    print "Starting System Monitor (Perl Fallback)\n";
    print "Press Ctrl+C to stop\n\n";
    
    my $start_time = time();
    my $iteration = 0;
    
    while (1) {
        $iteration++;
        
        if ($self->{options}{duration} > 0) {
            my $elapsed = time() - $start_time;
            last if $elapsed >= $self->{options}{duration};
        }
        
        my $stats = $self->_collect_perl_stats();
        
        $self->_display_perl_stats($stats, $iteration);
        
        if ($self->{options}{alerts}) {
            $self->_check_perl_alerts($stats);
        }
        
        $self->{logger}->log_system_stats($stats);
        
        sleep($self->{options}{interval});
    }
}

sub _collect_perl_stats {
    my ($self) = @_;
    
    my $stats = {
        timestamp => time(),
        cpu => $self->_get_perl_cpu_stats(),
        memory => $self->_get_perl_memory_stats(),
        system_info => $self->_get_perl_system_info(),
    };
    
    return $stats;
}

sub _get_perl_cpu_stats {
    my ($self) = @_;
    
    my $cpu_usage = 0;
    my $temperature = 0;
    my $cores = 1;
    
    if (open my $stat_fh, '<', '/proc/stat') {
        my $line = <$stat_fh>;
        close $stat_fh;
        
        if ($line =~ /^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/) {
            my ($user, $nice, $system, $idle) = ($1, $2, $3, $4);
            my $total = $user + $nice + $system + $idle;
            $cpu_usage = $total > 0 ? (($user + $nice + $system) / $total) * 100 : 0;
        }
    }
    
    if (open my $cpuinfo_fh, '<', '/proc/cpuinfo') {
        while (my $line = <$cpuinfo_fh>) {
            if ($line =~ /^processor\s*:\s*(\d+)/) {
                $cores = $1 + 1;
            }
        }
        close $cpuinfo_fh;
    }
    
    if (open my $temp_fh, '<', '/sys/class/thermal/thermal_zone0/temp') {
        my $temp_str = <$temp_fh>;
        close $temp_fh;
        
        if ($temp_str && $temp_str =~ /^\d+$/) {
            $temperature = $temp_str / 1000.0;
        }
    }
    
    return {
        usage_percent => $cpu_usage,
        cores => $cores,
        temperature => $temperature,
    };
}

sub _get_perl_memory_stats {
    my ($self) = @_;
    
    my %meminfo;
    
    if (open my $meminfo_fh, '<', '/proc/meminfo') {
        while (my $line = <$meminfo_fh>) {
            if ($line =~ /^(\w+):\s*(\d+)\s*kB/) {
                $meminfo{$1} = $2 * 1024;  # Convert to bytes
            }
        }
        close $meminfo_fh;
    }
    
    my $total = $meminfo{MemTotal} || 0;
    my $available = $meminfo{MemAvailable} || $meminfo{MemFree} || 0;
    my $used = $total - $available;
    my $swap_total = $meminfo{SwapTotal} || 0;
    my $swap_used = $swap_total - ($meminfo{SwapFree} || 0);
    
    return {
        total => $total,
        used => $used,
        available => $available,
        pressure_score => $total > 0 ? ($used / $total) * 100 : 0,
        swap_total => $swap_total,
        swap_used => $swap_used,
    };
}

sub _get_perl_system_info {
    my ($self) = @_;
    
    my $hostname = 'unknown';
    my $uptime = 0;
    
    if (open my $hostname_fh, '<', '/proc/sys/kernel/hostname') {
        $hostname = <$hostname_fh>;
        chomp $hostname if $hostname;
        close $hostname_fh;
    }
    
    if (open my $uptime_fh, '<', '/proc/uptime') {
        my $uptime_str = <$uptime_fh>;
        close $uptime_fh;
        
        if ($uptime_str && $uptime_str =~ /^(\d+\.\d+)/) {
            $uptime = int($1);
        }
    }
    
    return {
        hostname => $hostname,
        uptime => $uptime,
    };
}

sub _display_perl_stats {
    my ($self, $stats, $iteration) = @_;
    
    unless ($self->{options}{compact}) {
        $self->{display}->clear_screen();
    }
    
    $self->{display}->display_header($stats->{system_info}{hostname});
    $self->{display}->display_cpu_stats($stats->{cpu});
    $self->{display}->display_memory_stats($stats->{memory});
    $self->{display}->display_system_info($stats->{system_info});
    
    print "Iteration: $iteration\n";
    print "-" x 50 . "\n";
}

sub _check_perl_alerts {
    my ($self, $stats) = @_;
    
    if ($stats->{cpu}{usage_percent} > $self->{options}{'cpu-threshold'}) {
        $self->{display}->display_alert(
            sprintf("High CPU usage: %.1f%%", $stats->{cpu}{usage_percent}),
            'warning'
        );
    }
    
    if ($stats->{memory}{pressure_score} > $self->{options}{'memory-threshold'}) {
        $self->{display}->display_alert(
            sprintf("High memory usage: %.1f%%", $stats->{memory}{pressure_score}),
            'warning'
        );
    }
    
    if ($stats->{cpu}{temperature} > $self->{options}{'temp-threshold'}) {
        $self->{display}->display_alert(
            sprintf("High CPU temperature: %.1f°C", $stats->{cpu}{temperature}),
            'critical'
        );
    }
}

1;

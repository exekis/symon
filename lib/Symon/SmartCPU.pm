#!/usr/bin/perl

package Symon::SmartCPU;

use strict;
use warnings;
use File::Slurp;
use Time::HiRes qw(time);
use List::Util qw(sum max min);

sub new {
    my ($class, $config) = @_;
    my $self = {
        config => $config || {},
        history => [],
        last_measurement => {},
        cpu_cores => get_cpu_cores(),
        process_weights => {},
        scheduler_info => {},
        thermal_throttling => 0,
        boost_states => {},
    };
    
    bless $self, $class;
    $self->initialize_process_weights();
    $self->detect_scheduler();
    return $self;
}

sub get_cpu_cores {
    my $cores = 0;
    
    if (-f "/proc/cpuinfo") {
        my @cpuinfo = read_file("/proc/cpuinfo");
        foreach my $line (@cpuinfo) {
            if ($line =~ /^processor\s*:\s*\d+/) {
                $cores++;
            }
        }
    }
    
    return $cores || 1;
}

sub initialize_process_weights {
    my ($self) = @_;
    
    $self->{process_weights} = {
        'interactive' => {
            'firefox' => 2.5,
            'chrome' => 2.5,
            'code' => 2.0,
            'gnome' => 1.8,
            'kde' => 1.8,
            'xorg' => 1.5,
            'pulseaudio' => 1.3,
        },
        'system' => {
            'systemd' => 1.8,
            'kernel' => 2.0,
            'kworker' => 1.5,
            'migration' => 1.7,
            'rcu' => 1.4,
            'irq' => 1.9,
        },
        'background' => {
            'cron' => 0.8,
            'backup' => 0.5,
            'rsync' => 0.7,
            'updatedb' => 0.6,
        },
        'compute' => {
            'gcc' => 1.2,
            'make' => 1.1,
            'python' => 1.0,
            'perl' => 1.0,
        },
    };
}

sub detect_scheduler {
    my ($self) = @_;
    
    # Detect Linux scheduler type
    if (-f "/sys/kernel/debug/sched_features") {
        my $features = read_file("/sys/kernel/debug/sched_features");
        $self->{scheduler_info}{features} = $features;
    }
    
    # Check for CPU frequency scaling
    if (-d "/sys/devices/system/cpu/cpufreq") {
        $self->{scheduler_info}{freq_scaling} = 1;
        $self->detect_cpu_governors();
    }
}

sub detect_cpu_governors {
    my ($self) = @_;
    
    my @governors;
    for my $cpu (0 .. $self->{cpu_cores} - 1) {
        my $gov_file = "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_governor";
        if (-f $gov_file) {
            my $governor = read_file($gov_file);
            chomp $governor;
            push @governors, $governor;
        }
    }
    
    $self->{scheduler_info}{governors} = \@governors;
}

sub calculate_smart_cpu_usage {
    my ($self) = @_;
    
    # Get raw CPU stats
    my $raw_stats = $self->get_raw_cpu_stats();
    
    # Get process-level information
    my $process_info = $self->get_process_cpu_info();
    
    # Calculate weighted usage
    my $weighted_usage = $self->calculate_weighted_usage($raw_stats, $process_info);
    
    # Apply thermal and frequency corrections
    my $corrected_usage = $self->apply_frequency_corrections($weighted_usage);
    
    # Calculate efficiency metrics
    my $efficiency = $self->calculate_cpu_efficiency($corrected_usage, $process_info);
    
    # Predict future usage trends
    my $prediction = $self->predict_cpu_trend($corrected_usage);
    
    return {
        raw_usage => $raw_stats,
        weighted_usage => $corrected_usage,
        process_breakdown => $process_info,
        efficiency_score => $efficiency,
        prediction => $prediction,
        thermal_state => $self->get_thermal_state(),
        power_state => $self->get_power_state(),
        scheduler_pressure => $self->calculate_scheduler_pressure(),
    };
}

sub get_raw_cpu_stats {
    my ($self) = @_;
    
    return {} unless -f "/proc/stat";
    
    my @stat_lines = read_file("/proc/stat");
    my %cpu_stats;
    
    foreach my $line (@stat_lines) {
        if ($line =~ /^cpu(\d*)\s+(.+)/) {
            my $cpu_id = $1 eq '' ? 'total' : $1;
            my @times = split(/\s+/, $2);
            
            # user, nice, system, idle, iowait, irq, softirq, steal, guest, guest_nice
            $cpu_stats{$cpu_id} = {
                user => $times[0] || 0,
                nice => $times[1] || 0,
                system => $times[2] || 0,
                idle => $times[3] || 0,
                iowait => $times[4] || 0,
                irq => $times[5] || 0,
                softirq => $times[6] || 0,
                steal => $times[7] || 0,
                guest => $times[8] || 0,
                guest_nice => $times[9] || 0,
            };
        }
    }
    
    return \%cpu_stats;
}

sub get_process_cpu_info {
    my ($self) = @_;
    
    my @processes;
    
    # Get detailed process information
    my @ps_output = `ps axo pid,ppid,user,pri,ni,pcpu,pmem,time,comm,cmd --sort=-pcpu 2>/dev/null`;
    shift @ps_output; # Remove header
    
    foreach my $line (@ps_output) {
        chomp $line;
        my @fields = split(/\s+/, $line, 10);
        next unless @fields >= 9;
        
        my $process = {
            pid => $fields[0],
            ppid => $fields[1],
            user => $fields[2],
            priority => $fields[3],
            niceness => $fields[4],
            cpu_percent => $fields[5],
            memory_percent => $fields[6],
            time => $fields[7],
            command => $fields[8],
            full_cmd => $fields[9] || $fields[8],
        };
        
        $process->{weight} = $self->calculate_process_weight($process);
        
        $process->{sched_info} = $self->get_process_scheduler_info($process->{pid});
        
        push @processes, $process;
    }
    
    return \@processes;
}

sub calculate_process_weight {
    my ($self, $process) = @_;
    
    my $base_weight = 1.0;
    my $command = lc($process->{command});
    
    foreach my $category (keys %{$self->{process_weights}}) {
        foreach my $cmd (keys %{$self->{process_weights}{$category}}) {
            if ($command =~ /\Q$cmd\E/) {
                $base_weight = $self->{process_weights}{$category}{$cmd};
                last;
            }
        }
    }
    
    # priority-based adjustments
    my $priority = $process->{priority};
    if ($priority < 0) {
        $base_weight *= 1.5; 
    } elsif ($priority > 20) {
        $base_weight *= 0.7; 
    }
    
    my $niceness = $process->{niceness};
    if ($niceness < 0) {
        $base_weight *= (1.0 + abs($niceness) * 0.1); 
    } elsif ($niceness > 0) {
        $base_weight *= (1.0 - $niceness * 0.05);
    }
    
    if ($process->{user} eq 'root') {
        $base_weight *= 1.3;
    }
    
    return $base_weight;
}

sub get_process_scheduler_info {
    my ($self, $pid) = @_;
    
    my $sched_file = "/proc/$pid/sched";
    return {} unless -f $sched_file;
    
    my %sched_info;
    eval {
        my @sched_data = read_file($sched_file);
        foreach my $line (@sched_data) {
            if ($line =~ /^(\w+)\s*:\s*(.+)/) {
                $sched_info{$1} = $2;
            }
        }
    };
    
    return \%sched_info;
}

sub calculate_weighted_usage {
    my ($self, $raw_stats, $process_info) = @_;
    
    my $total_raw = 0;
    my $total_weighted = 0;
    
    if (exists $raw_stats->{total}) {
        my $stats = $raw_stats->{total};
        my $total_time = sum(values %$stats);
        my $idle_time = $stats->{idle} + $stats->{iowait};
        $total_raw = (($total_time - $idle_time) / $total_time) * 100;
    }
    
    foreach my $process (@$process_info) {
        my $cpu_usage = $process->{cpu_percent};
        my $weight = $process->{weight};
        $total_weighted += $cpu_usage * $weight;
    }
    
    my $max_weighted = $total_raw * 3.0; 
    $total_weighted = min($total_weighted, $max_weighted);
    
    return {
        raw_percent => $total_raw,
        weighted_percent => $total_weighted,
        efficiency_ratio => $total_raw > 0 ? $total_weighted / $total_raw : 1.0,
        core_usage => $self->calculate_per_core_usage($raw_stats),
    };
}

sub calculate_per_core_usage {
    my ($self, $raw_stats) = @_;
    
    my %core_usage;
    
    for my $core (0 .. $self->{cpu_cores} - 1) {
        if (exists $raw_stats->{$core}) {
            my $stats = $raw_stats->{$core};
            my $total_time = sum(values %$stats);
            my $idle_time = $stats->{idle} + $stats->{iowait};
            
            if ($total_time > 0) {
                $core_usage{$core} = (($total_time - $idle_time) / $total_time) * 100;
            } else {
                $core_usage{$core} = 0;
            }
        }
    }
    
    return \%core_usage;
}

sub apply_frequency_corrections {
    my ($self, $usage) = @_;
    
    my $freq_info = $self->get_cpu_frequencies();
    
    my $freq_factor = $freq_info->{scaling_factor} || 1.0;
    
    my $thermal_factor = $self->get_thermal_throttling_factor();
    
    my $corrected_usage = {
        %$usage,
        frequency_corrected => $usage->{weighted_percent} * $freq_factor,
        thermal_corrected => $usage->{weighted_percent} * $thermal_factor,
        final_corrected => $usage->{weighted_percent} * $freq_factor * $thermal_factor,
    };
    
    return $corrected_usage;
}

sub get_cpu_frequencies {
    my ($self) = @_;
    
    my %freq_info;
    my @current_freqs;
    my @max_freqs;
    
    for my $cpu (0 .. $self->{cpu_cores} - 1) {
        my $cur_freq_file = "/sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq";
        my $max_freq_file = "/sys/devices/system/cpu/cpu$cpu/cpufreq/cpuinfo_max_freq";
        
        if (-f $cur_freq_file && -f $max_freq_file) {
            my $cur_freq = read_file($cur_freq_file);
            my $max_freq = read_file($max_freq_file);
            chomp($cur_freq, $max_freq);
            
            push @current_freqs, $cur_freq;
            push @max_freqs, $max_freq;
        }
    }
    
    if (@current_freqs && @max_freqs) {
        my $avg_cur = sum(@current_freqs) / @current_freqs;
        my $avg_max = sum(@max_freqs) / @max_freqs;
        
        $freq_info{scaling_factor} = $avg_cur / $avg_max;
        $freq_info{current_freq} = $avg_cur;
        $freq_info{max_freq} = $avg_max;
    }
    
    return \%freq_info;
}

sub get_thermal_throttling_factor {
    my ($self) = @_;
    
    my $thermal_factor = 1.0;
    
    my $temp = $self->get_cpu_temperature();
    if ($temp > 80) {
        $thermal_factor = 0.9 - (($temp - 80) * 0.01); 
        $thermal_factor = max($thermal_factor, 0.5); 
    }
    
    return $thermal_factor;
}

sub get_cpu_temperature {
    my ($self) = @_;
    
    my $temp = 0;
    
    my @thermal_zones = glob("/sys/class/thermal/thermal_zone*/temp");
    if (@thermal_zones) {
        eval {
            my $thermal_temp = read_file($thermal_zones[0]);
            chomp $thermal_temp;
            $temp = $thermal_temp / 1000;
        };
    }
    
    if ($temp == 0) {
        my @sensors_output = `sensors 2>/dev/null`;
        foreach my $line (@sensors_output) {
            if ($line =~ /Core.*?(\d+\.\d+)°C/) {
                $temp = $1;
                last;
            }
        }
    }
    
    return $temp;
}

sub calculate_cpu_efficiency {
    my ($self, $usage, $process_info) = @_;
    
    my $efficiency_score = 0;
    
    my $productive_usage = 0;
    my $total_usage = 0;
    
    foreach my $process (@$process_info) {
        my $cpu = $process->{cpu_percent};
        $total_usage += $cpu;
        
        if ($process->{weight} > 1.0) {
            $productive_usage += $cpu * $process->{weight};
        }
    }
    
    if ($total_usage > 0) {
        $efficiency_score = ($productive_usage / $total_usage) * 100;
    }
    
    my $core_usage = $usage->{core_usage};
    my @core_values = values %$core_usage;
    my $core_variance = 0;
    
    if (@core_values > 1) {
        my $mean = sum(@core_values) / @core_values;
        my $variance = sum(map { ($_ - $mean) ** 2 } @core_values) / @core_values;
        $core_variance = sqrt($variance);
        
        $efficiency_score *= (1.0 - ($core_variance / 100));
    }
    
    return max(0, min(100, $efficiency_score));
}

sub predict_cpu_trend {
    my ($self, $usage) = @_;
    
    push @{$self->{history}}, {
        timestamp => time(),
        usage => $usage->{final_corrected} || $usage->{weighted_percent},
    };
    
    if (@{$self->{history}} > 20) {
        shift @{$self->{history}};
    }
    
    return {} if @{$self->{history}} < 5;
    
    my @usage_values = map { $_->{usage} } @{$self->{history}};
    my $trend = $self->calculate_linear_trend(\@usage_values);
    
    # Predict next 3 values
    my @predictions;
    for my $i (1..3) {
        my $predicted = $usage_values[-1] + ($trend * $i);
        push @predictions, max(0, min(100, $predicted));
    }
    
    return {
        trend_slope => $trend,
        next_values => \@predictions,
        volatility => $self->calculate_volatility(\@usage_values),
    };
}

sub calculate_linear_trend {
    my ($self, $values) = @_;
    
    return 0 if @$values < 2;
    
    my $n = @$values;
    my $sum_x = $n * ($n - 1) / 2;
    my $sum_y = sum(@$values);
    my $sum_xy = sum(map { $_ * $values->[$_] } 0..$n-1);
    my $sum_x2 = sum(map { $_ * $_ } 0..$n-1);
    
    my $slope = ($n * $sum_xy - $sum_x * $sum_y) / ($n * $sum_x2 - $sum_x * $sum_x);
    
    return $slope;
}

sub calculate_volatility {
    my ($self, $values) = @_;
    
    return 0 if @$values < 2;
    
    my $mean = sum(@$values) / @$values;
    my $variance = sum(map { ($_ - $mean) ** 2 } @$values) / @$values;
    
    return sqrt($variance);
}

sub get_thermal_state {
    my ($self) = @_;
    
    return {
        temperature => $self->get_cpu_temperature(),
        throttling_active => $self->get_thermal_throttling_factor() < 1.0,
    };
}

sub get_power_state {
    my ($self) = @_;
    
    my %power_state;
    
    # Get CPU governor information
    $power_state{governors} = $self->{scheduler_info}{governors} || [];
    
    # Get frequency information
    my $freq_info = $self->get_cpu_frequencies();
    $power_state{frequency} = $freq_info;
    
    return \%power_state;
}

sub calculate_scheduler_pressure {
    my ($self) = @_;
    
    my $pressure = 0;
    
    if (-f "/proc/loadavg") {
        my $loadavg = read_file("/proc/loadavg");
        my ($load1) = split(/\s+/, $loadavg);
        
        $pressure = ($load1 / $self->{cpu_cores}) * 100;
    }
    
    return min(100, $pressure);
}

1;

__END__

=head1 NAME

Symon::SmartCPU - Novel CPU usage calculation with process weighting and efficiency analysis

=head1 SYNOPSIS

    use Symon::SmartCPU;
    
    my $cpu_monitor = Symon::SmartCPU->new(\%config);
    my $usage_data = $cpu_monitor->calculate_smart_cpu_usage();

=head1 DESCRIPTION

This module provides a novel approach to CPU usage calculation that goes beyond traditional user+system metrics. It considers:

- Process priority and scheduling class
- Application type and importance weights
- CPU frequency scaling and thermal throttling
- Scheduler pressure and efficiency metrics
- Predictive trending based on historical data

=head1 METHODS

=head2 new(\%config)

Creates a new SmartCPU instance with optional configuration.

=head2 calculate_smart_cpu_usage()

Returns comprehensive CPU usage data including weighted usage, efficiency scores, and predictions.

=head1 AUTHOR

System Monitor Team

=head1 LICENSE

MIT License

=cut

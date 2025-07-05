package SmartCPU;

use strict;
use warnings;
use POSIX qw(strftime);
use File::Slurp;


sub new {
    my $class = shift;
    my $self = {
        last_measurement => {},
        process_weights => {},
        scheduling_history => [],
        thermal_throttling => 0,
        frequency_scaling => {},
    };
    bless $self, $class;
    return $self;
}

sub get_smart_usage {
    my $self = shift;
    
    my $basic_usage = $self->_get_basic_cpu_usage();
    my $process_analysis = $self->_analyze_process_priority();
    my $scheduling_analysis = $self->_analyze_scheduling_behavior();
    my $thermal_analysis = $self->_analyze_thermal_state();
    my $frequency_analysis = $self->_analyze_frequency_scaling();
    
    my $smart_usage = $self->_calculate_smart_usage(
        $basic_usage,
        $process_analysis,
        $scheduling_analysis,
        $thermal_analysis,
        $frequency_analysis
    );
    
    return {
        basic_usage => $basic_usage,
        smart_usage => $smart_usage,
        process_weight_factor => $process_analysis->{weight_factor},
        scheduling_efficiency => $scheduling_analysis->{efficiency},
        thermal_throttling => $thermal_analysis->{throttling_factor},
        frequency_scaling => $frequency_analysis->{scaling_factor},
        quality_score => $self->_calculate_quality_score($smart_usage),
    };
}

sub _get_basic_cpu_usage {
    my $self = shift;
    
    if (-r "/proc/stat") {
        return $self->_get_linux_cpu_usage();
    } else {
        return $self->_get_macos_cpu_usage();
    }
}

sub _get_linux_cpu_usage {
    my $self = shift;
    
    my @stat_lines = read_file("/proc/stat");
    my $cpu_line = (grep /^cpu\s/, @stat_lines)[0];
    chomp $cpu_line;
    
    my @cpu_times = split(/\s+/, $cpu_line);
    shift @cpu_times; # remove 'cpu' label
    
    my ($user, $nice, $system, $idle, $iowait, $irq, $softirq, $steal) = @cpu_times;
    
    my $total = $user + $nice + $system + $idle + $iowait + $irq + $softirq + ($steal || 0);
    
    return {
        user => sprintf("%.2f", ($user + $nice) / $total * 100),
        system => sprintf("%.2f", ($system + $irq + $softirq) / $total * 100),
        idle => sprintf("%.2f", $idle / $total * 100),
        iowait => sprintf("%.2f", ($iowait || 0) / $total * 100),
        steal => sprintf("%.2f", ($steal || 0) / $total * 100),
        total => sprintf("%.2f", 100 - ($idle / $total * 100)),
    };
}

sub _get_macos_cpu_usage {
    my $self = shift;
    
    my @top_output = `top -l 1 -n 0 2>/dev/null`;
    my ($user, $system, $idle) = (0, 0, 100);
    
    foreach my $line (@top_output) {
        if ($line =~ /CPU usage:\s+(\d+\.\d+)% user, (\d+\.\d+)% sys, (\d+\.\d+)% idle/) {
            ($user, $system, $idle) = ($1, $2, $3);
            last;
        }
    }
    
    return {
        user => $user,
        system => $system,
        idle => $idle,
        iowait => 0,
        steal => 0,
        total => sprintf("%.2f", $user + $system),
    };
}

sub _analyze_process_priority {
    my $self = shift;
    
    my @ps_output = `ps -eo pid,ni,pri,pcpu,comm --sort=-pcpu | head -20 2>/dev/null`;
    shift @ps_output; # Remove header
    
    my $total_weighted_cpu = 0;
    my $total_processes = 0;
    my $high_priority_usage = 0;
    my $real_time_usage = 0;
    
    foreach my $line (@ps_output) {
        chomp $line;
        my ($pid, $nice, $priority, $cpu, $command) = split(/\s+/, $line, 5);
        next unless defined $cpu && $cpu =~ /^\d+\.?\d*$/;
        
        $total_processes++;
        
        my $weight = $self->_calculate_process_weight($nice, $priority, $command);
        $total_weighted_cpu += $cpu * $weight;
        
        if ($priority > 80 || $nice < -10) {
            $high_priority_usage += $cpu;
        }
        
        if ($priority > 99) {
            $real_time_usage += $cpu;
        }
    }
    
    my $weight_factor = $total_processes > 0 ? $total_weighted_cpu / $total_processes : 1.0;
    
    return {
        weight_factor => sprintf("%.2f", $weight_factor),
        high_priority_usage => sprintf("%.2f", $high_priority_usage),
        real_time_usage => sprintf("%.2f", $real_time_usage),
        process_count => $total_processes,
    };
}

sub _calculate_process_weight {
    my ($self, $nice, $priority, $command) = @_;
    
    my $weight = 1.0;
    
    if ($priority > 99) {
        $weight = 3.0;  
    } elsif ($priority > 80) {
        $weight = 2.0;  
    } elsif ($priority < 20) {
        $weight = 0.5; 
    }
    
    if ($nice < -10) {
        $weight *= 1.5;
    } elsif ($nice > 10) {
        $weight *= 0.7;
    }
    
    if ($command && $command =~ /(kernel|kthread|migration|rcu_|watchdog)/) {
        $weight *= 2.0;  # Kernel processes are more important
    } elsif ($command && $command =~ /(chrome|firefox|electron|java)/) {
        $weight *= 1.2;  # Resource-heavy applications
    } elsif ($command && $command =~ /(systemd|init|dbus)/) {
        $weight *= 1.8;  # System processes
    }
    
    return $weight;
}

sub _analyze_scheduling_behavior {
    my $self = shift;
    
    my $efficiency = 100;
    my $context_switches = 0;
    my $interrupts = 0;
    
    if (-r "/proc/stat") {
        my @stat_lines = read_file("/proc/stat");
        foreach my $line (@stat_lines) {
            if ($line =~ /^ctxt (\d+)/) {
                $context_switches = $1;
            } elsif ($line =~ /^intr (\d+)/) {
                $interrupts = $1;
            }
        }
    }
    
    push @{$self->{scheduling_history}}, {
        timestamp => time(),
        context_switches => $context_switches,
        interrupts => $interrupts,
    };
    
    if (@{$self->{scheduling_history}} > 10) {
        shift @{$self->{scheduling_history}};
    }
    
    if (@{$self->{scheduling_history}} > 1) {
        my $recent = $self->{scheduling_history}->[-1];
        my $previous = $self->{scheduling_history}->[-2];
        
        my $time_diff = $recent->{timestamp} - $previous->{timestamp};
        my $ctxt_diff = $recent->{context_switches} - $previous->{context_switches};
        
        if ($time_diff > 0) {
            my $ctxt_rate = $ctxt_diff / $time_diff;
            $efficiency = 100 - ($ctxt_rate / 10000 * 100);
            $efficiency = 0 if $efficiency < 0;
        }
    }
    
    return {
        efficiency => sprintf("%.2f", $efficiency),
        context_switches => $context_switches,
        interrupts => $interrupts,
    };
}

sub _analyze_thermal_state {
    my $self = shift;
    
    my $throttling_factor = 0;
    my $temperature = 0;
    
    if (-r "/sys/class/thermal/thermal_zone0/temp") {
        my $temp_data = read_file("/sys/class/thermal/thermal_zone0/temp");
        chomp $temp_data;
        $temperature = $temp_data / 1000;
    }
    
    if (-r "/sys/devices/system/cpu/cpu0/thermal_throttle/core_throttle_count") {
        my $throttle_data = read_file("/sys/devices/system/cpu/cpu0/thermal_throttle/core_throttle_count");
        chomp $throttle_data;
        $throttling_factor = $throttle_data > 0 ? 1 : 0;
    }
    
    if ($temperature > 85) {
        $throttling_factor = 0.8;
    } elsif ($temperature > 75) {
        $throttling_factor = 0.9;
    } elsif ($temperature > 65) {
        $throttling_factor = 0.95;
    } else {
        $throttling_factor = 1.0;
    }
    
    return {
        throttling_factor => sprintf("%.2f", $throttling_factor),
        temperature => sprintf("%.1f", $temperature),
    };
}

sub _analyze_frequency_scaling {
    my $self = shift;
    
    my $scaling_factor = 1.0;
    my $current_freq = 0;
    my $max_freq = 0;
    
    if (-r "/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq") {
        my $cur_freq_data = read_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq");
        chomp $cur_freq_data;
        $current_freq = $cur_freq_data / 1000; # Convert to MHz
    }
    
    if (-r "/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq") {
        my $max_freq_data = read_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq");
        chomp $max_freq_data;
        $max_freq = $max_freq_data / 1000; # Convert to MHz
    }
    
    if ($max_freq > 0) {
        $scaling_factor = $current_freq / $max_freq;
    }
    
    return {
        scaling_factor => sprintf("%.2f", $scaling_factor),
        current_freq => sprintf("%.0f", $current_freq),
        max_freq => sprintf("%.0f", $max_freq),
    };
}

sub _calculate_smart_usage {
    my ($self, $basic, $process, $scheduling, $thermal, $frequency) = @_;
    
    my $base_usage = $basic->{total};
    
    my $weighted_usage = $base_usage * $process->{weight_factor};
    
    my $efficiency_factor = $scheduling->{efficiency} / 100;
    $weighted_usage *= $efficiency_factor;
    
    $weighted_usage *= $thermal->{throttling_factor};
    
    $weighted_usage *= $frequency->{scaling_factor};
    
    $weighted_usage = 100 if $weighted_usage > 100;
    
    return sprintf("%.2f", $weighted_usage);
}

sub _calculate_quality_score {
    my ($self, $smart_usage) = @_;
    
    my $score = 100;
    
    if ($smart_usage > 90) {
        $score -= 30;
    } elsif ($smart_usage > 70) {
        $score -= 20;
    } elsif ($smart_usage > 50) {
        $score -= 10;
    }
    
    if ($smart_usage < 30) {
        $score += 10;
    }
    
    return sprintf("%.0f", $score);
}

1;

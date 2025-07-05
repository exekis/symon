package SystemMonitor::Display;

use strict;
use warnings;
use POSIX qw(strftime);
use Term::ANSIColor;

sub new {
    my ($class) = @_;
    my $self = {
        show_colors => 1,
        compact_mode => 0,
    };
    
    bless $self, $class;
    return $self;
}

sub set_color_mode {
    my ($self, $enabled) = @_;
    $self->{show_colors} = $enabled;
}

sub set_compact_mode {
    my ($self, $enabled) = @_;
    $self->{compact_mode} = $enabled;
}

sub display_header {
    my ($self, $hostname) = @_;
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    my $header = "=== System Monitor - $hostname ===";
    my $time_str = "[$timestamp]";
    
    if ($self->{show_colors}) {
        print colored($header, 'bold cyan') . "\n";
        print colored($time_str, 'yellow') . "\n";
    } else {
        print "$header\n$time_str\n";
    }
    print "\n";
}

sub display_cpu_stats {
    my ($self, $cpu_stats) = @_;
    
    my $usage = $cpu_stats->{total_usage} || $cpu_stats->{usage_percent} || 0;
    my $temp = $cpu_stats->{temperature} || 0;
    
    my $color = $self->_get_usage_color($usage);
    my $temp_color = $self->_get_temp_color($temp);
    
    if ($self->{compact_mode}) {
        printf "CPU: %s%.1f%%%s", 
            $self->{show_colors} ? colored('', $color) : '',
            $usage,
            $self->{show_colors} ? colored('', 'reset') : '';
        
        if ($temp > 0) {
            printf " | Temp: %s%.1f°C%s",
                $self->{show_colors} ? colored('', $temp_color) : '',
                $temp,
                $self->{show_colors} ? colored('', 'reset') : '';
        }
        print "\n";
    } else {
        print "CPU Statistics:\n";
        printf "  Usage: %s%.1f%%%s\n",
            $self->{show_colors} ? colored('', $color) : '',
            $usage,
            $self->{show_colors} ? colored('', 'reset') : '';
        
        if ($cpu_stats->{user}) {
            printf "  User: %.1f%% | System: %.1f%% | Idle: %.1f%%\n",
                $cpu_stats->{user}, $cpu_stats->{system}, $cpu_stats->{idle};
        }
        
        if ($temp > 0) {
            printf "  Temperature: %s%.1f°C%s\n",
                $self->{show_colors} ? colored('', $temp_color) : '',
                $temp,
                $self->{show_colors} ? colored('', 'reset') : '';
        }
        print "\n";
    }
}

sub display_memory_stats {
    my ($self, $memory_stats) = @_;
    
    my $total = $memory_stats->{total} || 0;
    my $used = $memory_stats->{used} || 0;
    my $available = $memory_stats->{available} || ($total - $used);
    
    my $usage_percent = $total > 0 ? ($used / $total) * 100 : 0;
    my $color = $self->_get_usage_color($usage_percent);
    
    if ($self->{compact_mode}) {
        printf "Memory: %s%.1f%%%s (%s/%s)\n",
            $self->{show_colors} ? colored('', $color) : '',
            $usage_percent,
            $self->{show_colors} ? colored('', 'reset') : '',
            $self->_format_bytes($used),
            $self->_format_bytes($total);
    } else {
        print "Memory Statistics:\n";
        printf "  Total: %s\n", $self->_format_bytes($total);
        printf "  Used: %s%s%s (%.1f%%)\n",
            $self->{show_colors} ? colored('', $color) : '',
            $self->_format_bytes($used),
            $self->{show_colors} ? colored('', 'reset') : '',
            $usage_percent;
        printf "  Available: %s\n", $self->_format_bytes($available);
        print "\n";
    }
}

sub display_system_info {
    my ($self, $system_info) = @_;
    
    return if $self->{compact_mode};
    
    print "System Information:\n";
    printf "  Hostname: %s\n", $system_info->{hostname} || 'Unknown';
    
    if ($system_info->{uptime}) {
        printf "  Uptime: %s\n", $self->_format_uptime($system_info->{uptime});
    }
    
    if ($system_info->{load_avg}) {
        printf "  Load Average: %.2f, %.2f, %.2f\n", 
            @{$system_info->{load_avg}};
    }
    
    print "\n";
}

sub display_alert {
    my ($self, $message, $type) = @_;
    
    my $color = $type eq 'critical' ? 'red' : 
                $type eq 'warning' ? 'yellow' : 'green';
    
    my $prefix = $type eq 'critical' ? '[CRITICAL]' :
                 $type eq 'warning' ? '[WARNING]' : '[INFO]';
    
    if ($self->{show_colors}) {
        print colored("$prefix $message", "bold $color") . "\n";
    } else {
        print "$prefix $message\n";
    }
}

sub clear_screen {
    my ($self) = @_;
    print "\033[2J\033[H";
}

sub _get_usage_color {
    my ($self, $usage) = @_;
    
    return 'reset' unless $self->{show_colors};
    
    return $usage >= 90 ? 'red' :
           $usage >= 70 ? 'yellow' :
           $usage >= 50 ? 'cyan' : 'green';
}

sub _get_temp_color {
    my ($self, $temp) = @_;
    
    return 'reset' unless $self->{show_colors};
    
    return $temp >= 80 ? 'red' :
           $temp >= 65 ? 'yellow' :
           $temp >= 50 ? 'cyan' : 'green';
}

sub _format_bytes {
    my ($self, $bytes) = @_;
    
    my @units = ('B', 'KB', 'MB', 'GB', 'TB');
    my $unit_index = 0;
    my $value = $bytes;
    
    while ($value >= 1024 && $unit_index < $#units) {
        $value /= 1024;
        $unit_index++;
    }
    
    return sprintf("%.1f %s", $value, $units[$unit_index]);
}

sub _format_uptime {
    my ($self, $uptime_seconds) = @_;
    
    my $days = int($uptime_seconds / 86400);
    my $hours = int(($uptime_seconds % 86400) / 3600);
    my $minutes = int(($uptime_seconds % 3600) / 60);
    
    if ($days > 0) {
        return sprintf("%d days, %d hours, %d minutes", $days, $hours, $minutes);
    } elsif ($hours > 0) {
        return sprintf("%d hours, %d minutes", $hours, $minutes);
    } else {
        return sprintf("%d minutes", $minutes);
    }
}

1;

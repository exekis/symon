package SystemMonitor::Logger;

use strict;
use warnings;
use JSON;
use POSIX qw(strftime);
use File::Basename;

sub new {
    my ($class) = @_;
    my $self = {
        log_file => "system_usage_log.json",
        history_file => "system_history.json",
        max_history_entries => 1000,
        enable_file_logging => 1,
        enable_console_logging => 0,
        log_level => 'info',
    };
    
    bless $self, $class;
    $self->_ensure_log_directory();
    return $self;
}

sub set_log_file {
    my ($self, $log_file) = @_;
    $self->{log_file} = $log_file;
    $self->_ensure_log_directory();
}

sub set_history_file {
    my ($self, $history_file) = @_;
    $self->{history_file} = $history_file;
    $self->_ensure_log_directory();
}

sub set_max_history_entries {
    my ($self, $max_entries) = @_;
    $self->{max_history_entries} = $max_entries;
}

sub enable_file_logging {
    my ($self, $enabled) = @_;
    $self->{enable_file_logging} = $enabled;
}

sub enable_console_logging {
    my ($self, $enabled) = @_;
    $self->{enable_console_logging} = $enabled;
}

sub set_log_level {
    my ($self, $level) = @_;
    $self->{log_level} = $level;
}

sub log_system_stats {
    my ($self, $stats) = @_;
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    my $log_entry = {
        timestamp => $timestamp,
        epoch => time(),
        %$stats
    };
    
    $self->_write_to_log($log_entry);
    $self->_update_history($log_entry);
    
    if ($self->{enable_console_logging}) {
        $self->info("System stats logged: CPU: " . ($stats->{cpu}{usage_percent} || 0) . "%, Memory: " . 
                   ($stats->{memory}{total} > 0 ? sprintf("%.1f%%", ($stats->{memory}{used} / $stats->{memory}{total}) * 100) : "0%"));
    }
}

sub log_alert {
    my ($self, $message, $type, $metric, $value, $threshold) = @_;
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    my $alert_entry = {
        timestamp => $timestamp,
        epoch => time(),
        type => $type || 'info',
        message => $message,
        metric => $metric,
        value => $value,
        threshold => $threshold,
    };
    
    $self->_write_to_alert_log($alert_entry);
    
    if ($self->{enable_console_logging}) {
        $self->warn("ALERT: $message");
    }
}

sub info {
    my ($self, $message) = @_;
    $self->_log_message('info', $message);
}

sub warn {
    my ($self, $message) = @_;
    $self->_log_message('warn', $message);
}

sub error {
    my ($self, $message) = @_;
    $self->_log_message('error', $message);
}

sub debug {
    my ($self, $message) = @_;
    $self->_log_message('debug', $message);
}

sub get_recent_history {
    my ($self, $limit) = @_;
    $limit ||= 10;
    
    return [] unless -f $self->{history_file};
    
    eval {
        open my $fh, '<', $self->{history_file} or die "Cannot open history file: $!";
        my $json_text = do { local $/; <$fh> };
        close $fh;
        
        my $history = decode_json($json_text);
        my @sorted_history = sort { $b->{epoch} <=> $a->{epoch} } @$history;
        
        return [@sorted_history[0..($limit-1)]];
    };
    
    if ($@) {
        $self->error("Failed to read history: $@");
        return [];
    }
}

sub get_stats_summary {
    my ($self, $hours) = @_;
    $hours ||= 24;
    
    my $cutoff_time = time() - ($hours * 3600);
    my $all_history = $self->get_recent_history(10000);
    
    my @recent_history = grep { $_->{epoch} >= $cutoff_time } @$all_history;
    
    return {
        total_entries => scalar(@recent_history),
        time_range => $hours,
        avg_cpu_usage => $self->_calculate_average(\@recent_history, 'cpu.usage_percent'),
        max_cpu_usage => $self->_calculate_maximum(\@recent_history, 'cpu.usage_percent'),
        avg_memory_usage => $self->_calculate_average_memory_percent(\@recent_history),
        max_memory_usage => $self->_calculate_maximum_memory_percent(\@recent_history),
    };
}

sub cleanup_old_logs {
    my ($self, $days_to_keep) = @_;
    $days_to_keep ||= 30;
    
    my $cutoff_time = time() - ($days_to_keep * 24 * 3600);
    
    if (-f $self->{history_file}) {
        eval {
            my $history = $self->get_recent_history(10000);
            my @recent_history = grep { $_->{epoch} >= $cutoff_time } @$history;
            
            open my $fh, '>', $self->{history_file} or die "Cannot write to history file: $!";
            print $fh encode_json(\@recent_history);
            close $fh;
            
            $self->info("Cleaned up old history entries, kept " . scalar(@recent_history) . " entries");
        };
        
        if ($@) {
            $self->error("Failed to cleanup history: $@");
        }
    }
}

sub _write_to_log {
    my ($self, $entry) = @_;
    
    return unless $self->{enable_file_logging};
    
    eval {
        open my $fh, '>>', $self->{log_file} or die "Cannot open log file: $!";
        print $fh encode_json($entry) . "\n";
        close $fh;
    };
    
    if ($@) {
        warn "Failed to write to log file: $@";
    }
}

sub _write_to_alert_log {
    my ($self, $entry) = @_;
    
    return unless $self->{enable_file_logging};
    
    my $alert_log = $self->{log_file};
    $alert_log =~ s/\.json$/_alerts.json/;
    
    eval {
        open my $fh, '>>', $alert_log or die "Cannot open alert log file: $!";
        print $fh encode_json($entry) . "\n";
        close $fh;
    };
    
    if ($@) {
        warn "Failed to write to alert log file: $@";
    }
}

sub _update_history {
    my ($self, $entry) = @_;
    
    return unless $self->{enable_file_logging};
    
    my $history = [];
    
    if (-f $self->{history_file}) {
        eval {
            open my $fh, '<', $self->{history_file} or die "Cannot open history file: $!";
            my $json_text = do { local $/; <$fh> };
            close $fh;
            
            $history = decode_json($json_text);
        };
    }
    
    push @$history, $entry;
    
    if (@$history > $self->{max_history_entries}) {
        @$history = sort { $b->{epoch} <=> $a->{epoch} } @$history;
        @$history = @$history[0..($self->{max_history_entries}-1)];
    }
    
    eval {
        open my $fh, '>', $self->{history_file} or die "Cannot write to history file: $!";
        print $fh encode_json($history);
        close $fh;
    };
    
    if ($@) {
        warn "Failed to update history file: $@";
    }
}

sub _log_message {
    my ($self, $level, $message) = @_;
    
    my %level_priority = (
        debug => 0,
        info => 1,
        warn => 2,
        error => 3,
    );
    
    my $current_priority = $level_priority{$self->{log_level}} || 1;
    my $message_priority = $level_priority{$level} || 1;
    
    return if $message_priority < $current_priority;
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    my $log_line = "[$timestamp] [" . uc($level) . "] $message";
    
    if ($self->{enable_console_logging}) {
        print "$log_line\n";
    }
    
    if ($self->{enable_file_logging}) {
        my $debug_log = $self->{log_file};
        $debug_log =~ s/\.json$/_debug.log/;
        
        eval {
            open my $fh, '>>', $debug_log or die "Cannot open debug log file: $!";
            print $fh "$log_line\n";
            close $fh;
        };
    }
}

sub _ensure_log_directory {
    my ($self) = @_;
    
    for my $file ($self->{log_file}, $self->{history_file}) {
        my $dir = dirname($file);
        if ($dir && $dir ne '.' && !-d $dir) {
            eval {
                require File::Path;
                File::Path::make_path($dir);
            };
            
            if ($@) {
                warn "Failed to create log directory '$dir': $@";
            }
        }
    }
}

sub _calculate_average {
    my ($self, $history, $field) = @_;
    
    return 0 unless @$history;
    
    my $sum = 0;
    my $count = 0;
    
    for my $entry (@$history) {
        my $value = $self->_get_nested_value($entry, $field);
        if (defined $value && $value =~ /^\d+\.?\d*$/) {
            $sum += $value;
            $count++;
        }
    }
    
    return $count > 0 ? $sum / $count : 0;
}

sub _calculate_maximum {
    my ($self, $history, $field) = @_;
    
    return 0 unless @$history;
    
    my $max = 0;
    
    for my $entry (@$history) {
        my $value = $self->_get_nested_value($entry, $field);
        if (defined $value && $value =~ /^\d+\.?\d*$/) {
            $max = $value if $value > $max;
        }
    }
    
    return $max;
}

sub _calculate_average_memory_percent {
    my ($self, $history) = @_;
    
    return 0 unless @$history;
    
    my $sum = 0;
    my $count = 0;
    
    for my $entry (@$history) {
        my $total = $self->_get_nested_value($entry, 'memory.total');
        my $used = $self->_get_nested_value($entry, 'memory.used');
        
        if (defined $total && defined $used && $total > 0) {
            $sum += ($used / $total) * 100;
            $count++;
        }
    }
    
    return $count > 0 ? $sum / $count : 0;
}

sub _calculate_maximum_memory_percent {
    my ($self, $history) = @_;
    
    return 0 unless @$history;
    
    my $max = 0;
    
    for my $entry (@$history) {
        my $total = $self->_get_nested_value($entry, 'memory.total');
        my $used = $self->_get_nested_value($entry, 'memory.used');
        
        if (defined $total && defined $used && $total > 0) {
            my $percent = ($used / $total) * 100;
            $max = $percent if $percent > $max;
        }
    }
    
    return $max;
}

sub _get_nested_value {
    my ($self, $data, $path) = @_;
    
    my @keys = split /\./, $path;
    my $current = $data;
    
    for my $key (@keys) {
        return undef unless ref $current eq 'HASH';
        $current = $current->{$key};
    }
    
    return $current;
}

1;

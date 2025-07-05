#!/usr/bin/perl

package Symon::SmartMemory;

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
        pressure_history => [],
        swap_history => [],
        cache_stats => {},
        memory_zones => {},
        numa_info => {},
        hugepage_info => {},
        compression_ratio => 1.0,
    };
    
    bless $self, $class;
    $self->initialize_memory_zones();
    $self->detect_numa_topology();
    $self->analyze_hugepages();
    return $self;
}

sub initialize_memory_zones {
    my ($self) = @_;
    
    # memory zones information
    if (-f "/proc/zoneinfo") {
        my @zoneinfo = read_file("/proc/zoneinfo");
        my $current_zone;
        
        foreach my $line (@zoneinfo) {
            chomp $line;
            if ($line =~ /^Node\s+(\d+),\s+zone\s+(\w+)/) {
                $current_zone = "$1_$2";
                $self->{memory_zones}{$current_zone} = {};
            } elsif ($line =~ /^\s+(\w+)\s+(\d+)/ && $current_zone) {
                $self->{memory_zones}{$current_zone}{$1} = $2;
            }
        }
    }
}

sub detect_numa_topology {
    my ($self) = @_;
    
    # NUMA 
    if (-d "/sys/devices/system/node") {
        my @nodes = glob("/sys/devices/system/node/node*");
        foreach my $node (@nodes) {
            next unless -d $node;
            
            my $node_id = $node =~ /node(\d+)$/ ? $1 : 0;
            
            # Get memory info for this node
            my $meminfo_file = "$node/meminfo";
            if (-f $meminfo_file) {
                my @meminfo = read_file($meminfo_file);
                foreach my $line (@meminfo) {
                    if ($line =~ /^Node\s+\d+\s+(\w+):\s+(\d+)\s+kB/) {
                        $self->{numa_info}{$node_id}{$1} = $2 * 1024; # Convert to bytes
                    }
                }
            }
        }
    }
}

sub analyze_hugepages {
    my ($self) = @_;
    
    # hugepage 
    if (-f "/proc/meminfo") {
        my @meminfo = read_file("/proc/meminfo");
        foreach my $line (@meminfo) {
            if ($line =~ /^(HugePages_\w+):\s+(\d+)/) {
                $self->{hugepage_info}{$1} = $2;
            } elsif ($line =~ /^Hugepagesize:\s+(\d+)\s+kB/) {
                $self->{hugepage_info}{size} = $1 * 1024;
            }
        }
    }
}

sub calculate_memory_pressure {
    my ($self) = @_;
    
    # raw memory
    my $raw_stats = $self->get_raw_memory_stats();
    
    # pressure metrics
    my $pressure_score = $self->calculate_pressure_score($raw_stats);
    my $swap_pressure = $self->calculate_swap_pressure($raw_stats);
    my $cache_pressure = $self->calculate_cache_pressure($raw_stats);
    my $fragmentation = $self->calculate_fragmentation();
    
    # allocation patterns
    my $allocation_patterns = $self->analyze_allocation_patterns();
    
    # future memory usage prediction
    my $prediction = $self->predict_memory_pressure($pressure_score);
    
    # efficiency metrics
    my $efficiency = $self->calculate_memory_efficiency($raw_stats);
    
    return {
        raw_stats => $raw_stats,
        pressure_score => $pressure_score,
        swap_pressure => $swap_pressure,
        cache_pressure => $cache_pressure,
        fragmentation => $fragmentation,
        allocation_patterns => $allocation_patterns,
        prediction => $prediction,
        efficiency => $efficiency,
        numa_balance => $self->calculate_numa_balance(),
        compression_stats => $self->get_compression_stats(),
        oom_risk => $self->calculate_oom_risk($raw_stats),
    };
}

sub get_raw_memory_stats {
    my ($self) = @_;
    
    my %stats;
    
    # mem information
    if (-f "/proc/meminfo") {
        my @meminfo = read_file("/proc/meminfo");
        foreach my $line (@meminfo) {
            if ($line =~ /^(\w+):\s+(\d+)(?:\s+kB)?/) {
                $stats{$1} = $2 * 1024; # Convert to bytes
            }
        }
    }
    
    # virtual memory
    if (-f "/proc/vmstat") {
        my @vmstat = read_file("/proc/vmstat");
        foreach my $line (@vmstat) {
            if ($line =~ /^(\w+)\s+(\d+)/) {
                $stats{"vm_$1"} = $2;
            }
        }
    }
    
    # memory pressure information
    if (-f "/proc/pressure/memory") {
        my @pressure = read_file("/proc/pressure/memory");
        foreach my $line (@pressure) {
            if ($line =~ /^(\w+)\s+avg10=(\d+\.\d+)\s+avg60=(\d+\.\d+)\s+avg300=(\d+\.\d+)\s+total=(\d+)/) {
                $stats{"pressure_$1"} = {
                    avg10 => $2,
                    avg60 => $3,
                    avg300 => $4,
                    total => $5,
                };
            }
        }
    }
    
    return \%stats;
}

sub calculate_pressure_score {
    my ($self, $stats) = @_;
    
    my $pressure_score = 0;
    
    my $total = $stats->{MemTotal} || 1;
    my $available = $stats->{MemAvailable} || $stats->{MemFree} || 0;
    my $used = $total - $available;
    my $basic_pressure = ($used / $total) * 100;
    
    my $swap_total = $stats->{SwapTotal} || 0;
    my $swap_used = $swap_total - ($stats->{SwapFree} || 0);
    my $swap_pressure = 0;
    if ($swap_total > 0) {
        $swap_pressure = ($swap_used / $swap_total) * 100;
    }
    
    my $page_faults = $stats->{vm_pgfault} || 0;
    my $major_faults = $stats->{vm_pgmajfault} || 0;
    my $fault_pressure = 0;
    if ($page_faults > 0) {
        $fault_pressure = ($major_faults / $page_faults) * 100;
    }
    
    my $cache_size = ($stats->{Cached} || 0) + ($stats->{Buffers} || 0);
    my $cache_pressure = 0;
    if ($cache_size > 0) {
        my $cache_ratio = $cache_size / $total;
        if ($cache_ratio < 0.05) { # 5% cache indicates pressure
            $cache_pressure = (0.05 - $cache_ratio) * 2000; # 0-100
        }
    }
    
    my $slab = $stats->{Slab} || 0;
    my $kernel_pressure = ($slab / $total) * 100;
    if ($kernel_pressure > 10) { # +10% kernel usage indicates pressure
        $kernel_pressure = ($kernel_pressure - 10) * 2;
    } else {
        $kernel_pressure = 0;
    }
    
    my $system_pressure = 0;
    if (exists $stats->{pressure_some}) {
        $system_pressure = $stats->{pressure_some}{avg60} || 0;
    }
    
    $pressure_score = (
        $basic_pressure * 0.4 +
        $swap_pressure * 0.2 +
        $fault_pressure * 0.15 +
        $cache_pressure * 0.1 +
        $kernel_pressure * 0.1 +
        $system_pressure * 0.05
    );
    
    return min(100, max(0, $pressure_score));
}

sub calculate_swap_pressure {
    my ($self, $stats) = @_;
    
    my %swap_pressure;
    
    my $swap_total = $stats->{SwapTotal} || 0;
    my $swap_used = $swap_total - ($stats->{SwapFree} || 0);
    
    $swap_pressure{usage_percent} = $swap_total > 0 ? ($swap_used / $swap_total) * 100 : 0;
    
    my $swap_in = $stats->{vm_pswpin} || 0;
    my $swap_out = $stats->{vm_pswpout} || 0;
    
    push @{$self->{swap_history}}, {
        timestamp => time(),
        swap_in => $swap_in,
        swap_out => $swap_out,
        swap_used => $swap_used,
    };
    
    if (@{$self->{swap_history}} > 10) {
        shift @{$self->{swap_history}};
    }
    
    if (@{$self->{swap_history}} >= 2) {
        my $recent = $self->{swap_history}[-1];
        my $previous = $self->{swap_history}[-2];
        
        my $time_diff = $recent->{timestamp} - $previous->{timestamp};
        if ($time_diff > 0) {
            $swap_pressure{in_rate} = ($recent->{swap_in} - $previous->{swap_in}) / $time_diff;
            $swap_pressure{out_rate} = ($recent->{swap_out} - $previous->{swap_out}) / $time_diff;
        }
    }
    
    my $swap_cached = $stats->{SwapCached} || 0;
    $swap_pressure{cache_efficiency} = $swap_used > 0 ? ($swap_cached / $swap_used) * 100 : 0;
    
    if ($swap_pressure{out_rate} && $swap_pressure{out_rate} > 0) {
        my $swap_free = $stats->{SwapFree} || 0;
        $swap_pressure{exhaustion_eta} = $swap_free / $swap_pressure{out_rate}; # seconds
    }
    
    return \%swap_pressure;
}

sub calculate_cache_pressure {
    my ($self, $stats) = @_;
    
    my %cache_pressure;
    
    my $page_cache = $stats->{Cached} || 0;
    my $buffer_cache = $stats->{Buffers} || 0;
    my $slab_cache = $stats->{Slab} || 0;
    
    my $total_cache = $page_cache + $buffer_cache + $slab_cache;
    my $total_memory = $stats->{MemTotal} || 1;
    
    $cache_pressure{total_cache_percent} = ($total_cache / $total_memory) * 100;
    $cache_pressure{page_cache_percent} = ($page_cache / $total_memory) * 100;
    $cache_pressure{buffer_cache_percent} = ($buffer_cache / $total_memory) * 100;
    $cache_pressure{slab_cache_percent} = ($slab_cache / $total_memory) * 100;
    
    my $page_faults = $stats->{vm_pgfault} || 0;
    my $major_faults = $stats->{vm_pgmajfault} || 0;
    my $minor_faults = $page_faults - $major_faults;
    
    if ($page_faults > 0) {
        $cache_pressure{cache_hit_rate} = ($minor_faults / $page_faults) * 100;
    }
    
    my $direct_reclaim = $stats->{vm_allocstall_dma} || 0;
    $direct_reclaim += $stats->{vm_allocstall_dma32} || 0;
    $direct_reclaim += $stats->{vm_allocstall_normal} || 0;
    $direct_reclaim += $stats->{vm_allocstall_movable} || 0;
    
    $cache_pressure{reclaim_pressure} = $direct_reclaim;
    
    my $dirty_pages = $stats->{Dirty} || 0;
    my $writeback_pages = $stats->{Writeback} || 0;
    my $dirty_ratio = $page_cache > 0 ? (($dirty_pages + $writeback_pages) / $page_cache) * 100 : 0;
    
    $cache_pressure{efficiency_score} = max(0, 100 - $dirty_ratio);
    
    return \%cache_pressure;
}

sub calculate_fragmentation {
    my ($self) = @_;
    
    my %fragmentation;
    
    # buddyinfo 
    if (-f "/proc/buddyinfo") {
        my @buddyinfo = read_file("/proc/buddyinfo");
        my @total_free_pages = (0) x 11; # 11 orders (0-10)
        
        foreach my $line (@buddyinfo) {
            if ($line =~ /^Node\s+\d+,\s+zone\s+\w+\s+(.+)/) {
                my @free_pages = split(/\s+/, $1);
                for my $order (0..$#free_pages) {
                    $total_free_pages[$order] += $free_pages[$order] || 0;
                }
            }
        }
        
        my $total_free = sum(@total_free_pages);
        my $large_pages = sum(@total_free_pages[3..10]); 
        
        if ($total_free > 0) {
            $fragmentation{fragmentation_index} = (1 - ($large_pages / $total_free)) * 100;
        }
        
        $fragmentation{free_pages_by_order} = \@total_free_pages;
    }
    
    my $hugepages_total = $self->{hugepage_info}{HugePages_Total} || 0;
    my $hugepages_free = $self->{hugepage_info}{HugePages_Free} || 0;
    
    if ($hugepages_total > 0) {
        $fragmentation{hugepage_availability} = ($hugepages_free / $hugepages_total) * 100;
    }
    
    return \%fragmentation;
}

sub analyze_allocation_patterns {
    my ($self) = @_;
    
    my %patterns;
    
    # /proc/vmstat
    if (-f "/proc/vmstat") {
        my @vmstat = read_file("/proc/vmstat");
        my %vmstat_data;
        
        foreach my $line (@vmstat) {
            if ($line =~ /^(\w+)\s+(\d+)/) {
                $vmstat_data{$1} = $2;
            }
        }
        
        my $alloc_success = $vmstat_data{pgalloc_normal} || 0;
        my $alloc_fail = $vmstat_data{pgalloc_fail} || 0;
        
        if ($alloc_success + $alloc_fail > 0) {
            $patterns{allocation_success_rate} = ($alloc_success / ($alloc_success + $alloc_fail)) * 100;
        }
        
        $patterns{compaction_events} = $vmstat_data{compact_migrate_scanned} || 0;
        $patterns{compaction_success} = $vmstat_data{compact_success} || 0;
        
        # NUMA 
        $patterns{numa_hit} = $vmstat_data{numa_hit} || 0;
        $patterns{numa_miss} = $vmstat_data{numa_miss} || 0;
        $patterns{numa_foreign} = $vmstat_data{numa_foreign} || 0;
        
        if ($patterns{numa_hit} + $patterns{numa_miss} > 0) {
            $patterns{numa_locality} = ($patterns{numa_hit} / ($patterns{numa_hit} + $patterns{numa_miss})) * 100;
        }
    }
    
    return \%patterns;
}

sub predict_memory_pressure {
    my ($self, $current_pressure) = @_;
    
    push @{$self->{pressure_history}}, {
        timestamp => time(),
        pressure => $current_pressure,
    };
    
    if (@{$self->{pressure_history}} > 30) {
        shift @{$self->{pressure_history}};
    }
    
    return {} if @{$self->{pressure_history}} < 5;
    
    my @pressure_values = map { $_->{pressure} } @{$self->{pressure_history}};
    my $trend = $self->calculate_linear_trend(\@pressure_values);
    
    my @predictions;
    for my $i (1..5) {
        my $predicted = $pressure_values[-1] + ($trend * $i);
        push @predictions, max(0, min(100, $predicted));
    }
    
    my $acceleration = 0;
    if (@pressure_values >= 3) {
        my $recent_trend = $pressure_values[-1] - $pressure_values[-2];
        my $previous_trend = $pressure_values[-2] - $pressure_values[-3];
        $acceleration = $recent_trend - $previous_trend;
    }
    
    my $time_to_critical = 0;
    if ($trend > 0 && $current_pressure < 90) {
        $time_to_critical = (90 - $current_pressure) / $trend;
    }
    
    return {
        trend => $trend,
        acceleration => $acceleration,
        predictions => \@predictions,
        time_to_critical => $time_to_critical,
        volatility => $self->calculate_volatility(\@pressure_values),
    };
}

sub calculate_memory_efficiency {
    my ($self, $stats) = @_;
    
    my %efficiency;
    
    my $cache_size = ($stats->{Cached} || 0) + ($stats->{Buffers} || 0);
    my $total_memory = $stats->{MemTotal} || 1;
    my $cache_ratio = $cache_size / $total_memory;
    
    if ($cache_ratio >= 0.1 && $cache_ratio <= 0.3) {
        $efficiency{cache_efficiency} = 100;
    } elsif ($cache_ratio < 0.1) {
        $efficiency{cache_efficiency} = ($cache_ratio / 0.1) * 100;
    } else {
        $efficiency{cache_efficiency} = max(0, 100 - (($cache_ratio - 0.3) * 200));
    }
    
    my $available = $stats->{MemAvailable} || 0;
    my $utilization = (($total_memory - $available) / $total_memory) * 100;
    
    if ($utilization >= 70 && $utilization <= 85) {
        $efficiency{utilization_efficiency} = 100;
    } elsif ($utilization < 70) {
        $efficiency{utilization_efficiency} = ($utilization / 70) * 100;
    } else {
        $efficiency{utilization_efficiency} = max(0, 100 - (($utilization - 85) * 3));
    }
    
    my $swap_total = $stats->{SwapTotal} || 0;
    if ($swap_total > 0) {
        my $swap_used = $swap_total - ($stats->{SwapFree} || 0);
        my $swap_utilization = ($swap_used / $swap_total) * 100;
        
        $efficiency{swap_efficiency} = max(0, 100 - $swap_utilization);
    } else {
        $efficiency{swap_efficiency} = 100; # No swap = perfect efficiency
    }
    
    $efficiency{overall_score} = (
        $efficiency{cache_efficiency} * 0.4 +
        $efficiency{utilization_efficiency} * 0.4 +
        $efficiency{swap_efficiency} * 0.2
    );
    
    return \%efficiency;
}

sub calculate_numa_balance {
    my ($self) = @_;
    
    return {} unless keys %{$self->{numa_info}};
    
    my %numa_balance;
    my @node_usage;
    
    foreach my $node_id (keys %{$self->{numa_info}}) {
        my $node_info = $self->{numa_info}{$node_id};
        my $total = $node_info->{MemTotal} || 1;
        my $free = $node_info->{MemFree} || 0;
        my $used = $total - $free;
        
        push @node_usage, ($used / $total) * 100;
    }
    
    if (@node_usage > 1) {
        my $mean = sum(@node_usage) / @node_usage;
        my $variance = sum(map { ($_ - $mean) ** 2 } @node_usage) / @node_usage;
        
        $numa_balance{usage_variance} = $variance;
        $numa_balance{balance_score} = max(0, 100 - $variance); 
        $numa_balance{node_usage} = \@node_usage;
    }
    
    return \%numa_balance;
}

sub get_compression_stats {
    my ($self) = @_;
    
    my %compression;
    
    if (-f "/sys/module/zswap/parameters/enabled") {
        my $enabled = read_file("/sys/module/zswap/parameters/enabled");
        chomp $enabled;
        $compression{zswap_enabled} = $enabled eq 'Y' ? 1 : 0;
    }
    
    my @zram_devices = glob("/sys/block/zram*");
    $compression{zram_devices} = scalar(@zram_devices);
    
    if (@zram_devices) {
        my $total_compressed = 0;
        my $total_original = 0;
        
        foreach my $device (@zram_devices) {
            my $comp_file = "$device/compr_data_size";
            my $orig_file = "$device/orig_data_size";
            
            if (-f $comp_file && -f $orig_file) {
                my $compressed = read_file($comp_file);
                my $original = read_file($orig_file);
                chomp($compressed, $original);
                
                $total_compressed += $compressed;
                $total_original += $original;
            }
        }
        
        if ($total_original > 0) {
            $compression{compression_ratio} = $total_original / $total_compressed;
            $compression{space_saved} = $total_original - $total_compressed;
        }
    }
    
    return \%compression;
}

sub calculate_oom_risk {
    my ($self, $stats) = @_;
    
    my $oom_risk = 0;
    
    my $available = $stats->{MemAvailable} || 0;
    my $total = $stats->{MemTotal} || 1;
    my $available_percent = ($available / $total) * 100;
    
    if ($available_percent < 5) {
        $oom_risk += 50;
    } elsif ($available_percent < 10) {
        $oom_risk += 30;
    } elsif ($available_percent < 20) {
        $oom_risk += 10;
    }
    
    my $swap_total = $stats->{SwapTotal} || 0;
    if ($swap_total > 0) {
        my $swap_used = $swap_total - ($stats->{SwapFree} || 0);
        my $swap_percent = ($swap_used / $swap_total) * 100;
        
        if ($swap_percent > 90) {
            $oom_risk += 30;
        } elsif ($swap_percent > 70) {
            $oom_risk += 20;
        } elsif ($swap_percent > 50) {
            $oom_risk += 10;
        }
    } else {
        $oom_risk += 10;
    }
    
    if (exists $stats->{pressure_full}) {
        my $pressure = $stats->{pressure_full}{avg60} || 0;
        $oom_risk += $pressure * 0.2;
    }
    
    my $slab = $stats->{Slab} || 0;
    my $slab_percent = ($slab / $total) * 100;
    if ($slab_percent > 15) {
        $oom_risk += 10;
    }
    
    return min(100, $oom_risk);
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

1;

__END__

=head1 NAME

Symon::SmartMemory - Novel memory pressure calculation with swap prediction and efficiency analysis

=head1 SYNOPSIS

    use Symon::SmartMemory;
    
    my $memory_monitor = Symon::SmartMemory->new(\%config);
    my $pressure_data = $memory_monitor->calculate_memory_pressure();

=head1 DESCRIPTION

This module provides advanced memory pressure calculation that goes beyond traditional used/free metrics. It considers:

- Memory pressure from multiple sources (cache, swap, fragmentation)
- NUMA topology and memory locality
- Swap behavior prediction and efficiency
- Memory fragmentation analysis
- OOM (Out of Memory) risk assessment
- Memory compression statistics

=head1 METHODS

=head2 new(\%config)

Creates a new SmartMemory instance with optional configuration.

=head2 calculate_memory_pressure()

Returns comprehensive memory pressure data including efficiency scores, predictions, and risk assessments.

=head1 AUTHOR

System Monitor Team

=head1 LICENSE

MIT License

=cut

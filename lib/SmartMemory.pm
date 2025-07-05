package SmartMemory;

use strict;
use warnings;
use POSIX qw(strftime);
use File::Slurp;

# approach = analyze memory pressure considering fragmentation + cache efficiency + NUMA topology

sub new {
    my $class = shift;
    my $self = {
        history => [],
        fragmentation_data => {},
        numa_topology => {},
        cache_efficiency => {},
        pressure_trends => [],
    };
    bless $self, $class;
    return $self;
}

sub get_pressure_analysis {
    my $self = shift;
    
    my $basic_memory = $self->_get_basic_memory_info();
    my $pressure_metrics = $self->_analyze_memory_pressure();
    my $fragmentation = $self->_analyze_fragmentation();
    my $cache_analysis = $self->_analyze_cache_efficiency();
    my $numa_analysis = $self->_analyze_numa_topology();
    my $oom_risk = $self->_calculate_oom_risk();
    
    my $pressure_score = $self->_calculate_pressure_score(
        $basic_memory,
        $pressure_metrics,
        $fragmentation,
        $cache_analysis,
        $numa_analysis
    );
    
    return {
        basic_memory => $basic_memory,
        pressure_score => $pressure_score,
        fragmentation_index => $fragmentation->{index},
        cache_efficiency => $cache_analysis->{efficiency},
        numa_balance => $numa_analysis->{balance_score},
        oom_risk => $oom_risk,
        quality_score => $self->_calculate_quality_score($pressure_score),
        trend_direction => $self->_calculate_trend_direction(),
    };
}

sub _get_basic_memory_info {
    my $self = shift;
    
    if (-r "/proc/meminfo") {
        return $self->_get_linux_memory_info();
    } else {
        return $self->_get_macos_memory_info();
    }
}

sub _get_linux_memory_info {
    my $self = shift;
    
    my @meminfo_lines = read_file("/proc/meminfo");
    my %mem_data;
    
    foreach my $line (@meminfo_lines) {
        if ($line =~ /^(\w+):\s+(\d+)\s+kB/) {
            $mem_data{$1} = $2 * 1024; # Convert to bytes
        }
    }
    
    my $total = $mem_data{MemTotal} || 0;
    my $free = $mem_data{MemFree} || 0;
    my $available = $mem_data{MemAvailable} || $free;
    my $buffers = $mem_data{Buffers} || 0;
    my $cached = $mem_data{Cached} || 0;
    my $slab = $mem_data{Slab} || 0;
    my $swap_total = $mem_data{SwapTotal} || 0;
    my $swap_free = $mem_data{SwapFree} || 0;
    my $dirty = $mem_data{Dirty} || 0;
    my $writeback = $mem_data{Writeback} || 0;
    
    my $used = $total - $available;
    my $swap_used = $swap_total - $swap_free;
    
    return {
        total => $total,
        used => $used,
        free => $free,
        available => $available,
        buffers => $buffers,
        cached => $cached,
        slab => $slab,
        swap_total => $swap_total,
        swap_used => $swap_used,
        dirty => $dirty,
        writeback => $writeback,
        percent_used => sprintf("%.2f", ($used / $total) * 100),
        swap_percent => sprintf("%.2f", $swap_total > 0 ? ($swap_used / $swap_total) * 100 : 0),
    };
}

sub _get_macos_memory_info {
    my $self = shift;
    
    my @vm_stat_output = `vm_stat 2>/dev/null`;
    my %memory;
    
    foreach my $line (@vm_stat_output) {
        if ($line =~ /^Pages free:\s+(\d+)\./) {
            $memory{free} = $1 * 4096;
        } elsif ($line =~ /^Pages active:\s+(\d+)\./) {
            $memory{active} = $1 * 4096;
        } elsif ($line =~ /^Pages inactive:\s+(\d+)\./) {
            $memory{inactive} = $1 * 4096;
        } elsif ($line =~ /^Pages wired down:\s+(\d+)\./) {
            $memory{wired} = $1 * 4096;
        } elsif ($line =~ /^Pages purgeable:\s+(\d+)\./) {
            $memory{purgeable} = $1 * 4096;
        }
    }
    
    my $used = $memory{active} + $memory{inactive} + $memory{wired};
    my $total = $used + $memory{free};
    
    return {
        total => $total,
        used => $used,
        free => $memory{free},
        available => $memory{free} + $memory{purgeable},
        buffers => 0,
        cached => 0,
        slab => 0,
        swap_total => 0,
        swap_used => 0,
        dirty => 0,
        writeback => 0,
        percent_used => sprintf("%.2f", ($used / $total) * 100),
        swap_percent => 0,
    };
}

sub _analyze_memory_pressure {
    my $self = shift;
    
    my %pressure;
    
    if (-r "/proc/pressure/memory") {
        my @pressure_lines = read_file("/proc/pressure/memory");
        foreach my $line (@pressure_lines) {
            if ($line =~ /^some avg10=(\d+\.\d+) avg60=(\d+\.\d+) avg300=(\d+\.\d+)/) {
                $pressure{some} = { avg10 => $1, avg60 => $2, avg300 => $3 };
            } elsif ($line =~ /^full avg10=(\d+\.\d+) avg60=(\d+\.\d+) avg300=(\d+\.\d+)/) {
                $pressure{full} = { avg10 => $1, avg60 => $2, avg300 => $3 };
            }
        }
    }
    
    if (-r "/proc/vmstat") {
        my @vmstat_lines = read_file("/proc/vmstat");
        my %vmstat;
        
        foreach my $line (@vmstat_lines) {
            if ($line =~ /^(\w+)\s+(\d+)/) {
                $vmstat{$1} = $2;
            }
        }
        
        $pressure{page_faults} = $vmstat{pgfault} || 0;
        $pressure{page_major_faults} = $vmstat{pgmajfault} || 0;
        $pressure{page_alloc_failures} = $vmstat{pgalloc_fail} || 0;
        $pressure{compaction_events} = $vmstat{compact_migrate_scanned} || 0;
        $pressure{kswapd_efficiency} = $vmstat{kswapd_inodesteal} || 0;
    }
    
    return \%pressure;
}

sub _analyze_fragmentation {
    my $self = shift;
    
    my $fragmentation_index = 0;
    my %fragmentation_data;
    
    if (-r "/proc/buddyinfo") {
        my @buddy_lines = read_file("/proc/buddyinfo");
        
        foreach my $line (@buddy_lines) {
            if ($line =~ /^Node\s+(\d+).*?(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$/) {
                my $node = $1;
                my @orders = ($2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12);
                
                my $total_free = 0;
                my $weighted_fragmentation = 0;
                
                for my $order (0..$#orders) {
                    my $free_blocks = $orders[$order];
                    my $block_size = 4096 * (2 ** $order);
                    $total_free += $free_blocks * $block_size;
                    $weighted_fragmentation += $free_blocks * $order;
                }
                
                $fragmentation_data{$node} = {
                    total_free => $total_free,
                    fragmentation_score => $weighted_fragmentation,
                    orders => \@orders,
                };
            }
        }
        
        my $total_score = 0;
        my $node_count = 0;
        
        foreach my $node (keys %fragmentation_data) {
            $total_score += $fragmentation_data{$node}{fragmentation_score};
            $node_count++;
        }
        
        $fragmentation_index = $node_count > 0 ? $total_score / $node_count : 0;
    }
    
    return {
        index => sprintf("%.2f", $fragmentation_index),
        nodes => \%fragmentation_data,
    };
}

sub _analyze_cache_efficiency {
    my $self = shift;
    
    my $efficiency = 100;
    my %cache_data;
    
    if (-r "/proc/vmstat") {
        my @vmstat_lines = read_file("/proc/vmstat");
        
        foreach my $line (@vmstat_lines) {
            if ($line =~ /^(\w+)\s+(\d+)/) {
                $cache_data{$1} = $2;
            }
        }
        
        my $page_cache_hits = $cache_data{pgsteal_kswapd} || 0;
        my $page_cache_misses = $cache_data{pgalloc_high} || 0;
        my $total_access = $page_cache_hits + $page_cache_misses;
        
        if ($total_access > 0) {
            $efficiency = ($page_cache_hits / $total_access) * 100;
        }
    }
    
    return {
        efficiency => sprintf("%.2f", $efficiency),
        raw_data => \%cache_data,
    };
}

sub _analyze_numa_topology {
    my $self = shift;
    
    my $balance_score = 100;
    my %numa_data;
    
    if (-r "/proc/numastat") {
        my @numastat_lines = read_file("/proc/numastat");
        
        foreach my $line (@numastat_lines) {
            if ($line =~ /^(\w+)\s+(.+)/) {
                my $metric = $1;
                my @values = split(/\s+/, $2);
                $numa_data{$metric} = \@values;
            }
        }
        
        if (exists $numa_data{numa_hit}) {
            my @hits = @{$numa_data{numa_hit}};
            my @misses = @{$numa_data{numa_miss} || []};
            
            my $total_hits = 0;
            my $total_misses = 0;
            
            for my $i (0..$#hits) {
                $total_hits += $hits[$i];
                $total_misses += $misses[$i] || 0;
            }
            
            my $total_access = $total_hits + $total_misses;
            if ($total_access > 0) {
                $balance_score = ($total_hits / $total_access) * 100;
            }
        }
    }
    
    return {
        balance_score => sprintf("%.2f", $balance_score),
        numa_data => \%numa_data,
    };
}

sub _calculate_oom_risk {
    my $self = shift;
    
    my $risk = 0;
    
    # OOM kill 
    if (-r "/proc/vmstat") {
        my @vmstat_lines = read_file("/proc/vmstat");
        foreach my $line (@vmstat_lines) {
            if ($line =~ /^oom_kill\s+(\d+)/) {
                $risk = $1 > 0 ? 50 : 0;
                last;
            }
        }
    }
    
    if (-r "/proc/pressure/memory") {
        my @pressure_lines = read_file("/proc/pressure/memory");
        foreach my $line (@pressure_lines) {
            if ($line =~ /^full avg10=(\d+\.\d+)/) {
                my $pressure = $1;
                if ($pressure > 10) {
                    $risk += 30;
                } elsif ($pressure > 5) {
                    $risk += 15;
                }
            }
        }
    }
    
    return sprintf("%.0f", $risk > 100 ? 100 : $risk);
}

sub _calculate_pressure_score {
    my ($self, $basic, $pressure, $fragmentation, $cache, $numa) = @_;
    
    my $base_pressure = $basic->{percent_used};
    
    my $fragmentation_penalty = $fragmentation->{index} / 100 * 20;
    
    my $cache_bonus = (100 - $cache->{efficiency}) / 100 * 10;
    
    my $numa_penalty = (100 - $numa->{balance_score}) / 100 * 15;
    
    my $swap_penalty = $basic->{swap_percent} / 100 * 25;
    
    my $total_pressure = $base_pressure + $fragmentation_penalty + $cache_bonus + $numa_penalty + $swap_penalty;
    
    $total_pressure = 100 if $total_pressure > 100;
    
    push @{$self->{pressure_trends}}, {
        timestamp => time(),
        pressure => $total_pressure,
    };
    
    if (@{$self->{pressure_trends}} > 20) {
        shift @{$self->{pressure_trends}};
    }
    
    return sprintf("%.2f", $total_pressure);
}

sub _calculate_quality_score {
    my ($self, $pressure_score) = @_;
    
    my $score = 100;
    
    if ($pressure_score > 90) {
        $score -= 40;
    } elsif ($pressure_score > 70) {
        $score -= 25;
    } elsif ($pressure_score > 50) {
        $score -= 15;
    }
    
    if ($pressure_score < 30) {
        $score += 10;
    }
    
    return sprintf("%.0f", $score);
}

sub _calculate_trend_direction {
    my $self = shift;
    
    return 0 if @{$self->{pressure_trends}} < 3;
    
    my @recent = @{$self->{pressure_trends}}[-3..-1];
    my $start = $recent[0]{pressure};
    my $end = $recent[-1]{pressure};
    
    my $trend = $end - $start;
    
    if ($trend > 5) {
        return 1; # increasing
    } elsif ($trend < -5) {
        return -1; # decreasing
    } else {
        return 0; # stable
    }
}

1;

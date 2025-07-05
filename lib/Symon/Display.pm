#!/usr/bin/perl

package Symon::Display;

use strict;
use warnings;
use Term::ANSIColor;
use POSIX qw(strftime);

sub new {
    my ($class, $config) = @_;
    my $self = {
        config => $config || {},
        theme => $config->{theme} || 'matrix',
        width => $config->{width} || 80,
        height => $config->{height} || 24,
        no_color => $config->{no_color} || 0,
    };
    
    bless $self, $class;
    $self->init_themes();
    return $self;
}

sub init_themes {
    my ($self) = @_;
    
    my %themes = (
        'matrix' => {
            primary => 'bold green',
            secondary => 'green',
            accent => 'bold white',
            warning => 'bold yellow',
            critical => 'bold red',
            info => 'cyan',
            bars => {
                full => '█',
                seven => '▉',
                six => '▊',
                five => '▋',
                four => '▌',
                three => '▍',
                two => '▎',
                one => '▏',
                empty => '░',
            },
        },
        'cyber' => {
            primary => 'bold cyan',
            secondary => 'blue',
            accent => 'bold white',
            warning => 'bold magenta',
            critical => 'bold red',
            info => 'cyan',
            bars => {
                full => '█',
                seven => '▉',
                six => '▊',
                five => '▋',
                four => '▌',
                three => '▍',
                two => '▎',
                one => '▏',
                empty => '▒',
            },
        },
        'retro' => {
            primary => 'bold yellow',
            secondary => 'yellow',
            accent => 'bold white',
            warning => 'bold red',
            critical => 'bold red',
            info => 'white',
            bars => {
                full => '#',
                seven => '#',
                six => '#',
                five => '*',
                four => '*',
                three => '+',
                two => '+',
                one => '-',
                empty => '.',
            },
        },
        'minimal' => {
            primary => 'bold white',
            secondary => 'white',
            accent => 'bold white',
            warning => 'white',
            critical => 'bold white',
            info => 'white',
            bars => {
                full => '|',
                seven => '|',
                six => '|',
                five => '|',
                four => '|',
                three => '|',
                two => '|',
                one => '|',
                empty => '-',
            },
        },
    );
    
    $self->{theme_colors} = $themes{$self->{theme}} || $themes{'matrix'};
}

sub display_full_stats {
    my ($self, $stats) = @_;
    
    system("clear");
    
    $self->display_main_header($stats);
    
    $self->display_system_overview($stats);
    
    $self->display_cpu_section($stats->{cpu}) if $stats->{cpu};
    
    $self->display_memory_section($stats->{memory}) if $stats->{memory};
    
    $self->display_additional_metrics($stats);
    
    $self->display_footer($stats);
}

sub display_main_header {
    my ($self, $stats) = @_;
    
    my $banner = <<'EOF';
  ███████╗██╗   ██╗███╗   ███╗ ██████╗ ███╗   ██╗    ██╗   ██╗██████╗ 
  ██╔════╝╚██╗ ██╔╝████╗ ████║██╔═══██╗████╗  ██║    ██║   ██║╚════██╗
  ███████╗ ╚████╔╝ ██╔████╔██║██║   ██║██╔██╗ ██║    ██║   ██║ █████╔╝
  ╚════██║  ╚██╔╝  ██║╚██╔╝██║██║   ██║██║╚██╗██║    ╚██╗ ██╔╝██╔═══╝ 
  ███████║   ██║   ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║     ╚████╔╝ ███████╗
  ╚══════╝   ╚═╝   ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝      ╚═══╝  ╚══════╝
EOF
    
    $self->print_colored($banner, 'primary');
    
    my $subtitle = "                      ADVANCED SYSTEM MONITOR v2.0                      ";
    $self->print_colored($subtitle, 'accent');
    print "\n";
    
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime());
    my $uptime = $self->format_uptime($stats->{uptime});
    my $platform = $self->detect_platform();
    
    my $info_line = sprintf("    [%s] [%s] [%s]", $timestamp, $uptime, $platform);
    $self->print_colored($info_line, 'info');
    print "\n\n";
}

sub display_system_overview {
    my ($self, $stats) = @_;
    
    print "╔" . "═" x 78 . "╗\n";
    print "║" . " " x 30 . "SYSTEM OVERVIEW" . " " x 33 . "║\n";
    print "╠" . "═" x 78 . "╣\n";
    
    my $cpu_pct = $stats->{cpu}{weighted_usage}{weighted_percent} || 0;
    my $mem_pct = $stats->{memory}{pressure_score} || 0;
    my $load = $stats->{load}{load_1min} || 0;
    
    printf "║ CPU: %5.1f%%  ║ Memory: %5.1f%%  ║ Load: %8.2f ║\n", $cpu_pct, $mem_pct, $load;
    printf "║ %s ║ %s ║ Cores: %6d ║\n", 
           $self->create_bar($cpu_pct, 12), 
           $self->create_bar($mem_pct, 12),
           $stats->{cpu_cores} || 1;
    
    print "╚" . "═" x 78 . "╝\n\n";
}

sub display_cpu_section {
    my ($self, $cpu_stats) = @_;
    
    print "╔" . "═" x 78 . "╗\n";
    print "║" . " " x 35 . "CPU METRICS" . " " x 32 . "║\n";
    print "╠" . "═" x 78 . "╣\n";
    
    my $raw = $cpu_stats->{raw_usage} || {};
    if (ref $raw eq 'HASH' && exists $raw->{total}) {
        my $total = $raw->{total};
        printf "║ USER: %5.1f%% │ SYSTEM: %5.1f%% │ IDLE: %5.1f%% │ IOWAIT: %5.1f%% ║\n",
               $total->{user} || 0, $total->{system} || 0, 
               $total->{idle} || 0, $total->{iowait} || 0;
    }
    
    my $weighted = $cpu_stats->{weighted_usage} || {};
    if (ref $weighted eq 'HASH') {
        printf "║ WEIGHTED: %5.1f%% │ EFFICIENCY: %5.1f%% │ THERMAL: %5.1f°C      ║\n",
               $weighted->{weighted_percent} || 0,
               $cpu_stats->{efficiency_score} || 0,
               $cpu_stats->{thermal_state}{temperature} || 0;
        
        print "║ " . $self->create_bar($weighted->{weighted_percent} || 0, 18) . " │ ";
        print $self->create_bar($cpu_stats->{efficiency_score} || 0, 18) . " │ ";
        print $self->create_temp_bar($cpu_stats->{thermal_state}{temperature} || 0, 18) . " ║\n";
    }
    
    my $prediction = $cpu_stats->{prediction} || {};
    if (ref $prediction eq 'HASH' && exists $prediction->{trend_slope}) {
        my $trend = $prediction->{trend_slope};
        my $trend_symbol = $trend > 0.5 ? "▲" : ($trend < -0.5 ? "▼" : "▶");
        
        printf "║ TREND: %s %+6.2f │ VOLATILITY: %5.1f%% │ PRESSURE: %5.1f%%     ║\n",
               $trend_symbol, $trend,
               $prediction->{volatility} || 0,
               $cpu_stats->{scheduler_pressure} || 0;
    }
    
    print "╚" . "═" x 78 . "╝\n\n";
}

sub display_memory_section {
    my ($self, $memory_stats) = @_;
    
    print "╔" . "═" x 78 . "╗\n";
    print "║" . " " x 33 . "MEMORY METRICS" . " " x 31 . "║\n";
    print "╠" . "═" x 78 . "╣\n";
    
    my $raw = $memory_stats->{raw_stats} || {};
    if (ref $raw eq 'HASH') {
        my $total_gb = ($raw->{MemTotal} || 0) / (1024**3);
        my $available_gb = ($raw->{MemAvailable} || 0) / (1024**3);
        my $used_gb = $total_gb - $available_gb;
        
        printf "║ TOTAL: %6.1f GB │ USED: %6.1f GB │ AVAILABLE: %6.1f GB    ║\n",
               $total_gb, $used_gb, $available_gb;
        
        my $used_pct = $total_gb > 0 ? ($used_gb / $total_gb) * 100 : 0;
        print "║ " . $self->create_bar($used_pct, 70) . " ║\n";
    }
    
    my $pressure = $memory_stats->{pressure_score} || 0;
    my $swap_pressure = $memory_stats->{swap_pressure} || {};
    my $cache_pressure = $memory_stats->{cache_pressure} || {};
    
    printf "║ PRESSURE: %5.1f%% │ SWAP: %5.1f%% │ CACHE HIT: %5.1f%%        ║\n",
           $pressure,
           $swap_pressure->{usage_percent} || 0,
           $cache_pressure->{cache_hit_rate} || 0;
    
    print "║ " . $self->create_pressure_bar($pressure, 18) . " │ ";
    print $self->create_bar($swap_pressure->{usage_percent} || 0, 18) . " │ ";
    print $self->create_bar($cache_pressure->{cache_hit_rate} || 0, 18) . " ║\n";
    
    my $efficiency = $memory_stats->{efficiency} || {};
    my $fragmentation = $memory_stats->{fragmentation} || {};
    my $oom_risk = $memory_stats->{oom_risk} || 0;
    
    printf "║ EFFICIENCY: %5.1f%% │ FRAGMENTATION: %5.1f%% │ OOM RISK: %5.1f%% ║\n",
           $efficiency->{overall_score} || 0,
           $fragmentation->{fragmentation_index} || 0,
           $oom_risk;
    
    print "╚" . "═" x 78 . "╝\n\n";
}

sub display_additional_metrics {
    my ($self, $stats) = @_;
    
    print "╔" . "═" x 78 . "╗\n";
    print "║" . " " x 31 . "ADDITIONAL METRICS" . " " x 29 . "║\n";
    print "╠" . "═" x 78 . "╣\n";
    
    if ($stats->{network}) {
        my $total_rx = 0;
        my $total_tx = 0;
        my $interface_count = 0;
        
        foreach my $interface (keys %{$stats->{network}}) {
            my $net = $stats->{network}{$interface};
            $total_rx += $net->{rx_bytes} || 0;
            $total_tx += $net->{tx_bytes} || 0;
            $interface_count++;
        }
        
        printf "║ NETWORK RX: %8.1f MB │ TX: %8.1f MB │ INTERFACES: %3d      ║\n",
               $total_rx / (1024**2), $total_tx / (1024**2), $interface_count;
    }
    
    if ($stats->{disk}) {
        my $disk = $stats->{disk};
        my $usage_pct = $disk->{use_percent} || "0%";
        $usage_pct =~ s/%//;
        
        printf "║ DISK: %s used │ %s available │ Usage: %5.1f%%           ║\n",
               $disk->{used} || "0", $disk->{available} || "0", $usage_pct;
    }
    
    if ($stats->{processes}) {
        my $proc_count = scalar(@{$stats->{processes}});
        my $top_cpu = $stats->{processes}[0]{cpu} || 0;
        
        printf "║ PROCESSES: %6d │ TOP CPU: %5.1f%% │ LOAD AVG: %8.2f    ║\n",
               $proc_count, $top_cpu, $stats->{load}{load_1min} || 0;
    }
    
    print "╚" . "═" x 78 . "╝\n\n";
}

sub display_footer {
    my ($self, $stats) = @_;
    
    print "╔" . "═" x 78 . "╗\n";
    
    my $alert_count = 0;
    my $alert_level = "OK";
    
    if ($stats->{alerts} && ref $stats->{alerts} eq 'ARRAY') {
        $alert_count = scalar(@{$stats->{alerts}});
        if ($alert_count > 0) {
            my $has_critical = grep { $_->{level} eq 'critical' } @{$stats->{alerts}};
            $alert_level = $has_critical ? "CRITICAL" : "WARNING";
        }
    }
    
    my $status_color = $alert_level eq 'CRITICAL' ? 'critical' : 
                      $alert_level eq 'WARNING' ? 'warning' : 'info';
    
    printf "║ STATUS: ";
    $self->print_colored(sprintf("%-10s", $alert_level), $status_color);
    printf " │ ALERTS: %3d │ UPTIME: %20s ║\n",
           $alert_count, $self->format_uptime($stats->{uptime});
    
    print "╚" . "═" x 78 . "╝\n";
    
    print "\n";
    $self->print_colored("  [CTRL+C] Exit  [SPACE] Pause  [R] Reset  [H] Help", 'info');
    print "\n\n";
}

sub create_bar {
    my ($self, $percentage, $width) = @_;
    
    $percentage = max(0, min(100, $percentage));
    my $filled = int(($percentage / 100) * $width);
    my $empty = $width - $filled;
    
    my $bars = $self->{theme_colors}{bars};
    my $bar = $bars->{full} x $filled . $bars->{empty} x $empty;
    
    my $color = $percentage > 90 ? 'critical' : 
               $percentage > 70 ? 'warning' : 'secondary';
    
    return $self->colorize($bar, $color);
}

sub create_pressure_bar {
    my ($self, $pressure, $width) = @_;
    
    my $color = $pressure > 80 ? 'critical' : 
               $pressure > 60 ? 'warning' : 
               $pressure > 40 ? 'accent' : 'secondary';
    
    return $self->create_bar($pressure, $width);
}

sub create_temp_bar {
    my ($self, $temperature, $width) = @_;
    
    my $temp_pct = min(100, ($temperature / 100) * 100); # 0-100
    my $color = $temperature > 80 ? 'critical' : 
               $temperature > 60 ? 'warning' : 'info';
    
    return $self->create_bar($temp_pct, $width);
}

sub format_uptime {
    my ($self, $uptime_data) = @_;
    
    return "Unknown" unless $uptime_data;
    
    if (ref $uptime_data eq 'HASH') {
        return $uptime_data->{uptime_formatted} || "Unknown";
    }
    
    return $uptime_data;
}

sub detect_platform {
    my ($self) = @_;
    
    if (-f "/etc/arch-release") {
        return "Arch Linux";
    } elsif (-f "/etc/debian_version") {
        return "Debian/Ubuntu";
    } elsif (-f "/etc/redhat-release") {
        return "Red Hat/CentOS";
    } elsif (-f "/etc/os-release") {
        return "Linux";
    } else {
        return "Unknown";
    }
}

sub print_colored {
    my ($self, $text, $color_name) = @_;
    
    if ($self->{no_color}) {
        print $text;
    } else {
        my $color = $self->{theme_colors}{$color_name} || 'white';
        print colored($text, $color);
    }
}

sub colorize {
    my ($self, $text, $color_name) = @_;
    
    if ($self->{no_color}) {
        return $text;
    } else {
        my $color = $self->{theme_colors}{$color_name} || 'white';
        return colored($text, $color);
    }
}

sub max {
    my ($a, $b) = @_;
    return $a > $b ? $a : $b;
}

sub min {
    my ($a, $b) = @_;
    return $a < $b ? $a : $b;
}

sub display_minimal_stats {
    my ($self, $stats) = @_;
    
    my $cpu_pct = $stats->{cpu}{weighted_usage}{weighted_percent} || 0;
    my $mem_pct = $stats->{memory}{pressure_score} || 0;
    my $load = $stats->{load}{load_1min} || 0;
    
    printf "CPU: %5.1f%% [%s] MEM: %5.1f%% [%s] LOAD: %6.2f\n",
           $cpu_pct, $self->create_bar($cpu_pct, 10),
           $mem_pct, $self->create_bar($mem_pct, 10),
           $load;
}

sub display_compact_stats {
    my ($self, $stats) = @_;
    
    print "╔" . "═" x 50 . "╗\n";
    print "║" . " " x 18 . "SYMON COMPACT" . " " x 19 . "║\n";
    print "╠" . "═" x 50 . "╣\n";
    
    my $cpu_pct = $stats->{cpu}{weighted_usage}{weighted_percent} || 0;
    my $mem_pct = $stats->{memory}{pressure_score} || 0;
    
    printf "║ CPU: %5.1f%% [%s] ║\n", $cpu_pct, $self->create_bar($cpu_pct, 20);
    printf "║ MEM: %5.1f%% [%s] ║\n", $mem_pct, $self->create_bar($mem_pct, 20);
    
    print "╚" . "═" x 50 . "╝\n";
}

1;

__END__

=head1 NAME

Symon::Display - ASCII display module for SYMON system monitor

=head1 SYNOPSIS

    use Symon::Display;
    
    my $display = Symon::Display->new(\%config);
    $display->display_full_stats(\%stats);

=head1 DESCRIPTION

This module provides impressive ASCII-based terminal displays for the SYMON system monitor. Features include:

- Multiple themes (matrix, cyber, retro, minimal)
- Progress bars using Unicode block characters
- Color-coded output with customizable themes
- Compact and detailed display modes
- No emoji dependency - pure ASCII/Unicode

=head1 METHODS

=head2 new(\%config)

Creates a new Display instance with theme and configuration options.

=head2 display_full_stats(\%stats)

Displays comprehensive system statistics with ASCII art and progress bars.

=head2 display_minimal_stats(\%stats)

Shows minimal one-line statistics display.

=head2 display_compact_stats(\%stats)

Shows compact boxed statistics display.

=head1 THEMES

- matrix: Green matrix-style theme
- cyber: Blue/cyan cyberpunk theme  
- retro: Yellow/amber retro terminal theme
- minimal: Clean monochrome theme

=head1 AUTHOR

System Monitor Team

=head1 LICENSE

MIT License

=cut

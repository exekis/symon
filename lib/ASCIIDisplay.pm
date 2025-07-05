package ASCIIDisplay;

use strict;
use warnings;
use Term::ANSIColor;

sub new {
    my $class = shift;
    my %args = @_;
    
    my $self = {
        theme => $args{theme} || 'default',
        format => $args{format} || 'ascii',
        width => $args{width} || 80,
        height => $args{height} || 24,
        colors => $args{colors} || {},
    };
    
    bless $self, $class;
    $self->_init_theme();
    return $self;
}

sub _init_theme {
    my $self = shift;
    
    my %themes = (
        'default' => {
            primary => 'cyan',
            secondary => 'white',
            accent => 'yellow',
            warning => 'red',
            success => 'green',
            border => 'blue',
        },
        'matrix' => {
            primary => 'green',
            secondary => 'bright_green',
            accent => 'bright_white',
            warning => 'bright_red',
            success => 'bright_green',
            border => 'green',
        },
        'cyber' => {
            primary => 'magenta',
            secondary => 'cyan',
            accent => 'bright_white',
            warning => 'bright_red',
            success => 'bright_cyan',
            border => 'bright_magenta',
        },
        'retro' => {
            primary => 'yellow',
            secondary => 'white',
            accent => 'bright_yellow',
            warning => 'red',
            success => 'green',
            border => 'yellow',
        },
        'minimal' => {
            primary => 'white',
            secondary => 'white',
            accent => 'white',
            warning => 'white',
            success => 'white',
            border => 'white',
        },
    );
    
    $self->{colors} = $themes{$self->{theme}} || $themes{'default'};
}

sub show_data {
    my ($self, $data) = @_;
    
    if ($self->{format} eq 'ascii') {
        $self->_show_ascii_display($data);
    } elsif ($self->{format} eq 'minimal') {
        $self->_show_minimal_display($data);
    } elsif ($self->{format} eq 'detailed') {
        $self->_show_detailed_display($data);
    }
}

sub _show_ascii_display {
    my ($self, $data) = @_;
    
    system("clear");
    
    print $self->_color('primary', $self->_get_ascii_header());
    print "\n";
    
    print $self->_color('border', "+" . "="x78 . "+") . "\n";
    print $self->_color('border', "|") . 
          $self->_color('accent', sprintf(" %-76s ", "SYMON v2.0 - Advanced System Monitor")) . 
          $self->_color('border', "|") . "\n";
    print $self->_color('border', "|") . 
          $self->_color('secondary', sprintf(" %-76s ", "Timestamp: " . ($data->{timestamp} || strftime("%Y-%m-%d %H:%M:%S", localtime)))) . 
          $self->_color('border', "|") . "\n";
    print $self->_color('border', "+" . "="x78 . "+") . "\n";
    
    if ($data->{cpu}) {
        print $self->_color('primary', "\n[CPU ANALYSIS]") . "\n";
        $self->_draw_cpu_bars($data->{cpu});
    }
    
    if ($data->{memory}) {
        print $self->_color('primary', "\n[MEMORY ANALYSIS]") . "\n";
        $self->_draw_memory_bars($data->{memory});
    }
    
    print $self->_color('border', "\n" . "+"x80) . "\n";
    print $self->_color('secondary', "Press Ctrl+C to exit | Data refreshes every few seconds") . "\n";
    print $self->_color('border', "+"x80) . "\n";
}

sub _show_minimal_display {
    my ($self, $data) = @_;
    
    my $cpu_usage = $data->{cpu}{smart_usage} || 0;
    my $mem_pressure = $data->{memory}{pressure_score} || 0;
    
    printf "CPU: %6.2f%% | MEM: %6.2f%% | %s\n",
        $cpu_usage, $mem_pressure, $data->{timestamp} || strftime("%H:%M:%S", localtime);
}

sub _show_detailed_display {
    my ($self, $data) = @_;
    
    system("clear");
    
    print $self->_color('primary', "SYMON - DETAILED SYSTEM ANALYSIS") . "\n";
    print $self->_color('border', "="x80) . "\n";
    
    if ($data->{cpu}) {
        print $self->_color('accent', "\nCPU METRICS:") . "\n";
        printf "  Basic Usage:         %6.2f%%\n", $data->{cpu}{basic_usage}{total} || 0;
        printf "  Smart Usage:         %6.2f%%\n", $data->{cpu}{smart_usage} || 0;
        printf "  Process Weight:      %6.2f\n", $data->{cpu}{process_weight_factor} || 0;
        printf "  Scheduling Eff:      %6.2f%%\n", $data->{cpu}{scheduling_efficiency} || 0;
        printf "  Thermal Factor:      %6.2f\n", $data->{cpu}{thermal_throttling} || 0;
        printf "  Frequency Scale:     %6.2f\n", $data->{cpu}{frequency_scaling} || 0;
        printf "  Quality Score:       %6.0f/100\n", $data->{cpu}{quality_score} || 0;
    }
    
    if ($data->{memory}) {
        print $self->_color('accent', "\nMEMORY METRICS:") . "\n";
        printf "  Basic Usage:         %6.2f%%\n", $data->{memory}{basic_memory}{percent_used} || 0;
        printf "  Pressure Score:      %6.2f\n", $data->{memory}{pressure_score} || 0;
        printf "  Fragmentation:       %6.2f\n", $data->{memory}{fragmentation_index} || 0;
        printf "  Cache Efficiency:    %6.2f%%\n", $data->{memory}{cache_efficiency} || 0;
        printf "  NUMA Balance:        %6.2f\n", $data->{memory}{numa_balance} || 0;
        printf "  OOM Risk:            %6.0f%%\n", $data->{memory}{oom_risk} || 0;
        printf "  Quality Score:       %6.0f/100\n", $data->{memory}{quality_score} || 0;
    }
    
    print $self->_color('border', "\n" . "="x80) . "\n";
}

sub _get_ascii_header {
    my $self = shift;
    
    return <<'EOF';
 ____  _   _ __  __  ___  _   _ 
/ ___|| | | |  \/  |/ _ \| \ | |
\___ \| |_| | |\/| | | | |  \| |
 ___) |  _  | |  | | |_| | |\  |
|____/|_| |_|_|  |_|\___/|_| \_|
                                
Advanced System Monitor v2.0
EOF
}

sub _draw_cpu_bars {
    my ($self, $cpu_data) = @_;
    
    my $basic_usage = $cpu_data->{basic_usage}{total} || 0;
    my $smart_usage = $cpu_data->{smart_usage} || 0;
    my $quality = $cpu_data->{quality_score} || 0;
    
    print $self->_color('secondary', sprintf("Basic CPU Usage: %6.2f%%", $basic_usage)) . "\n";
    print $self->_draw_bar($basic_usage, 50, 'warning');
    
    print $self->_color('secondary', sprintf("Smart CPU Usage: %6.2f%%", $smart_usage)) . "\n";
    print $self->_draw_bar($smart_usage, 50, 'primary');
    
    print $self->_color('secondary', sprintf("Quality Score:   %6.0f/100", $quality)) . "\n";
    print $self->_draw_bar($quality, 50, 'success');
}

sub _draw_memory_bars {
    my ($self, $memory_data) = @_;
    
    my $basic_usage = $memory_data->{basic_memory}{percent_used} || 0;
    my $pressure = $memory_data->{pressure_score} || 0;
    my $quality = $memory_data->{quality_score} || 0;
    
    print $self->_color('secondary', sprintf("Basic Memory:    %6.2f%%", $basic_usage)) . "\n";
    print $self->_draw_bar($basic_usage, 50, 'warning');
    
    print $self->_color('secondary', sprintf("Pressure Score:  %6.2f", $pressure)) . "\n";
    print $self->_draw_bar($pressure, 50, 'primary');
    
    print $self->_color('secondary', sprintf("Quality Score:   %6.0f/100", $quality)) . "\n";
    print $self->_draw_bar($quality, 50, 'success');
}

sub _draw_bar {
    my ($self, $value, $width, $color_type) = @_;
    
    my $filled = int(($value / 100) * $width);
    my $empty = $width - $filled;
    
    my $bar = "[" . 
              $self->_color($color_type, "=" x $filled) . 
              " " x $empty . 
              "]";
    
    print $bar . sprintf(" %6.1f%%", $value) . "\n";
}

sub show_benchmark_results {
    my ($self, $results) = @_;
    
    system("clear");
    
    print $self->_color('primary', "BENCHMARK RESULTS") . "\n";
    print $self->_color('border', "="x50) . "\n";
    
    printf "Duration:        %d seconds\n", $results->{duration};
    printf "Samples:         %d\n", $results->{sample_count};
    printf "CPU Average:     %.2f%%\n", $results->{cpu_avg};
    printf "CPU Peak:        %.2f%%\n", $results->{cpu_max};
    printf "Memory Average:  %.2f\n", $results->{memory_avg};
    printf "Memory Peak:     %.2f\n", $results->{memory_max};
    
    print $self->_color('border', "="x50) . "\n";
}

sub show_comparison {
    my ($self, $comparison) = @_;
    
    system("clear");
    
    print $self->_color('primary', "SYSTEM COMPARISON") . "\n";
    print $self->_color('border', "="x50) . "\n";
    
    printf "Timestamp:       %s\n", $comparison->{timestamp};
    printf "CPU Difference:  %+.2f%%\n", $comparison->{cpu_diff};
    printf "Memory Difference: %+.2f\n", $comparison->{memory_diff};
    
    print $self->_color('border', "="x50) . "\n";
}

sub _color {
    my ($self, $type, $text) = @_;
    
    return $text unless $self->{colors}{$type};
    
    return colored($text, $self->{colors}{$type});
}

1;

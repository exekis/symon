# SYMON

A comprehensive, cross-platform Perl system monitor with advanced features for Linux (especially Arch Linux) and macOS. SYMON provides real-time monitoring, alerting, trending, and detailed logging of system performance metrics with novel CPU and memory analysis methods.

## FEATURES

### Core Monitoring
- **Smart CPU Usage**: Novel weighted calculation based on process priority, type, and scheduling behavior
- **Memory Pressure Analysis**: Advanced pressure calculation considering swap behavior, cache efficiency, and fragmentation  
- **Disk Usage Monitoring**: Comprehensive disk space and I/O monitoring with filesystem details
- **Temperature Monitoring**: Multi-source temperature monitoring with thermal throttling detection
- **System Load Analysis**: Load averages, process statistics, and scheduler pressure analysis
- **Network Statistics**: Interface monitoring with throughput analysis and trend detection

### Advanced Features
- **Process Priority Weighting**: CPU calculations consider process importance and scheduling class
- **Memory Pressure Prediction**: Predictive swap usage and OOM risk assessment
- **Performance Trending**: Historical analysis with volatility and trend prediction
- **NUMA Topology Aware**: Memory locality and NUMA balance analysis
- **Thermal Management**: CPU frequency scaling and thermal throttling detection
- **Cache Efficiency**: Buffer and page cache hit rate analysis
- **Fragmentation Analysis**: Memory fragmentation and compaction statistics

### User Interface
- **Multiple Display Modes**: ASCII art, minimal, detailed, and compact display options
- **Configurable Themes**: Matrix, cyber, retro, and minimal color schemes
- **Command Line Interface**: Comprehensive CLI with multiple operation modes
- **Profile System**: Pre-configured profiles for different use cases
- **Real-time Updates**: Configurable update intervals from 1 second to 5 minutes

### Configuration & Profiles
- **Profile Management**: Default, server, desktop, gaming, minimal, developer, and troubleshooting profiles
- **JSON Configuration**: Flexible configuration system with validation
- **Export/Import**: Configuration backup and sharing capabilities
- **Automatic Setup**: Self-configuring with intelligent defaults

## PLATFORM SUPPORT

### Linux (Arch Linux Optimized)
- Advanced /proc filesystem parsing for CPU, memory, and system statistics
- lm-sensors integration for temperature monitoring
- NUMA topology detection and analysis
- Memory pressure interface support (Linux 4.20+)
- Scheduler statistics and pressure analysis
- Thermal zone monitoring with multiple sensor support
- Memory compression (zswap/zram) statistics
- Process scheduling class detection

### macOS
- Native system API integration
- osx-cpu-temp for temperature monitoring
- vm_stat for memory statistics
- iostat for disk I/O monitoring
- sysctl for system information

## INSTALLATION

### Prerequisites

```bash
# Arch Linux
sudo pacman -S perl perl-json perl-file-slurp perl-term-ansicolor lm-sensors

# Debian/Ubuntu
sudo apt-get install perl libjson-perl libfile-slurp-perl libterm-ansicolor-perl lm-sensors

# macOS
brew install perl
cpan JSON File::Slurp Term::ANSIColor
brew install osx-cpu-temp
```

### Perl Modules

```bash
# Using CPAN
cpan JSON File::Slurp Term::ANSIColor Time::HiRes POSIX Sys::Info

# Using cpanm (recommended)
cpanm JSON File::Slurp Term::ANSIColor Time::HiRes POSIX Sys::Info::OS Sys::Info::Device
```

### Setup

```bash
# Clone repository
git clone <repository-url>
cd symon

# Make executable
chmod +x symon_cli.pl system_monitor.pl

# Run installation script
./install.sh

# Configure sensors (Linux only)
sudo sensors-detect
```

## USAGE

### Basic Usage

```bash
# Start monitoring with default profile
./symon_cli.pl

# Use specific profile
./symon_cli.pl --profile gaming

# Compact display with custom theme
./symon_cli.pl --format minimal --theme cyber

# Server monitoring mode
./symon_cli.pl --profile server --interval 10
```

### Advanced Usage

```bash
# Benchmark mode for 60 seconds
./symon_cli.pl --mode benchmark --duration 60

# Single snapshot with detailed output
./symon_cli.pl --mode snapshot --format detailed

# Export monitoring data
./symon_cli.pl --mode monitor --export system_data.json

# Compare with baseline
./symon_cli.pl --compare baseline.json

# Troubleshooting mode with maximum detail
./symon_cli.pl --profile troubleshooting --verbose
```

### CLI Options

```
MODES:
    monitor         Real-time system monitoring (default)
    snapshot        Single system snapshot
    benchmark       CPU/Memory benchmarking
    compare         Compare system states
    report          Generate performance reports
    interactive     Interactive monitoring mode

OPTIONS:
    -h, --help              Show help message
    -v, --version           Show version information
    -c, --config FILE       Configuration file
    -m, --mode MODE         Operation mode
    -i, --interval SEC      Update interval (1-300 seconds)
    -d, --duration SEC      Run duration (0 = infinite)
    -f, --format STYLE      Display format: ascii, minimal, detailed
    -p, --profile PROFILE   Use profile: default, server, desktop, gaming
    -t, --theme THEME       Color theme: matrix, cyber, retro, minimal
    -q, --quiet             Quiet mode
    --verbose               Verbose mode
    --no-color              Disable colors
    --cpu-method METHOD     CPU calculation method
    --memory-method METHOD  Memory calculation method
    --export FILE           Export data to file
```

## CONFIGURATION

### Profiles

**Default Profile**: Balanced monitoring for general use
- 5-second update interval
- Smart CPU and memory pressure calculation
- Matrix theme with full feature set

**Server Profile**: Optimized for server environments
- 10-second update interval
- System process prioritization
- Minimal theme with essential metrics
- Enhanced disk and network monitoring

**Desktop Profile**: Desktop/workstation focused
- 3-second update interval
- Interactive process prioritization
- Cyber theme with visual enhancements
- Temperature and power monitoring

**Gaming Profile**: Gaming performance monitoring
- 1-second update interval
- Maximum interactive process priority
- Retro theme with high-frequency updates
- Thermal and power state monitoring

**Minimal Profile**: Lightweight monitoring
- 15-second update interval
- Basic CPU and memory metrics only
- Minimal theme with no colors
- Reduced feature set for low overhead

**Developer Profile**: Development environment monitoring
- 2-second update interval
- Compilation and build process awareness
- Enhanced disk I/O monitoring
- Process-specific CPU weighting

**Troubleshooting Profile**: Maximum detail monitoring
- 1-second update interval
- All features enabled
- Verbose output mode
- Extended history and precision

### Configuration File

Location: `~/.symon/symon_config.json`

Key settings:
- `monitor_interval`: Update frequency (1-300 seconds)
- `cpu_method`: 'smart', 'traditional', or 'weighted'
- `memory_method`: 'pressure', 'traditional', or 'available'
- `theme`: 'matrix', 'cyber', 'retro', or 'minimal'
- Alert thresholds for CPU, memory, disk, and temperature

## NOVEL CALCULATION METHODS

### Smart CPU Usage
- **Process Weighting**: Interactive processes (browsers, editors) weighted higher than background tasks
- **Priority Consideration**: Process nice values and scheduling class affect CPU importance
- **Thermal Correction**: CPU frequency scaling and thermal throttling factored into usage calculations
- **Scheduler Pressure**: System load and scheduling latency incorporated into efficiency metrics

### Memory Pressure Analysis
- **Multi-factor Pressure**: Combines swap usage, cache pressure, and allocation failure rates
- **Fragmentation Awareness**: Memory fragmentation and compaction statistics included
- **NUMA Balance**: Memory locality and NUMA node balance considered
- **Predictive Modeling**: Swap exhaustion and OOM risk prediction based on usage trends

### Efficiency Scoring
- **CPU Efficiency**: Ratio of productive vs. wasteful CPU usage based on process importance
- **Memory Efficiency**: Optimal memory utilization considering cache performance
- **Thermal Efficiency**: Temperature-adjusted performance metrics
- **Overall System Health**: Composite score incorporating all subsystem efficiency metrics

## OUTPUT EXAMPLE

```
  ███████╗██╗   ██╗███╗   ███╗ ██████╗ ███╗   ██╗    ██╗   ██╗██████╗ 
  ██╔════╝╚██╗ ██╔╝████╗ ████║██╔═══██╗████╗  ██║    ██║   ██║╚════██╗
  ███████╗ ╚████╔╝ ██╔████╔██║██║   ██║██╔██╗ ██║    ██║   ██║ █████╔╝
  ╚════██║  ╚██╔╝  ██║╚██╔╝██║██║   ██║██║╚██╗██║    ╚██╗ ██╔╝██╔═══╝ 
  ███████║   ██║   ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║     ╚████╔╝ ███████╗
  ╚══════╝   ╚═╝   ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝      ╚═══╝  ╚══════╝
                      ADVANCED SYSTEM MONITOR v2.0                      
    [2025-07-04 14:30:45] [2d 14h 32m] [Arch Linux]

╔══════════════════════════════════════════════════════════════════════════════╗
║                              SYSTEM OVERVIEW                                ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ CPU:  42.3%  ║ Memory:  67.8%  ║ Load:     1.45 ║
║ ████████████ ║ ████████████    ║ Cores:       8 ║
╚══════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════╗
║                               CPU METRICS                                   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ USER:  25.5% │ SYSTEM:  15.2% │ IDLE:  59.3% │ IOWAIT:   2.0% ║
║ WEIGHTED:  42.3% │ EFFICIENCY:  78.5% │ THERMAL:  45.2°C      ║
║ ████████████████████ │ ████████████████████ │ ████████████████████ ║
║ TREND: ▲  +1.25 │ VOLATILITY:   8.3% │ PRESSURE:  15.8%     ║
╚══════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════╗
║                              MEMORY METRICS                                 ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ TOTAL:   16.0 GB │ USED:   10.8 GB │ AVAILABLE:    5.2 GB    ║
║ ████████████████████████████████████████████████████████████████████████████ ║
║ PRESSURE:  67.8% │ SWAP:    0.0% │ CACHE HIT:   94.2%        ║
║ ████████████████████ │ ░░░░░░░░░░░░░░░░░░░░ │ ████████████████████ ║
║ EFFICIENCY:  85.3% │ FRAGMENTATION:  12.1% │ OOM RISK:   8.5% ║
╚══════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════╗
║                            ADDITIONAL METRICS                               ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ NETWORK RX:   1234.5 MB │ TX:   567.8 MB │ INTERFACES:   3      ║
║ DISK: 350GB used │ 150GB available │ Usage:  70.0%           ║
║ PROCESSES:    245 │ TOP CPU:   25.5% │ LOAD AVG:     1.45    ║
╚══════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════╗
║ STATUS: OK         │ ALERTS:   0 │ UPTIME:      2d 14h 32m ║
╚══════════════════════════════════════════════════════════════════════════════╝

  [CTRL+C] Exit  [SPACE] Pause  [R] Reset  [H] Help

```

## FILES AND DIRECTORIES

- `~/.symon/`: Configuration directory
- `~/.symon/symon_config.json`: Main configuration file
- `~/.symon/profiles.json`: Custom profiles
- `system_usage_log.json`: Monitoring data log
- `system_history.json`: Historical data for trend analysis
- `system_alerts.log`: Alert notifications
- `lib/Symon/`: Perl modules for advanced calculations

## TROUBLESHOOTING

### Common Issues

1. **Permission denied for sensors**
   ```bash
   sudo usermod -a -G sensors $USER
   # Log out and back in
   ```

2. **Missing temperature data**
   ```bash
   # Run sensor detection
   sudo sensors-detect
   # Test sensors
   sensors
   ```

3. **High CPU usage from monitoring**
   ```bash
   # Use minimal profile
   ./symon_cli.pl --profile minimal
   # Or increase interval
   ./symon_cli.pl --interval 15
   ```

### Debugging

Enable verbose mode for detailed information:
```bash
./symon_cli.pl --verbose
```

Check configuration:
```bash
./symon_cli.pl --mode snapshot --format detailed
```

## ARCH LINUX SPECIFIC FEATURES

- Native systemd integration and process monitoring
- Pacman package manager awareness
- AUR package compilation detection
- Rolling release update monitoring
- Arch-specific thermal zone detection
- Custom kernel module monitoring
- Pacman cache and log analysis

## PERFORMANCE IMPACT

SYMON is designed to be lightweight with minimal system impact:
- Default profile: ~0.1% CPU usage
- Minimal profile: ~0.05% CPU usage
- Gaming profile: ~0.2% CPU usage (high frequency updates)
- Memory usage: ~5-10MB resident

## CONTRIBUTING

Areas for contribution:
- Additional platform support (FreeBSD, OpenBSD)
- New monitoring metrics and calculations
- Enhanced visualization and reporting
- Performance optimizations
- Additional export formats
- Integration with monitoring systems

## LICENSE

MIT License - see LICENSE file for details.

## DEPENDENCIES

### Core Perl Modules
- **JSON**: Configuration and data serialization
- **File::Slurp**: Fast file operations
- **Term::ANSIColor**: Color terminal output
- **Time::HiRes**: High-resolution timing
- **POSIX**: System functions and formatting
- **Sys::Info**: Cross-platform system information

### System Tools
- **lm-sensors** (Linux): Temperature monitoring
- **osx-cpu-temp** (macOS): Temperature monitoring
- **ps, top, df, iostat**: System utilities

---

**SYMON v2.0** - Advanced system monitoring with novel analysis methods for the modern era.
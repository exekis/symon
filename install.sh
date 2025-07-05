#!/bin/bash

# SYMON Installation Script

echo "SYMON - Advanced System Monitor Installation"
echo "==============================================="
echo ""

# check if we're on Arch Linux
if [ -f /etc/arch-release ] || [ -f /etc/pacman.conf ]; then
    echo "Detected Arch Linux"
    ARCH_LINUX=true
else
    echo "Detected Linux/Unix system"
    ARCH_LINUX=false
fi

echo "Checking system dependencies..."

# check for Perl
if ! command -v perl &> /dev/null; then
    echo "[ERROR] Perl is not installed. Please install Perl first."
    exit 1
fi

echo "[OK] Perl is installed"

if command -v cpanm &> /dev/null; then
    echo "[OK] cpanm is available"
    PERL_INSTALLER="cpanm"
elif command -v cpan &> /dev/null; then
    echo "[OK] cpan is available"
    PERL_INSTALLER="cpan"
else
    echo "[WARNING] Neither cpanm nor cpan found. Installing cpanm..."
    curl -L https://cpanmin.us | perl - App::cpanminus
    PERL_INSTALLER="cpanm"
fi

# Perl modules
PERL_MODULES=(
    "JSON"
    "File::Slurp"
    "Time::HiRes"
    "POSIX"
    "Sys::Info"
    "Sys::Info::OS"
    "Sys::Info::Device"
)

echo ""
echo "Installing required Perl modules..."
echo "======================================="

for module in "${PERL_MODULES[@]}"; do
    echo "Installing $module..."
    if [ "$PERL_INSTALLER" = "cpanm" ]; then
        cpanm "$module"
    else
        cpan "$module"
    fi
    
    if [ $? -eq 0 ]; then
        echo "[OK] $module installed successfully"
    else
        echo "[ERROR] Failed to install $module"
    fi
done

echo ""
echo "Installing system-specific dependencies..."
echo "==============================================="

if [ "$ARCH_LINUX" = true ]; then
    echo "Installing lm-sensors for temperature monitoring..."
    sudo pacman -S --needed lm-sensors
    
    echo "NOTE: To configure sensors, run: sudo sensors-detect"
    echo "NOTE: Then run: sensors"
    
elif command -v apt-get &> /dev/null; then
    echo "Installing lm-sensors for temperature monitoring..."
    sudo apt-get update
    sudo apt-get install -y lm-sensors
    
elif command -v yum &> /dev/null; then
    echo "Installing lm-sensors for temperature monitoring..."
    sudo yum install -y lm_sensors
    
elif command -v brew &> /dev/null; then
    echo "Installing osx-cpu-temp for temperature monitoring..."
    brew install osx-cpu-temp
    
else
    echo "[WARNING] Could not detect package manager. Please install temperature monitoring tools manually:"
    echo "   - Linux: lm-sensors package"
    echo "   - macOS: osx-cpu-temp via Homebrew"
fi

echo ""
echo "Installation complete!"
echo "========================="
echo ""
echo "To run SYMON:"
echo "  chmod +x system_monitor.pl"
echo "  ./system_monitor.pl"
echo ""
echo "Check README.md for detailed usage instructions"
echo "Configuration file will be created automatically on first run"
echo ""

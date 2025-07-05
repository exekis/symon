#!/usr/bin/perl

package Symon::Config;

use strict;
use warnings;
use JSON;
use File::Slurp;
use File::Spec;
use File::Path qw(make_path);


sub new {
    my ($class, $config_file) = @_;
    my $self = {
        config_file => $config_file || 'symon_config.json',
        config_dir => File::Spec->catdir($ENV{HOME}, '.symon'),
        config => {},
        profiles => {},
        current_profile => 'default',
    };
    
    bless $self, $class;
    $self->ensure_config_directory();
    $self->load_configuration();
    $self->load_profiles();
    return $self;
}

sub ensure_config_directory {
    my ($self) = @_;
    
    unless (-d $self->{config_dir}) {
        make_path($self->{config_dir}) or die "Cannot create config directory: $!";
    }
}

sub get_default_config {
    my ($self) = @_;
    
    return {
        monitor_interval => 5,
        duration => 0,
        quiet => 0,
        verbose => 0,
        
        theme => 'matrix',
        format => 'ascii',
        width => 80,
        height => 24,
        no_color => 0,
        
        cpu_alert_threshold => 90,
        memory_alert_threshold => 85,
        disk_alert_threshold => 90,
        temp_alert_threshold => 80,
        load_alert_threshold => 2.0,
        
        enable_alerts => 1,
        enable_network_monitoring => 1,
        enable_process_monitoring => 1,
        enable_disk_monitoring => 1,
        enable_predictions => 1,
        enable_history => 1,
        
        cpu_method => 'smart',
        cpu_weight_interactive => 2.0,
        cpu_weight_system => 1.5,
        cpu_weight_background => 0.8,
        cpu_weight_compute => 1.2,
        
        memory_method => 'pressure',
        memory_pressure_threshold => 80,
        swap_pressure_threshold => 50,
        cache_pressure_threshold => 20,
        
        max_history_entries => 1000,
        log_file => 'system_usage_log.json',
        history_file => 'system_history.json',
        alert_file => 'system_alerts.log',
        
        network_interfaces => 'auto',
        network_threshold_mbps => 100,
        
        max_processes => 10,
        process_cpu_threshold => 5.0,
        process_memory_threshold => 5.0,
        
        disk_mountpoints => 'auto',
        disk_io_threshold => 50,
        
        sampling_rate => 1.0,
        calculation_precision => 2,
        
        export_format => 'json',
        export_compression => 0,
        
        numa_monitoring => 1,
        thermal_monitoring => 1,
        power_monitoring => 1,
        scheduler_monitoring => 1,
    };
}

sub get_profile_configs {
    my ($self) = @_;
    
    return {
        'default' => {
            name => 'Default Profile',
            description => 'Balanced monitoring for general use',
            config => {
                monitor_interval => 5,
                cpu_method => 'smart',
                memory_method => 'pressure',
                theme => 'matrix',
                cpu_weight_interactive => 2.0,
                cpu_weight_system => 1.5,
                cpu_weight_background => 0.8,
                memory_pressure_threshold => 80,
                enable_all_features => 1,
            },
        },
        
        'server' => {
            name => 'Server Profile',
            description => 'Optimized for server monitoring',
            config => {
                monitor_interval => 10,
                cpu_method => 'smart',
                memory_method => 'pressure',
                theme => 'minimal',
                cpu_weight_interactive => 1.0,
                cpu_weight_system => 2.0,
                cpu_weight_background => 1.2,
                memory_pressure_threshold => 90,
                disk_alert_threshold => 95,
                enable_network_monitoring => 1,
                enable_process_monitoring => 1,
                max_processes => 20,
                format => 'minimal',
            },
        },
        
        'desktop' => {
            name => 'Desktop Profile',
            description => 'Desktop/workstation focused monitoring',
            config => {
                monitor_interval => 3,
                cpu_method => 'smart',
                memory_method => 'pressure',
                theme => 'cyber',
                cpu_weight_interactive => 3.0,
                cpu_weight_system => 1.0,
                cpu_weight_background => 0.5,
                memory_pressure_threshold => 75,
                temp_alert_threshold => 75,
                enable_predictions => 1,
                enable_history => 1,
                format => 'ascii',
            },
        },
        
        'gaming' => {
            name => 'Gaming Profile',
            description => 'Gaming performance monitoring',
            config => {
                monitor_interval => 1,
                cpu_method => 'smart',
                memory_method => 'pressure',
                theme => 'retro',
                cpu_weight_interactive => 4.0,
                cpu_weight_system => 1.0,
                cpu_weight_background => 0.3,
                memory_pressure_threshold => 85,
                temp_alert_threshold => 70,
                enable_predictions => 1,
                enable_history => 1,
                thermal_monitoring => 1,
                power_monitoring => 1,
                sampling_rate => 2.0,
                format => 'ascii',
            },
        },
        
        'minimal' => {
            name => 'Minimal Profile',
            description => 'Lightweight monitoring with minimal features',
            config => {
                monitor_interval => 15,
                cpu_method => 'traditional',
                memory_method => 'traditional',
                theme => 'minimal',
                enable_network_monitoring => 0,
                enable_process_monitoring => 0,
                enable_predictions => 0,
                enable_history => 0,
                thermal_monitoring => 0,
                power_monitoring => 0,
                numa_monitoring => 0,
                scheduler_monitoring => 0,
                format => 'minimal',
                quiet => 1,
            },
        },
        
        'developer' => {
            name => 'Developer Profile',
            description => 'Development and compilation monitoring',
            config => {
                monitor_interval => 2,
                cpu_method => 'smart',
                memory_method => 'pressure',
                theme => 'matrix',
                cpu_weight_interactive => 2.0,
                cpu_weight_system => 1.5,
                cpu_weight_background => 0.8,
                cpu_weight_compute => 2.0,
                memory_pressure_threshold => 80,
                enable_process_monitoring => 1,
                max_processes => 15,
                process_cpu_threshold => 2.0,
                enable_disk_monitoring => 1,
                disk_io_threshold => 30,
                format => 'ascii',
            },
        },
        
        'troubleshooting' => {
            name => 'Troubleshooting Profile',
            description => 'Maximum detail for system troubleshooting',
            config => {
                monitor_interval => 1,
                cpu_method => 'smart',
                memory_method => 'pressure',
                theme => 'cyber',
                verbose => 1,
                enable_all_features => 1,
                sampling_rate => 3.0,
                calculation_precision => 4,
                max_history_entries => 2000,
                max_processes => 25,
                numa_monitoring => 1,
                thermal_monitoring => 1,
                power_monitoring => 1,
                scheduler_monitoring => 1,
                format => 'detailed',
            },
        },
    };
}

sub load_configuration {
    my ($self) = @_;
    
    my $config_path = File::Spec->catfile($self->{config_dir}, $self->{config_file});
    
    if (-f $config_path) {
        eval {
            my $json_text = read_file($config_path);
            my $loaded_config = decode_json($json_text);
            $self->{config} = { %{$self->get_default_config()}, %$loaded_config };
        };
        if ($@) {
            warn "Failed to load configuration: $@\n";
            $self->{config} = $self->get_default_config();
        }
    } else {
        $self->{config} = $self->get_default_config();
        $self->save_configuration();
    }
}

sub load_profiles {
    my ($self) = @_;
    
    $self->{profiles} = $self->get_profile_configs();
    
    my $profiles_path = File::Spec->catfile($self->{config_dir}, 'profiles.json');
    if (-f $profiles_path) {
        eval {
            my $json_text = read_file($profiles_path);
            my $custom_profiles = decode_json($json_text);
            $self->{profiles} = { %{$self->{profiles}}, %$custom_profiles };
        };
        if ($@) {
            warn "Failed to load custom profiles: $@\n";
        }
    }
}

sub save_configuration {
    my ($self) = @_;
    
    my $config_path = File::Spec->catfile($self->{config_dir}, $self->{config_file});
    
    eval {
        my $json_text = encode_json($self->{config});
        write_file($config_path, $json_text);
    };
    if ($@) {
        warn "Failed to save configuration: $@\n";
    }
}

sub save_profiles {
    my ($self) = @_;
    
    my $profiles_path = File::Spec->catfile($self->{config_dir}, 'profiles.json');
    
    my %custom_profiles;
    my $builtin_profiles = $self->get_profile_configs();
    
    foreach my $profile_name (keys %{$self->{profiles}}) {
        unless (exists $builtin_profiles->{$profile_name}) {
            $custom_profiles{$profile_name} = $self->{profiles}{$profile_name};
        }
    }
    
    if (keys %custom_profiles) {
        eval {
            my $json_text = encode_json(\%custom_profiles);
            write_file($profiles_path, $json_text);
        };
        if ($@) {
            warn "Failed to save custom profiles: $@\n";
        }
    }
}

sub get_config {
    my ($self, $key) = @_;
    
    return $key ? $self->{config}{$key} : $self->{config};
}

sub set_config {
    my ($self, $key, $value) = @_;
    
    if (ref $key eq 'HASH') {
        $self->{config} = { %{$self->{config}}, %$key };
    } else {
        $self->{config}{$key} = $value;
    }
    
    $self->save_configuration();
}

sub apply_profile {
    my ($self, $profile_name) = @_;
    
    return 0 unless exists $self->{profiles}{$profile_name};
    
    my $profile = $self->{profiles}{$profile_name};
    my $profile_config = $profile->{config};
    
    $self->{config} = { %{$self->{config}}, %$profile_config };
    $self->{current_profile} = $profile_name;
    
    if ($profile_config->{enable_all_features}) {
        $self->{config}{enable_alerts} = 1;
        $self->{config}{enable_network_monitoring} = 1;
        $self->{config}{enable_process_monitoring} = 1;
        $self->{config}{enable_disk_monitoring} = 1;
        $self->{config}{enable_predictions} = 1;
        $self->{config}{enable_history} = 1;
        $self->{config}{numa_monitoring} = 1;
        $self->{config}{thermal_monitoring} = 1;
        $self->{config}{power_monitoring} = 1;
        $self->{config}{scheduler_monitoring} = 1;
    }
    
    $self->save_configuration();
    return 1;
}

sub get_profile {
    my ($self, $profile_name) = @_;
    
    return $profile_name ? $self->{profiles}{$profile_name} : $self->{profiles};
}

sub create_profile {
    my ($self, $profile_name, $profile_data) = @_;
    
    $self->{profiles}{$profile_name} = $profile_data;
    $self->save_profiles();
}

sub delete_profile {
    my ($self, $profile_name) = @_;
    
    # Don't delete built-in profiles
    my $builtin_profiles = $self->get_profile_configs();
    return 0 if exists $builtin_profiles->{$profile_name};
    
    delete $self->{profiles}{$profile_name};
    $self->save_profiles();
    return 1;
}

sub list_profiles {
    my ($self) = @_;
    
    my @profiles;
    foreach my $name (sort keys %{$self->{profiles}}) {
        my $profile = $self->{profiles}{$name};
        push @profiles, {
            name => $name,
            display_name => $profile->{name},
            description => $profile->{description},
            is_current => ($name eq $self->{current_profile}),
        };
    }
    
    return \@profiles;
}

sub validate_config {
    my ($self) = @_;
    
    my @errors;
    my $config = $self->{config};
    
    if ($config->{monitor_interval} < 1 || $config->{monitor_interval} > 300) {
        push @errors, "monitor_interval must be between 1 and 300 seconds";
    }
    
    if ($config->{cpu_alert_threshold} < 0 || $config->{cpu_alert_threshold} > 100) {
        push @errors, "cpu_alert_threshold must be between 0 and 100";
    }
    
    if ($config->{memory_alert_threshold} < 0 || $config->{memory_alert_threshold} > 100) {
        push @errors, "memory_alert_threshold must be between 0 and 100";
    }
    
    if ($config->{disk_alert_threshold} < 0 || $config->{disk_alert_threshold} > 100) {
        push @errors, "disk_alert_threshold must be between 0 and 100";
    }
    
    if ($config->{temp_alert_threshold} < 0 || $config->{temp_alert_threshold} > 150) {
        push @errors, "temp_alert_threshold must be between 0 and 150";
    }
    
    my @valid_cpu_methods = qw(smart traditional weighted);
    unless (grep { $_ eq $config->{cpu_method} } @valid_cpu_methods) {
        push @errors, "cpu_method must be one of: " . join(', ', @valid_cpu_methods);
    }
    
    my @valid_memory_methods = qw(pressure traditional available);
    unless (grep { $_ eq $config->{memory_method} } @valid_memory_methods) {
        push @errors, "memory_method must be one of: " . join(', ', @valid_memory_methods);
    }
    
    my @valid_themes = qw(matrix cyber retro minimal);
    unless (grep { $_ eq $config->{theme} } @valid_themes) {
        push @errors, "theme must be one of: " . join(', ', @valid_themes);
    }
    
    my @valid_formats = qw(ascii minimal detailed);
    unless (grep { $_ eq $config->{format} } @valid_formats) {
        push @errors, "format must be one of: " . join(', ', @valid_formats);
    }
    
    return @errors;
}

sub get_config_summary {
    my ($self) = @_;
    
    my $config = $self->{config};
    
    return {
        profile => $self->{current_profile},
        interval => $config->{monitor_interval},
        theme => $config->{theme},
        format => $config->{format},
        cpu_method => $config->{cpu_method},
        memory_method => $config->{memory_method},
        features => {
            alerts => $config->{enable_alerts},
            network => $config->{enable_network_monitoring},
            processes => $config->{enable_process_monitoring},
            disk => $config->{enable_disk_monitoring},
            predictions => $config->{enable_predictions},
            history => $config->{enable_history},
        },
        thresholds => {
            cpu => $config->{cpu_alert_threshold},
            memory => $config->{memory_alert_threshold},
            disk => $config->{disk_alert_threshold},
            temperature => $config->{temp_alert_threshold},
        },
    };
}

sub reset_to_defaults {
    my ($self) = @_;
    
    $self->{config} = $self->get_default_config();
    $self->{current_profile} = 'default';
    $self->save_configuration();
}

sub export_config {
    my ($self, $filename) = @_;
    
    my $export_data = {
        config => $self->{config},
        current_profile => $self->{current_profile},
        timestamp => time(),
        version => '2.0',
    };
    
    eval {
        my $json_text = encode_json($export_data);
        write_file($filename, $json_text);
    };
    if ($@) {
        warn "Failed to export configuration: $@\n";
        return 0;
    }
    
    return 1;
}

sub import_config {
    my ($self, $filename) = @_;
    
    return 0 unless -f $filename;
    
    eval {
        my $json_text = read_file($filename);
        my $import_data = decode_json($json_text);
        
        if ($import_data->{config}) {
            $self->{config} = { %{$self->get_default_config()}, %{$import_data->{config}} };
            $self->{current_profile} = $import_data->{current_profile} || 'default';
            $self->save_configuration();
        }
    };
    if ($@) {
        warn "Failed to import configuration: $@\n";
        return 0;
    }
    
    return 1;
}

1;

__END__

=head1 NAME

Symon::Config - Configuration management for SYMON system monitor

=head1 SYNOPSIS

    use Symon::Config;
    
    my $config = Symon::Config->new('symon_config.json');
    $config->apply_profile('gaming');
    my $interval = $config->get_config('monitor_interval');

=head1 DESCRIPTION

This module provides comprehensive configuration management for SYMON, including:

- Default configuration generation
- Profile management (server, desktop, gaming, etc.)
- Configuration validation
- Import/export functionality
- Automatic configuration directory creation

=head1 PROFILES

Built-in profiles include:
- default: Balanced monitoring
- server: Server-optimized monitoring
- desktop: Desktop/workstation focused
- gaming: Gaming performance monitoring
- minimal: Lightweight monitoring
- developer: Development-focused monitoring
- troubleshooting: Maximum detail monitoring

=head1 METHODS

=head2 new($config_file)

Creates a new Config instance and loads configuration.

=head2 apply_profile($profile_name)

Applies a monitoring profile to the current configuration.

=head2 get_config($key)

Gets a configuration value or entire configuration hash.

=head2 set_config($key, $value)

Sets a configuration value and saves to disk.

=head1 AUTHOR

System Monitor Team

=head1 LICENSE

MIT License

=cut

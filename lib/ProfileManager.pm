package ProfileManager;

use strict;
use warnings;
use JSON;
use File::Slurp;


my %profiles = (
    'default' => {
        interval => 5,
        cpu_method => 'smart',
        memory_method => 'pressure',
        enable_network => 1,
        enable_processes => 1,
        enable_alerts => 1,
        theme => 'default',
        format => 'ascii',
        description => 'Balanced monitoring for general use',
    },
    'server' => {
        interval => 10,
        cpu_method => 'smart',
        memory_method => 'pressure',
        enable_network => 1,
        enable_processes => 1,
        enable_alerts => 1,
        theme => 'minimal',
        format => 'minimal',
        description => 'Server monitoring with network focus',
    },
    'desktop' => {
        interval => 3,
        cpu_method => 'smart',
        memory_method => 'pressure',
        enable_network => 0,
        enable_processes => 1,
        enable_alerts => 1,
        theme => 'cyber',
        format => 'ascii',
        description => 'Desktop monitoring with user focus',
    },
    'gaming' => {
        interval => 1,
        cpu_method => 'smart',
        memory_method => 'pressure',
        enable_network => 0,
        enable_processes => 1,
        enable_alerts => 1,
        theme => 'matrix',
        format => 'detailed',
        description => 'High-frequency gaming performance monitoring',
    },
    'minimal' => {
        interval => 30,
        cpu_method => 'basic',
        memory_method => 'basic',
        enable_network => 0,
        enable_processes => 0,
        enable_alerts => 0,
        theme => 'minimal',
        format => 'minimal',
        description => 'Minimal resource usage monitoring',
    },
    'developer' => {
        interval => 5,
        cpu_method => 'smart',
        memory_method => 'pressure',
        enable_network => 1,
        enable_processes => 1,
        enable_alerts => 1,
        theme => 'retro',
        format => 'detailed',
        description => 'Development environment monitoring',
    },
    'troubleshooting' => {
        interval => 1,
        cpu_method => 'smart',
        memory_method => 'pressure',
        enable_network => 1,
        enable_processes => 1,
        enable_alerts => 1,
        theme => 'default',
        format => 'detailed',
        description => 'Maximum detail for troubleshooting',
    },
);

sub load_profile {
    my ($profile_name) = @_;
    
    return $profiles{$profile_name} if exists $profiles{$profile_name};
    
    my $profile_file = "profiles/${profile_name}.json";
    if (-f $profile_file) {
        eval {
            my $json_text = read_file($profile_file);
            return decode_json($json_text);
        };
        if ($@) {
            warn "Failed to load profile file: $@\n";
        }
    }
    
    return undef;
}

sub save_profile {
    my ($profile_name, $profile_data) = @_;
    
    mkdir "profiles" unless -d "profiles";
    
    my $profile_file = "profiles/${profile_name}.json";
    
    eval {
        write_file($profile_file, encode_json($profile_data));
    };
    if ($@) {
        warn "Failed to save profile: $@\n";
        return 0;
    }
    
    return 1;
}

sub list_profiles {
    my @available_profiles;
    
    foreach my $profile_name (keys %profiles) {
        push @available_profiles, {
            name => $profile_name,
            type => 'built-in',
            description => $profiles{$profile_name}{description},
        };
    }
    
    if (-d "profiles") {
        opendir(my $dh, "profiles");
        while (my $file = readdir($dh)) {
            next unless $file =~ /^(.+)\.json$/;
            my $profile_name = $1;
            
            next if exists $profiles{$profile_name};
            
            push @available_profiles, {
                name => $profile_name,
                type => 'custom',
                description => 'Custom profile',
            };
        }
        closedir($dh);
    }
    
    return @available_profiles;
}

sub create_profile {
    my ($name, $base_profile, $overrides) = @_;
    
    $base_profile ||= 'default';
    $overrides ||= {};
    
    my $base_config = $profiles{$base_profile} || $profiles{'default'};
    my %new_profile = (%$base_config, %$overrides);
    
    return save_profile($name, \%new_profile);
}

sub delete_profile {
    my ($profile_name) = @_;
    
    return 0 if exists $profiles{$profile_name};
    
    my $profile_file = "profiles/${profile_name}.json";
    return 0 unless -f $profile_file;
    
    return unlink($profile_file);
}

sub get_profile_info {
    my ($profile_name) = @_;
    
    my $profile = load_profile($profile_name);
    return undef unless $profile;
    
    return {
        name => $profile_name,
        interval => $profile->{interval},
        cpu_method => $profile->{cpu_method},
        memory_method => $profile->{memory_method},
        theme => $profile->{theme},
        format => $profile->{format},
        description => $profile->{description},
        features => {
            network => $profile->{enable_network},
            processes => $profile->{enable_processes},
            alerts => $profile->{enable_alerts},
        },
    };
}

sub validate_profile {
    my ($profile_data) = @_;
    
    my @required_fields = qw(interval cpu_method memory_method theme format);
    
    foreach my $field (@required_fields) {
        return 0 unless exists $profile_data->{$field};
    }
    
    return 0 unless $profile_data->{interval} >= 1 && $profile_data->{interval} <= 300;
    
    my @valid_cpu_methods = qw(basic smart);
    my @valid_memory_methods = qw(basic pressure);
    
    return 0 unless grep { $_ eq $profile_data->{cpu_method} } @valid_cpu_methods;
    return 0 unless grep { $_ eq $profile_data->{memory_method} } @valid_memory_methods;
    
    my @valid_themes = qw(default matrix cyber retro minimal);
    my @valid_formats = qw(ascii minimal detailed);
    
    return 0 unless grep { $_ eq $profile_data->{theme} } @valid_themes;
    return 0 unless grep { $_ eq $profile_data->{format} } @valid_formats;
    
    return 1;
}

1;

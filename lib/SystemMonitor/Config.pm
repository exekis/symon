package SystemMonitor::Config;

use strict;
use warnings;
use JSON;

sub new {
    my ($class) = @_;
    my $self = {
        config => {
            monitor_interval => 5,
            cpu_alert_threshold => 90,
            memory_alert_threshold => 85,
            disk_alert_threshold => 90,
            temp_alert_threshold => 80,
            log_file => "system_usage_log.json",
            enable_alerts => 1,
            enable_network_monitoring => 1,
            max_history_entries => 1000,
        }
    };
    
    bless $self, $class;
    $self->load_config();
    return $self;
}

sub load_config {
    my ($self) = @_;
    
    my $config_file = "symon_config.json";
    return unless -f $config_file;
    
    eval {
        open my $fh, '<', $config_file or die "Cannot open config file: $!";
        my $json_text = do { local $/; <$fh> };
        close $fh;
        
        my $loaded_config = decode_json($json_text);
        %{$self->{config}} = (%{$self->{config}}, %$loaded_config);
    };
    
    warn "Failed to load config: $@" if $@;
}

sub get {
    my ($self, $key) = @_;
    return $self->{config}{$key};
}

sub set {
    my ($self, $key, $value) = @_;
    $self->{config}{$key} = $value;
}

sub save_config {
    my ($self) = @_;
    
    my $config_file = "symon_config.json";
    eval {
        open my $fh, '>', $config_file or die "Cannot write config file: $!";
        print $fh encode_json($self->{config});
        close $fh;
    };
    
    warn "Failed to save config: $@" if $@;
}

1;

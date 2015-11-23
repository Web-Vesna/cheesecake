package CakeConfig;

use strict;
use warnings;

use base qw( Exporter );

use JSON::XS;

use Logger;

our @EXPORT_OK = qw(
	read_config
	config
	service
);

our @EXPORT = @EXPORT_OK;

{
	our %Config = ();
	our $logger = Logger->new("Config");

	sub parse_schema {
		my ($cfg, $param_name, $str) = @_;

		my $parser = JSON::XS->new;
		my $decoded = undef;
		eval {
			$decoded = $parser->decode($str);
		};

		return "JSON parse error: $@"
			if $@ || !$decoded;

		return "JSON parse error: object is expected"
			if !ref $decoded || ref $decoded ne 'HASH';

		return "table_name is required in JSON"
			unless $decoded->{table_name};

		return "columns list is required in JSON"
			unless $decoded->{columns};

		return "columns is is not a list in JSON"
			unless ref $decoded->{columns} && ref $decoded->{columns} eq 'ARRAY';

		my %required_types = map { $_ => 1 } qw( userid login pass );
		my %_required_types = map { $_ => 1 } qw( userid login pass );
		my %types = map { $_ => 1 } qw( int str email );
		my @columns;

		for (@{$decoded->{columns}}) {
			return "invalid column specification: object is required"
				unless ref $_ && ref $_ eq 'HASH';

			return "both, name and type items required in column specification"
				unless $_->{name} && $_->{type};

			return "unknown type: '$_->{type}'"
				unless $types{$_->{type}};

			return "unknown col_type: '$_->{col_type}'"
				if defined $_->{col_type} && !$_required_types{$_->{col_type}};

			return "only one col_type is required in a columns list: '$_->{col_type}'"
				if defined $_->{col_type} && !$required_types{$_->{col_type}};

			return "unknown required value for $_->{name}: '$_->{required}': bool is expected"
				if defined $_->{required} && (!ref $_->{required} || ref $_->{required} ne 'JSON::PP::Boolean');

			delete $required_types{$_->{col_type}}
				if $_->{col_type};

			push @columns, {
				name => $_->{name},
				type => $_->{type},
				col_type => $_->{col_type},
				required => ($_->{required} ? 1 : 0),
			};
		}

		return "all coll types, " . join(', ', keys %_required_types) . " are required"
			if %required_types;

		$cfg->{$param_name} = {
			table_name => $decoded->{table_name},
			columns => \@columns,
		};

		return undef;
	}

	# XXX: 'default' is not capable with 'cb'
	our %ConfigSpec = (
		listen => {
			type => 'string',
			cb => sub {
				my ($cfg, $param_name, $str) = @_;
				return "unexpected format"
					unless $str =~ /^([^:]+):(\d+)$/;
				@{$cfg->{listen}}{qw( host port )} = ($1, $2);
				$logger->debug("Listening $str");
				return undef;
			},
		},
		user => {
			type => 'string',
			cb => sub {
				my ($cfg, $param_name, $str) = @_;
				return "no such user"
					unless getpwnam $str;
				$cfg->{user}{name} = $str;
				$logger->debug("User is $str");
				return undef;
			},
		},
		group => {
			type => 'string',
			cb => sub {
				my ($cfg, $param_name, $str) = @_;
				return "no such group"
					unless getgrnam $str;
				$cfg->{user}{group} = $str;
				$cfg->{group} = { need_delete => 1 }; # to be valid on conf check
				$logger->debug("Group is $str");
				return undef;
			},
		},

		service => {
			enabled => {
				type => 'int',
			},
			db_host => {
				type => 'string',
			},
			db_port => {
				type => 'int',
			},
			db_user => {
				type => 'string',
			},
			db_password => {
				type => 'string',
			},
			db_name => {
				type => 'string',
			},
			db_schema => {
				type => 'string',
				cb => \&parse_schema,
			},
			memc_host => {
				type => 'string',
			},
			memc_port => {
				type => 'int',
			},
			memc_prefix => {
				type => 'string',
				default => '',
			},
			session_expire_time => {
				type => 'int',
				default => 60 * 60 * 24,
			},
			secrets => {
				type => 'list',
			},
		},
	);

	sub read_config {
		my $cfg_name = shift;

		open my $f, '<', $cfg_name
			or die "Can't open $cfg_name: $!\n";

		my %cfg;
		while (<$f>) {
			chomp;

			s/^([^#]*)#.*$/$1/;
			s/\s+//g;

			$logger->trace("Parsing config line '$_'");

			next if /^$/;

			if ($_ !~ /=/ || /^=/) {
				$logger->err("Invalid option format: '$_'");
				next;
			}

			my ($param_name, $param_val, @tail) = split '=';
			if (@tail) {
				$logger->err("Invalid option format: '$_'");
				next;
			}

			if ($ConfigSpec{$param_name}) {
				parse_arg(\%cfg, $param_name, $param_val, $ConfigSpec{$param_name});
			} elsif ($param_name =~ /^([^_]+)_(.+)$/) {
				my $spec = $ConfigSpec{service};
				unless ($spec->{$2}) {
					$logger->err("Unknown option: '$param_name'");
					next;
				}

				$logger->debug("Initializing service '$1' ($2)");
				parse_arg(($cfg{services}{$1} //= {}), $2, $param_val, $spec->{$2});
			} else {
				$logger->err("Unknown option: '$param_name'");
			}
		}

		%Config = %cfg
			if check_config(\%cfg);
	}

	sub parse_arg {
		my ($cfg, $param_name, $param_val, $spec) = @_;

		$param_val //= "";
		$logger->trace("Parsing arg '$param_name' ($param_val)");

		if ($spec->{type} eq 'int' && (length($param_val) == 0 || $param_val =~ /\D/)) {
			$logger->err("Unexpected value for '$param_name': '$param_val' (integer is expected)");
			return;
		}

		if ($spec->{cb}) {
			if (my $err = $spec->{cb}($cfg, $param_name, $param_val)) {
				$logger->err("Can't parse '$param_name' ($param_val): $err\n");
			}
			return;
		}

		if ($spec->{type} eq 'list') {
			$cfg->{$param_name} = [ split ',', $param_val ];
			$logger->debug("Parsed arg: '$param_name' = [" . join(', ', @{$cfg->{$param_name}}) . "]");
			return;
		}

		$cfg->{$param_name} = $param_val;
		$logger->debug("Parsed arg: '$param_name' = '" . $param_val . "'");
	}

	sub check_config {
		my $config = shift;

		for (keys %ConfigSpec) {
			next if /^service$/;
			unless (defined $config->{$_}) {
				if ($ConfigSpec{$_}{default}) {
					$config->{$_} = $ConfigSpec{$_}{default};
					next;
				}
				$logger->err("Option '$_' is not found in config. Skip config loading.\n");
				return undef;
			}
		}

		my $spec = $ConfigSpec{service};
		my $svcs = $config->{services} // {};

		my %services;
		for my $svc (keys %$svcs) {
			unless ($svcs->{$svc}{enabled}) {
				# dirty hack =)
				next;
			}

			for (keys %$spec) {
				unless (defined $svcs->{$svc}{$_}) {
					if ($spec->{$_}{default}) {
						$svcs->{$svc}{$_} = $spec->{$_}{default};
						next;
					}
					$logger->err("Option $_ for service $svc wasn't found in config");
					return undef;
				}
			}

			$services{$svc} = $svcs->{$svc};
		}

		unless (%services) {
			$logger->err("At least one service is required");
			return undef;
		}

		$config->{services} = \%services;
		return 1;
	}

	sub config {
		die "Config wasnt read\n"
			unless %Config;

		\%Config;
	}

	sub service {
		return config->{services}{$_[0]};
	}
}

1;

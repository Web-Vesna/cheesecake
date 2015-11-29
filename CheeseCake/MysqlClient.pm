package MysqlClient;

use strict;
use warnings;

use Logger;
use CakeConfig qw( service );

use Mail::RFC822::Address ();

use List::Util qw( first );
use AnyEvent;
use DBI;

my %connections;

sub new {
	my ($class, $service_name, $packet_id) = @_;

	my $self = bless {
		logger => Logger->new("MysqlClient", $service_name, $packet_id),
	}, $class;

	unless ($connections{$service_name}) {
		$self->establish_connection($service_name);
	}

	$self->{conn} = $connections{$service_name};

	return $self;
}

sub logger {
	return shift->{logger};
}

sub schema {
	return shift->{conn}{cols_list};
}

sub extra_col {
	my ($self, $ecol_name) = @_;
	return $self->{conn}{extra_cols}{$ecol_name . "_col"};
}

sub establish_connection {
	my ($self, $service_name) = @_;

	$self->logger->info("Initialization of a service connection");
	my ($host, $port, $user, $pass, $name, $schema) =
		@{service($service_name)}{qw( db_host db_port db_user db_password db_name db_schema )};

	my $conn_str = "DBI:mysql:database=$name:host=$host:port=$port";
	my $dbh = DBI->connect($conn_str, $user, $pass, {
		PrintError => 1,
		RaiseError => 1,
		mysql_auto_reconnect => 1,
	});

	my $find_by_type = sub {
		my $type = shift;
		my $found = first { $_->{col_type} eq $type } @{ $schema->{columns} };
		die "Can't find column of type $type for $service_name service!!!\n"
			unless $found;

		return $found->{name};
	};

	my %table_prefs = (
		uid_col => $find_by_type->('userid'),
		login_col => $find_by_type->('login'),
		pass_col => $find_by_type->('pass'),
	);

	my @cols_list = map { $_->{name} } grep { !$_->{col_type} || $_->{col_type} ne 'userid' } @{ $schema->{columns} };

	my $extra_request = sub {
		my $col = shift;
		# don't know why, but can't inline =(
		return "select_by_unique__$col->{name}" => {
			r => "select $col->{name} from $schema->{table_name} where $col->{name} = ?",
			p => [ $col->{name} ],
		}
	};

	$connections{$service_name} = {
		dbh => $dbh,
		queue => [],
		cols_list => $schema->{columns},
		extra_cols => \%table_prefs,
		requests => {
			select_by_uid => {
				r => "select * from $schema->{table_name} where $table_prefs{uid_col} = ?",
				p => [ $table_prefs{uid_col} ],
			},
			select_by_login => {
				r => "select * from $schema->{table_name} where $table_prefs{login_col} = ?",
				p => [ $table_prefs{login_col} ],
			},
			check_pass => {
				# TODO: make a password encryption
				r => "select * from $schema->{table_name} where $table_prefs{login_col} = ? and $table_prefs{pass_col} = ?",
				p => [ $table_prefs{login_col}, $table_prefs{pass_col} ],
			},
			add_row => {
				r => "insert into $schema->{table_name} (" . join(', ', @cols_list) . ") values (" . join(', ', map { '?' } @cols_list) . ")",
				p => [ @cols_list ],
			},
			change_row => {
				r => "update $schema->{table_name} set " . join(', ', map { "$_ = ?" } @cols_list) . " where $table_prefs{uid_col} = ?",
				p => [ @cols_list, $table_prefs{uid_col} ],
			},
			# a couple extra requests
			map { $extra_request->($_) } grep { $_->{unique} } @{ $schema->{columns} },
		},
	};
}

sub queue_up {
	my ($self, $request_name, $callback, %args) = @_;

	# args is a list of pairs 'column_name' => 'value'
	my $c = $self->{conn};
	my $r = $c->{requests}{$request_name};

	$self->logger->info("Trying to execute '$request_name' with args " . join(', ', map { "'$_' = '$args{$_}'" } sort keys %args));

	unless ($r) {
		$self->logger->err("Failed to execute '$request_name': request not found");
		return $callback->(undef, 'unknown request');
	}

	my @args = @args{@{ $r->{p} }};
	if (scalar(@args) != scalar(@{ $r->{p} })) {
		$self->logger->err("Failed to execute '$request_name': invalid number of arguments: " .
			scalar(@{ $r->{p} }) . " expected, " . scalar(@args) . " found");
		return $callback->(undef, 'invalid args');
	}

	$r->{sth} //= $c->{dbh}->prepare($r->{r}, { async => 1 });
	push @{$c->{queue}}, {
		sth => $r->{sth},
		args => [ @args ],
		cb => $callback,
		r_name => $request_name,
		r => $r->{r},
	};

	$self->process_queue;
}

sub process_queue {
	my $self = shift;

	my $c = $self->{conn};
	return if $c->{watcher};

	my $process_next;
	$process_next = sub {
		my $req = shift @{ $c->{queue} };
		unless ($req) {
			$self->logger->info("Queue is empty");
			delete $c->{watcher} unless $req;
			return undef;
		}

		$self->logger->info("Sending request '$req->{r_name}' to mysql");
		if (Logger::log_lvl() eq 'trace') {
			my $req_str = $req->{r};
			my @args = @{$req->{args}};
			my $x;
			do { $x = shift @args; } while ($req_str =~ s/\?/'$x'/);
			$self->logger->trace("MySQL> $req_str");
		}

		unless ($req->{sth}->execute(@{$req->{args}})) {
			$req->{cb}->(undef, $req->{sth}->errstr);
			return $process_next->();
		}
		return $req;
	};

	my $req = $process_next->();
	return unless $req;

	$c->{watcher} = AnyEvent->io(
		fh	=> $c->{dbh}->mysql_fd,
		poll	=> 'r',
		cb	=> sub {
			$self->logger->trace("Got response for '$req->{r_name}' from mysql");

			my @result;
			# use mysql_async_result instead ?
			while (my $row = $req->{sth}->fetchrow_hashref) {
				if (ref $row && ref $row eq 'HASH') {
					for (keys %{$c->{extra_cols}}) {
						my ($name) = /^(.*)_col/;
						$row->{$name} = delete $row->{$c->{extra_cols}{$_}}
							if $row->{$c->{extra_cols}{$_}};
					}
				}
				push @result, $row;
			}

			$req->{cb}->(\@result);
			$req = $process_next->();
		},
	);
}

sub select {
	# $callback->($response, $error)
	my ($self, $key, $val, $callback) = @_;
	my ($request_name, $col_name) = @{{
		uid	=> [ 'select_by_uid', $self->{conn}{extra_cols}{uid_col}, ],
		login	=> [ 'select_by_login', $self->{conn}{extra_cols}{login_col}, ],
	}->{$key}};

	unless ($request_name) {
		$self->logger->err("Invalid key came to select request '$key': 'uid' or 'login' are expected");
		return $callback(undef, 'invalid request');
	}

	$self->queue_up($request_name, $callback, $col_name => $val);
}

sub check_unique {
	# $callback->($err); $err is undefined unless row exists
	my ($self, $colname, $value, $cb) = @_;

	$self->queue_up("select_by_unique__$colname", sub {
		my ($response, $err) = @_;
		return $cb->($err)
			if $err;

		return $cb->()
			unless $response;

		return $cb->("user with $colname '$response->{$colname}' is already exists")
			if $response->{$colname};

		return $cb->();
	}, $colname => $value);
}

sub check_pass {
	# $callback->($response, $error)
	my ($self, $login, $pass, $callback) = @_;

	my $c = $self->{conn}{extra_cols};
	$self->queue_up('check_pass', $callback, $c->{login_col} => $login, $c->{pass_col} => $pass);
}

sub check_cols {
	my ($given, $expected) = @_;

	for my $col (@$expected) {
		next # error will be processed later if col is required
			unless defined $given->{$col->{name}};
		return "$col->{name} should be integer"
			if $col->{type} eq 'int' && $given->{$col->{name}} =~ /\D/;
		return "$col->{name} should be email"
			if $col->{tyepe} eq 'email' && !Mail::RFC822::Address::valid($given->{$col->{name}});
	}

	return undef;
}

sub insert_replace {
	# $callback->($error)
	my ($self, $type, @args) = @_;

	my $fname = {
		insert => 'add_row',
		replace => 'change_row',
	}->{$type};

	my $cb = pop @args;
	unless ($fname) {
		$self->logger->err("Invalid request type found: '$type'");
		return $cb->("invalid request");
	}

	if (my $err = check_cols({ @args }, $self->{conn}{cols_list})) {
		$self->logger->err("Invalid arguments types: $err");
		return $cb->($err);
	}

	$self->queue_up($fname, sub {
		my ($data, $error) = @_;
		# ignore data
		$cb->($error);
	}, @args);
}

sub insert {
	# $callback->($last_insert_id, $error)
	my ($self, @args) = @_;
	my $cb = pop @args;

	$self->insert_replace('insert', @args, sub {
		my $err = shift;
		return $cb->(undef, $err) if $err;

		return $cb->($self->{conn}{dbh}{mysql_insertid});
	});
}

sub replace {
	# $callback->($error)
	insert_replace('replace', @_);
}

1;

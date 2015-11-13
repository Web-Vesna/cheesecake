=head1 NAME

Cheesecake -- a simple async authorization server.

=head1 SYNOPSIS

main.pl [options]

  Options:
    --config|-c         config file path;
    --help|-h           brief help message;
    --man|-m            show full documentation;

=head1 OPTIONS

=over 8

=item B<--config>

Config file path.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Show full documentation for a product.

=back

=head1 DESCRIPTION

Daemon implements session mechanism for a couple projects.

=head2 Config file specification

All options in the configuration file should be presented in the following format:

=over 8

E<lt>option_nameE<gt> = E<lt>option_valueE<gt>

=back

The '#' symbol starts a comment. All symbols after '#' will be ignored. No new lines are expected in one argument specification.

=head3 Common options

Following configuration options are expected:

=over 8

=item B<listen>

Listen specified host and port. Following format is expected:

E<lt>hostE<gt>:E<lt>portE<gt>

This parametr is required.

=item B<user>

Daemon will be started with given user privileges. Default is I<nobody>.

=item B<group>

Daemon will be started with given group privileges. Default is I<nogroup>.

=back

=head3 Service-specific options

This part of config file specifies a list of services supported by cheesecake. All options starts from the service name (see example below).

Following service-specific options are supported. All options are required unless otherwise specified.

=over 8

=item B<E<lt>serviceE<gt>_enabled>

Service enable status. Integer number, B<1> or B<0>. Every service is disabled by default.

=item B<E<lt>serviceE<gt>_db_host>

=item B<E<lt>serviceE<gt>_db_port>

=item B<E<lt>serviceE<gt>_db_user>

=item B<E<lt>serviceE<gt>_db_password>

=item B<E<lt>serviceE<gt>_db_name>

Service database parametrs. String.

The database should contains a table B<users> with specified by B<login> request format (see below). The B<id> column as a primary key is required.

=item B<E<lt>serviceE<gt>_memc_host>
=item B<E<lt>serviceE<gt>_memc_port>

Memcached server options. This server will be used to store an authorized sessions.

=item B<E<lt>serviceE<gt>_memc_prefix>

This string will be used as a prefix in memcached.

=item B<E<lt>serviceE<gt>_session_expire_time>

Memcached session expire time. All sessions expiration times will be updated on every request call. This time specifies maximum inactivity time (in seconds).

=item B<E<lt>serviceE<gt>_secrets>

A comma-separated list of registered clients secrets (see authorization packet specification below).

=back

=head2 Protocol specification

Daemon expects a L<CBOR|http://cbor.io/> packets. Daemon will return a CBOR packet as a reply.

All packets should be represented as an array with the format, specified below. But every have a I<packet_id> as first element.

The packet_id  is a random integer number required to enumerate packets over async mechanism.

This number will be returned to client in response also as a first argument.

=head3 Authorization packet specification

Daemon expects as a first packet with the following structure:

=over 16

[ packet_id, client_name, client_seret ]

=back

=over 8

=item B<client_name>

The client name is a string, specified as a B<service_name> in configuration file. This service should be enabled in configuration.

If this service is not presented in config, this client will be banned.

=item B<client_secret>

This string value should be presented in the B<E<lt>serviceE<gt>_secrets> configuration option.

If there is no such client secret presented in config, this client will be banned.

=back

"The client is banned" means, that an error packet will be sent in response and the connection will be force closed.

The response packet have following format:

=over 16

[ packet_id, status, error_message ]

=back

Status field will be set to B<0> on error and to B<1> otherwise. The error message is not presented in success response.

=head3 Common packet specification

Daemon expects input with following structure (json interpretarion):

=over 16

[ packet_id, function_name, arguments ]

=back

=over 8

=item B<function_name>

This is a unique function name (string) to be called. All functions expects individual number of arguments (see below).

=item B<arguments>

This is a number of function-specific argumets.

=back

Daemon will return foolowin packet in response (also CBOR encoded):

=over 16

[ packet_id, status, arguments ]

=back

The I<packet_id> argument will be simply taken from a request.

The I<status> argument can be B<1> on request success and B<0> on request fail.

If the request was failed, the third argument will be a message (string) which explains an error.

Following functions are expected:

=over 8

=item B<check>

Check the session existance. Session id should be given as argument (string).

Daemon will just return a status B<1> if the session exists and B<0> otherwise. See return packet format below for more information.

=item B<about>

Check the session existance and return a session information. Session id should be given as argument (string).

Daemon will return a hash (as a third argument) with a format, specified by a configuration file (see below).

=item B<login>

The request will try to authorize a user with given parametrs (a hash element in third argument).

If success, the method will return a session id.

All options, specified as a required login options (see cofiguration file specification below) should present in the parametrs.

=item B<logout>

The request will try to close a session with given in third argument id.

The 4th integer argument is optional.

If 1 is given, the system will try to close all session of the specified user. Otherwise the system will close only given session.

=item B<register>

The request will try to register a user with specified parametrs (third hash argument).

All options, specified as required for register request (see cofiguration file specification below) should present in parametrs.

=back

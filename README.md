# NAME

Cheesecake -- a simple async authorization server.

# SYNOPSIS

main.pl \[options\]

    Options:
      --config|-c         config file path;
      --log_level|-l      log level;
      --no_auth|-n        don't expect auth packets;
      --json|-j           use JSON instead of CBOR;
      --help|-h           brief help message;
      --man|-m            show full documentation;

# INSTALL

To generate a Makefile run

> perl Makefile.pl

All dependences will be downloaded and installed automatically. Then type

> make && make install

to install a module.

# OPTIONS

- **--config**

    Config file path.

- **--log\_level**

    Daemon log level. Integer number 1..5 is expected. **1** means error logs, **5** -- trace.

- **--no\_auth**

    Daemon will not expects auth packets. Foe debug purposes needed.

- **--json**

    Use JSON as an encoder instead of CBOR. For debug purposes.

- **--help**

    Print a brief help message and exit.

- **--man**

    Show full documentation for a product.

# DESCRIPTION

Daemon implements session mechanism for a couple projects.

## Config file specification

All options in the configuration file should be presented in the following format:

> &lt;option\_name> = &lt;option\_value>

The '#' symbol starts a comment. All symbols after '#' will be ignored. No new lines are expected in one argument specification.

### Common options

Following configuration options are expected:

- **listen**

    Listen specified host and port. Following format is expected:

    &lt;host>:&lt;port>

    This parametr is required.

- **user**

    Daemon will be started with given user privileges. Default is _nobody_.

- **group**

    Daemon will be started with given group privileges. Default is _nogroup_.

### Service-specific options

This part of config file specifies a list of services supported by cheesecake. All options starts from the service name (see example below).

Following service-specific options are supported. All options are required unless otherwise specified.

- **&lt;service>\_enabled**

    Service enable status. Integer number, **1** or **0**. Every service is disabled by default.

- **&lt;service>\_db\_host**
- **&lt;service>\_db\_port**
- **&lt;service>\_db\_user**
- **&lt;service>\_db\_password**
- **&lt;service>\_db\_name**

    Service database parametrs. String.

    The database should contains a table **users** with specified by **login** request format (see below). The **id** column as a primary key is required.

- **&lt;service>\_memc\_host**
- **&lt;service>\_memc\_port**

    Memcached server options. This server will be used to store an authorized sessions.

- **&lt;service>\_memc\_prefix**

    This string will be used as a prefix in memcached.

- **&lt;service>\_session\_expire\_time**

    Memcached session expire time. All sessions expiration times will be updated on every request call. This time specifies maximum inactivity time (in seconds).

- **&lt;service>\_secrets**

    A comma-separated list of registered clients secrets (see authorization packet specification below).

- **&lt;service>\_db\_schema**

    This option specifies a database schema to be used in requests.

    The schema should be specified as a JSON object.

    The object is consists of 2 items: a table name and a list of columns.

    Each column have 2 required field (_name_ and _type_) and a list of optional fields:

    - _name_

        Specifies a column name into MySQL table.

    - _type_

        Specifies column value type. Only _str_, _int_, _email_ types are supported.

    - _col\_type_

        Specifies a type of a column: _userid_, _login_, _pass_. All 3 types should be presented in a columns list.

        Columns with this types (except _userid_) will be checked on **login** request.

    - _required_

        Specifies, that given field is required on sign-up request.

        If the column have a _type_ and not required, that means, that this column will be ignored in the _select_ request to db.

        If the column is not required, this column will be inserted as NULL if not presented in request.

    - _unique_

        Specifies a unique status of the column.

        Unique fields will be processed on register method.

        A column of type _login_ is unique by default. _userid_ column will be ignored in the register process.

    {

            table_name : "users",

            columns: [

                    {

                            name : "id",

                            col_type : "userid",

                            type : "int",

                    }, {

                            name : "login",

                            required : true,

                            col_type : "login",

                            type : "str",

                            unique: true,

                    }, {

                            name : "password",

                            required : true,

                            col_type : "pass",

                            type : "str",

                    }, {

                            name : "name",

                            required : true,

                            type : "str",

                    }, {

                            name : "email"

                            required : false,

                            type : "str",

                            unique : true,

                    }, {

                            name : "role",

                            required : true,

                            type : "int",

                    },

                    ...

            ],

    }

Example configuration for a service named &lt;some\_service>.

> some\_service\_enabled = 1
>
> some\_service\_memc\_prefix = some\_service\_prefix
>
> ...

## Protocol specification

Daemon expects a [CBOR](http://cbor.io/) packets. Daemon will return a CBOR packet as a reply.

All packets should be represented as an array with the format, specified below. But every have a _packet\_id_ as first element.

The packet\_id  is a random integer number required to enumerate packets over async mechanism.

This number will be returned to client in response also as a first argument.

### Authorization packet specification

Daemon expects as a first packet with the following structure.

If **--no\_auth** command line option is specified, this request shouldn't be sent. This implemented for debug purposes only.

> \[ packet\_id, client\_name, client\_seret \]

- **client\_name**

    The client name is a string, specified as a **service\_name** in configuration file. This service should be enabled in configuration.

    If this service is not presented in config, this client will be banned.

- **client\_secret**

    This string value should be presented in the **&lt;service>\_secrets** configuration option.

    If there is no such client secret presented in config, this client will be banned.

"The client is banned" means, that an error packet will be sent in response and the connection will be force closed.

The response packet have following format:

> \[ packet\_id, status, error\_message \]

Status field will be set to **0** on error and to **1** otherwise. The error message is not presented in success response.

### Common packet specification

Daemon expects input with following structure (json interpretarion):

> \[ packet\_id, function\_name, arguments \]

- **function\_name**

    This is a unique function name (string) to be called. All functions expects individual number of arguments (see below).

- **arguments**

    This is a number of function-specific argumets.

Daemon will return following packet in response (also CBOR encoded):

> \[ packet\_id, status, arguments \]

The _packet\_id_ argument will be simply taken from a request.

The _status_ argument can be **1** on request success and **0** on request fail.

If the request was failed, the third argument will be a message (string) which explains an error.

Following functions are expected:

- **check**

    Check the session existance. Session id should be given as argument (string).

    Daemon will just return a status **1** if the session exists and **0** otherwise. See return packet format below for more information.

- **about**

    Check the session existance and return a session information. Session id should be given as argument (string).

    Daemon will return a hash (as a third argument) with a format, specified by a configuration file (see below).

- **login**

    The request will try to authorize a user with given parametrs (a hash element in third argument).

    If success, the method will return a session id.

    All options, specified as a required login options (see cofiguration file specification below) should present in the parametrs.

- **logout**

    The request will try to close a session with given in third argument id.

    The 4th integer argument is optional.

    If 1 is given, the system will try to close all session of the specified user. Otherwise the system will close only given session.

- **register**

    The request will try to register a user with specified parametrs (third hash argument).

    All options, specified as required for register request (see cofiguration file specification below) should present in parametrs.

    On success new session id will be returned as third argument and user info in forth.

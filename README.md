# NAME

Catalyst::Plugin::PrometheusTiny - use Prometheus::Tiny with Catalyst

# SYNOPSIS

Use the plugin in your application class:

```perl
package MyApp;
use Catalyst 'PrometheusTiny';

MyApp->setup;
```

Add more metrics:

```perl
MyApp->config('Plugin::PrometheusTiny' => {
    metrics => {
        myapp_thing_to_measure => {
            help    => 'Some thing we want to measure',
            type    => 'histogram',
            buckets => [ 1, 50, 100, 1_000, 50_000, 500_000, 1_000_000 ],
        },
        myapp_something_else_to_measure => {
            help    => 'Some other thing we want to measure',
            type    => 'counter',
        },
    },
});
```

And somewhere in your controller classes:

```perl
$c->prometheus->observe_histogram(
    'myapp_thing_to_measure', $value, { label1 => 'foo' }
);

$c->prometheus->inc(
    'myapp_something_else_to_measure', $value, { label2 => 'bar' }
);
```

Once your app has served from requests you can fetch request/response metrics:

```perl
curl http://$myappaddress/metrics
```

# DESCRIPTION

This plugin integrates [Prometheus::Tiny::Shared](https://metacpan.org/pod/Prometheus%3A%3ATiny%3A%3AShared) with your [Catalyst](https://metacpan.org/pod/Catalyst) app,
providing some default metrics for requests and responses, with the ability
to easily add further metrics to your app. A default controller is included
which makes the metrics available via the configured ["endpoint"](#endpoint), though this
can be disabled if you prefer to add your own controller action.

See [Prometheus::Tiny](https://metacpan.org/pod/Prometheus%3A%3ATiny) for more details of the kind of metrics supported.

The following metrics are included by default:

```perl
http_request_duration_seconds => {
    help => 'Request durations in seconds',
    type => 'histogram',
},
http_request_size_bytes => {
    help    => 'Request sizes in bytes',
    type    => 'histogram',
    buckets => [ 1, 50, 100, 1_000, 50_000, 500_000, 1_000_000 ],
},
http_requests_total => {
    help => 'Total number of http requests processed',
    type => 'counter',
},
http_response_size_bytes => {
    help    => 'Response sizes in bytes',
    type    => 'histogram',
    buckets => [ 1, 50, 100, 1_000, 50_000, 500_000, 1_000_000 ],
}
```

# METHODS

## prometheus

```perl
sub my_action {
    my ( $self, $c ) = @_;

    $c->prometheus->inc(...);
}
```

Returns the `Prometheus::Tiny::Shared` instance.

# CONFIGURATION

## endpoint

The endpoint from which metrics are served. Defaults to `/metrics`.

## filename

It is recommended that this is set to a directory on a memory-backed
filesystem. See ["filename" in Prometheus::Tiny::Shared](https://metacpan.org/pod/Prometheus%3A%3ATiny%3A%3AShared#filename) for details and default
value.

## ignore\_path\_regex

```perl
ignore_path_regex => '^(healthcheck|foobar)'
```

A regular expression against which `$c->request->path` is checked, and
if there is a match then the request is not added to default request/response
metrics.

## include\_action\_labels

```perl
include_action_labels => 0      # default
```

If set to a true value, adds `controller` and `action` labels to the
default metrics, in addition to the `code` and `method` labels.

## metrics

```perl
metrics => {
    $metric_name => {
        help => $metric_help_text,
        type => $metric_type,
    },
    # more...
}
```

See ["declare" in Prometheus::Tiny](https://metacpan.org/pod/Prometheus%3A%3ATiny#declare). Declare extra metrics to be added to those
included with the plugin.

## no\_default\_controller

```perl
no_default_controller => 0      # default
```

If set to a true value then the default ["endpoint"](#endpoint) will not be
added, and you will need to add your own controller action for exporting the
metrics. Something like:

```perl
package MyApp::Controller::Stats;

sub begin : Private { }
sub end  : Private  { }

sub index : Path Args(0) {
    my ( $self, $c ) = @_;
    my $res = $c->res;
    $res->content_type("text/plain");
    $res->output( $c->prometheus->format );
}
```

# AUTHOR

Peter Mottram (SysPete) <peter@sysnix.com>

# CONTRIBUTORS

Curtis "Ovid" Poe

Graham Christensen <graham@grahamc.com>

# COPYRIGHT

Copyright (c) 2021 the Catalyst::Plugin::PrometheusTiny ["AUTHOR"](#author)
and ["CONTRIBUTORS"](#contributors) as listed above.

# LICENSE

This library is free software and may be distributed under the same terms
as perl itself.

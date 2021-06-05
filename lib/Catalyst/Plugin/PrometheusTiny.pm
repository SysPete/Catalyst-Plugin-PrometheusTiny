package Catalyst::Plugin::PrometheusTiny;

use strict;
use warnings;

our $VERSION = '0.001';

use Carp            ();
use Catalyst::Utils ();
use Moose::Role;
use Prometheus::Tiny::Shared;

my $defaults = {
    metrics => [
        {
            name => 'http_request_duration_seconds',
            help => 'Request durations in seconds',
            type => 'histogram',
        },
        {
            name    => 'http_request_size_bytes',
            help    => 'Request sizes in bytes',
            type    => 'histogram',
            buckets => [ 1, 50, 100, 1_000, 50_000, 500_000, 1_000_000 ],
        },
        {
            name => 'http_requests_total',
            help => 'Total number of http requests processed',
            type => 'counter',
        },
        {
            name    => 'http_response_size_bytes',
            help    => 'Response sizes in bytes',
            type    => 'histogram',
            buckets => [ 1, 50, 100, 1_000, 50_000, 500_000, 1_000_000 ],
        }
    ],
};

my ( $prometheus, $ignore_path_regexp, $no_default_controller );

sub prometheus {
    my $c = shift;
    $prometheus ||= do {
        my $config = Catalyst::Utils::merge_hashes( $defaults,
            $c->config->{'Plugin::PrometheusTiny'} // {} );

        $ignore_path_regexp = $config->{ignore_path_regexp};
        if ($ignore_path_regexp) {
            $ignore_path_regexp = qr/$ignore_path_regexp/n
              unless 'Regexp' eq ref $ignore_path_regexp;
        }

        $no_default_controller = $config->{no_default_controller};

        my $metrics = $config->{metrics};
        Carp::croak "Plugin::PrometheusTiny metrics must be an array reference"
          unless 'ARRAY' eq ref $metrics;

        my $prom = Prometheus::Tiny::Shared->new(
            ( filename => $config->{filename} ) x defined $config->{filename} );

        for my $metric (@$metrics) {
            $prom->declare(
                $metric->{name},
                help => $metric->{help},
                type => $metric->{type},
                ( buckets => $metric->{buckets} ) x defined $metric->{buckets},
            );
        }

        $prom;
    };
    return $prometheus;
}

after finalize => sub {
    my $c       = shift;
    my $request = $c->request;

    return
      if !$no_default_controller && $request->path eq 'metrics';

    return
      if $ignore_path_regexp
      && $request->path =~ $ignore_path_regexp;

    my $response = $c->response;
    my $code     = $response->code;
    my $method   = $request->method;

    $prometheus->histogram_observe(
        'http_request_size_bytes',
        $request->content_length // 0,
        { method => $method, code => $code }
    );
    $prometheus->histogram_observe(
        'http_response_size_bytes',
        $response->has_body ? length( $response->body ) : 0,
        { method => $method, code => $code }
    );
    $prometheus->inc( 'http_requests_total',
        { method => $method, code => $code } );
    $prometheus->histogram_observe( 'http_request_duration_seconds',
        $c->stats->elapsed, { method => $method, code => $code } );
};

before setup_components => sub {
    my $class = shift;
    return
      if $class->config->{'Plugin::PrometheusTiny'}{no_default_controller};

    $class->inject_component( "Controller::Metrics" =>
          { from_component => "Catalyst::Plugin::PrometheusTiny::Controller" }
    );
};

# ensure our Prometheus::Tiny::Shared is created pre-fork
after setup_finalize => sub {
    shift->prometheus;
};

package Catalyst::Plugin::PrometheusTiny::Controller;

use base 'Catalyst::Controller';

sub begin : Private { }
sub end : Private   { }

sub index : Path Args(0) {
    my ( $self, $c ) = @_;
    my $res = $c->res;
    $res->content_type("text/plain");
    $res->output( $c->prometheus->format );
}

=head1 NAME

Catalyst::Plugin::PrometheusTiny - use Prometheus::Tiny with Catalyst

=head1 SYNOPSIS

Use the plugin in your application class:

    package MyApp;
    use Catalyst 'PrometheusTiny';

    MyApp->setup;

Add more metrics:

    MyApp->config('Plugin::PrometheusTiny' => {
        metrics => [
            {
                name    => 'myapp_thing_to_measure',
                help    => 'Some thing we want to measure',
                type    => 'histogram',
                buckets => [ 1, 50, 100, 1_000, 50_000, 500_000, 1_000_000 ],
            },
            {
                name    => 'myapp_something_else_to_measure',
                help    => 'Some other thing we want to measure',
                type    => 'counter',
            },
        ],
    });

And somewhere in your controller classes:

    $c->prometheus->observe_histogram(
        'myapp_thing_to_measure', $value, { label1 => 'foo' }
    );

    $c->prometheus->inc(
        'myapp_something_else_to_measure', $value, { label2 => 'bar' }
    );

Once your app has served from requests you can fetch request/response metrics:

    curl http://$myappaddress/metrics

=head1 DESCRIPTION

This plugin integrates L<Prometheus::Tiny::Shared> with your L<Catalyst> app,
providing some default metrics for requests and responses, with the ability
to easily add further metrics to your app. A default controller is included
which makes the metrics available via the C</metrics> endpoint, though this
can be disabled if you prefer to add your own controller action.

See L<Prometheus::Tiny> for more details of the kind of metrics supported.

The following metrics are included by default:

    {
        name    => 'http_request_duration_seconds',
        help    => 'Request durations in seconds',
        type    => 'histogram',
    },
    {
        name    => 'http_request_size_bytes',
        help    => 'Request sizes in bytes',
        type    => 'histogram',
        buckets => [ 1, 50, 100, 1_000, 50_000, 500_000, 1_000_000 ],
    },
    {
        name    => 'http_requests_total',
        help    => 'Total number of http requests processed',
        type    => 'counter',
    },
    {
        name    => 'http_response_size_bytes',
        help    => 'Response sizes in bytes',
        type    => 'histogram',
        buckets => [ 1, 50, 100, 1_000, 50_000, 500_000, 1_000_000 ],
    }

=head1 METHODS

=head2 prometheus

    sub my_action {
        my ( $self, $c ) = @_;

        $c->prometheus->inc(...);
    }

Returns the C<Prometheus::Tiny::Shared> instance.

=head1 CONFIGURATION

=head2 filename

It is recommended that this is set to a directory on a memory-backed
filesystem. See L<Prometheus::Tiny::Shared/filename> for details and default
value.

=head2 ignore_path_regex

    ignore_path_regex => '^(healthcheck|foobar)'

A regular expression against which C<< $c->request->path >> is checked, and
if there is a match then the request is not added to default request/response
metrics.

=head2 metrics

    metrics => [
        {
            name => $metric_name,
            help => $metric_help_text,
            type => $metric_type,
        },
        # more...
    ]

See L<Prometheus::Tiny/declare>. Declare extra metrics to be added to those
included with the plugin.

=head2 no_default_controller

    no_default_controller => 0      # default

If set to a true value then the default C</metrics> endpoint will not be
added, and you will need to add your own controller action for exporting the
metrics. Something like:

    package MyApp::Controller::Stats;

    sub begin : Private { }
    sub end  : Private  { }

    sub index : Path Args(0) {
        my ( $self, $c ) = @_;
        my $res = $c->res;
        $res->content_type("text/plain");
        $res->output( $c->prometheus->format );
    }

=cut

1;

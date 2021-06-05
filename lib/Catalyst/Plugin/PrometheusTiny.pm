package Catalyst::Plugin::PrometheusTiny;

use strict;
use warnings;

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
    return;
}

=head1 NAME

Catalyst::Plugin::PrometheusTiny - use Prometheus::Tiny with Catalyst

=cut

1;

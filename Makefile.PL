use ExtUtils::MakeMaker;
( do './maint/Makefile.PL.include' or die $@ ) unless -f 'META.yml';
WriteMakefile(
    NAME             => "Catalyst::Plugin::PrometheusTiny",
    AUTHOR           => q{Peter Mottram (SysPete) <peter@sysnix.com>},
    VERSION_FROM     => 'lib/Catalyst/Plugin/PrometheusTiny.pm',
    MIN_PERL_VERSION => 5.008,
    BUILD_REQUIRES   => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'Carp'                     => 0,
        'Catalyst::Runtime'        => '5.900000',
        'Moose::Role'              => 0,
        'Prometheus::Tiny'         => 0,
        'Prometheus::Tiny::Shared' => 0,
    },
);

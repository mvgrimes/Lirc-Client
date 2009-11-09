use strict;
use warnings;
use Test::Most 'bail';
use File::Find;

BEGIN {
    my @modules;

    find(
        sub {
            push @modules, $_ if /\.pm$/;
        },
        'lib'
    );

    plan tests => scalar @modules;
    use_ok $_ for @modules;
}

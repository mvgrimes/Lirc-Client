use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    module_name => 'Lirc::Client',
    license     => 'perl',

    requires => {
        'Moo'                => '1.0',
        'IO::Socket'         => '1.0',
        'Carp'               => 0,
        'File::Path::Expand' => 0,
    },
    build_requires => {
        'Test::More' => 0,
        'File::Spec' => 0,
        'IO::Select' => 0,
        'IO::Handle' => 0,
    },
);

# LIRC doesn't work on Windows, so no need for this module to support it
die "No support for OS" if $^O eq 'MSWin32';

$build->create_build_script;

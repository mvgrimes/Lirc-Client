use strict;
use warnings;
use Module::Build;

my $build = Module::Build->new(
    module_name => 'Lirc::Client',
    license     => 'perl',

    requires           => {
        'IO::Socket'            => '1.0',
        'Hash::Util'            => 0,
        'Class::Accessor::Fast' => 0,
        'Carp'                  => 0,
        'File::Path::Expand'    => 0,
    },
    build_requires => {
        'Test::More' => 0,
        'File::Spec' => 0,
        'IO::Select' => 0,
        'IO::Handle' => 0,
    },

    # recommends				=> {
    # 		'Test::Pod'				=> 0,
    # 	},
);

# $build->add_build_element('gif');
$build->create_build_script;


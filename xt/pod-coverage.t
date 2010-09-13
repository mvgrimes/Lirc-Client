# Ensure pod coverage in your distribution
use strict;
use warnings;
use Test::More;

my @MODULES = ( 'Test::Pod::Coverage 1.08', );

# Load the testing modules
for my $MODULE (@MODULES) {
    eval "use $MODULE";
    if ($@) {
        $ENV{RELEASE_TESTING}
          ? die("Failed to load required release-testing module $MODULE")
          : plan( skip_all => "$MODULE not available for testing" );
    }
}

all_pod_coverage_ok();
1;

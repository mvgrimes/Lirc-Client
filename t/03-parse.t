#!/usr/bin/perl -w

use strict;
use warnings;

use Test::More tests => 3;

# Test 1 -- can we load the library?
BEGIN { use_ok( 'Lirc::Client' ); };

# Test 2 -- can we create an new client based on lclient_test?
my $lirc = Lirc::Client->new( 'lclient_test', 'samples/lircrc', { fake => 1 } );
ok $lirc, "Created new Lirc::Client";

# Test 3 -- can we get the command list?
my %hash1 = (
	'son-cable-CABLE_STOP-:mode' => 'undef',
	'son-cable-CABLE_STOP-:flag' => 'undef',
	'son-cable-CABLE_STOP-:conf' => 'STOP',
	'son-cable-CABLE_STOP-:rep' => 'undef',

	'son-cable-CABLE_PLAY-:conf' => 'PLAY',
	'son-cable-CABLE_PLAY-:flag' => 'undef',
	'son-cable-CABLE_PLAY-:rep' => 'undef',
	'son-cable-CABLE_PLAY-:mode' => 'undef',
  
	'son-cable-CABLE_PAUSE-:conf' => 'PAUSE',
	'son-cable-CABLE_PAUSE-:flag' => 'undef',
	'son-cable-CABLE_PAUSE-:rep' => 'undef',
	'son-cable-CABLE_PAUSE-:mode' => 'undef',
);

my $k;
my %hash2;
for ($lirc->recognized_commands){
	next if /^\s*$/;
	if( /:/ && ! /=>/ ){
		s/\n.*//;
		$k = $_;
	} else {
		my ($m,$v) = split /\s*=>\s*/;
		$v =~ s/,\n.*//;
		$hash2{"$k$m"} = $v;
		# print "\$hash2{$k$m} = $v\n";
	}
}

# ok eq_hash( \%hash1, \%hash2), "Recognized commands";
is_deeply \%hash1, \%hash2, "Recognized commands";


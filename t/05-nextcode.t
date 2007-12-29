#!/usr/bin/perl

use Test::More tests=>4;
$|++;

use_ok( "Lirc::Client" );

my $lirc=Lirc::Client->new(
		"lirc-client-test",
		"samples/lircrc.2",
		{ debug => 0, fake => 1 }
	);
ok( $lirc, "created a lirc object");

pipe my $read, $write or die $!;
$lirc->{sock} = $read;
print $write "0 0 play test-remote\n";
print $write "0 0 pause test-remote\n";
close $write;

my $code = $lirc->next_code; 
is( $code, "PLAY", "received the play event");
$code = $lirc->next_code; 
is( $code, "PAUSE", "received the pause event");

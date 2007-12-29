#!/usr/bin/perl

use strict;
use warnings;
use Lirc::Client;

                            
my $lirc = Lirc::Client->new('lclient-test',{
        rcfile    => "./lircrc", 
        debug    => 1,
        fake    => 0,
    });

while( my $k = $lirc->next_code ){
    print "key: $k\n";
}

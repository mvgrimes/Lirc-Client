package Lirc::Client;

###########################################################################
# Lirc::Client
# Mark Grimes
# $Id: Client.pm,v 1.28 2007/12/10 22:45:58 mgrimes Exp $
#
# Package to interact with the LIRC deamon
# Copyright (c) 2001 Mark Grimes (mgrimes AT alumni DOT duke DOT edu).
# All rights reserved. This program is free software; you can redistribute
# it and/or modify it under the same terms as Perl itself.
#
# Formatted with tabstops at 4
#
# Parts of this package were inspired by
#  hotornot.pl by michael@engsoc.org, and
#  Perl LIRC Client (plircc) by Matti Airas (mairas@iki.fi)
# Thanks!
#
###########################################################################

use strict;
use warnings;
use base qw(Class::Accessor::Fast);
use Hash::Util qw(lock_keys);	# Lock a hash so no new keys can be added
use Carp;
use IO::Socket;

# use POSIX qw(:errno_h);
# use Fcntl qw(F_GETFL F_SETFL O_NONBLOCK);

# TODO: watch for signals from lircd to re-read rc file

our $VERSION = '1.29';
our $DEBUG = 0;		# Class level debug flag

# #########################################################
#
#	Fields contains all of the objects data which can be
#	set/retreived by an accessor methods
#
# #########################################################

my %fields = (		# List of all the fields which will have accessors
	'prog'		=> undef,		# the program name from lircrc file
	'rcfile'	=> "$ENV{HOME}/.lircrc",	# location of lircrc
	'dev'		=> '/dev/lircd',			# location of the lircd device
	'debug'		=> 0,			# instance debug flag
	'fake'		=> 0,			# fake the lirc connection
	'sock'		=> undef,		# the lircd socket
);

Lirc::Client->mk_accessors( keys %fields );

# -------------------------------------------------------------------------------
# LircClient->new( <program>, [<lircrc-file>], [<lircd-device>],
#                               [<debug-flag>], [<fake-lircd>] );
#
sub new {
	my $that  = shift;
	my $class = ref($that) || $that;	# Enables use to call $instance->new()
	my $self  = {
		'_DEBUG' 		=> 0,			# Instance level debug flag
		'_mode'			=> '',
		'_in_block'		=> 0,
		'_commands'		=> {},
		'_buf'			=> '',
		%fields,
	};

	# Process the arguments
	my $cfg = {}; 
	for(qw/prog rcfile dev debug fake/){	# get any passed by order
		my $arg = shift;
		($cfg=$arg and last) if ref $arg eq 'HASH';
		$self->{$_} = $arg if defined $arg;
	}
	while(my ($k,$v) = each %$cfg ){		# now take care of those by name
		$self->{$k} = $v;
	}
	bless $self, $class;

	# Lock the $self hashref, so we don't accidentally add a key!
	# TODO: how does this impact inheritance?
	lock_keys( %$self );

	croak "Lirc::Client not passed a program name" unless $self->prog;
    $self->_initialize()
        or croak "Lircd::Client couldn't initialize device $self->{dev}: $!";
	return $self;
}

#  -------------------------------------------------------------------------------

sub _initialize {
	my $self = shift;

	if( $self->{fake} ){
		$self->{sock} = \*STDIN;
	} else {
		$self->{sock} = IO::Socket->new(Domain => &AF_UNIX,
				Type    => SOCK_STREAM,
				Peer    => $self->{dev} )
			or croak "couldn't connect to $self->{dev}: $!";
	}

	$self->_parse_lircrc;
	return 1;
}

# -------------------------------------------------------------------------------

sub clean_up {
	my $self = shift;
	close $self->{sock} unless $self->{fake};
    return;
}

# -------------------------------------------------------------------------------

sub _parse_lircrc { ## no critic  
  my $self = shift;

  # This is too complicated and uses if/elsif/elsif/...
  # TODO: fix it when we can use "given"
  ## no critic

  open( my $rcfile, '<', $self->{rcfile} )
      or croak "couldn't open lircrc file ($self->{rcfile}): $!";

  my $in_block = 0;
  my $cur_mode = '';
  my %commands;

  my ($prog, $remote, $button, $repeat, $config, $mode, $flags);
  while(<$rcfile>){
    s/^\s*#.*$//g;                            # remove commented lines

    # print "> ($cur_mode) $_" if ($self->{debug} & D_PARSE);

    if     (  /^\s*begin\s*$/i            ){  # begin block
      $in_block and croak "Found begin inside a block in line: $_\n";
      $in_block = 1;

    } elsif(  /^\s*end\s*(\w*)\s*$/i          ){  # end block
      if( $1 ){
        if( $cur_mode eq $1 ){ $cur_mode = ''; next; }
        else { croak "end \"$1\": found without associated begin mode"; }
      }

      $in_block or croak "Found end outside of a block in line: $_\n";
      $in_block = 0;
      defined $prog or croak "end of block found without a prog code at line: $_\n";
      next if( $prog ne $self->{prog} );
      $commands{"$remote-$button-$cur_mode"} = { conf => $config, rep => $repeat, mode => $mode, flag => $flags };
      ($prog, $remote, $button, $repeat, $config, $mode, $flags) = (undef, undef, undef, undef, undef, undef, undef, undef );

    } elsif( /^\s*begin\s*(\w+)\s*$/i      ){  # begin mode block
      croak "found embedded mode line: $_\n" if $cur_mode;
      croak "begin mode found inside command block: $_\n" if $in_block;
      $cur_mode = $1;

    } elsif(  /^\s*(\w+)\s*=\s*(.*?)\s*$/  ){  # command
      my ($tok, $act) = ($1, $2);
      if   ($tok =~ /^prog$/i)  { $prog    = $act; }
      elsif($tok =~ /^remote$/i){  $remote  = $act; }
      elsif($tok =~ /^button$/i){  $button  = $act; }
      elsif($tok =~ /^repeat$/i){  $repeat  = $act; }
      elsif($tok =~ /^config$/i){  $config  = $act; }
      elsif($tok =~ /^mode$/i)  {  $mode    = $act; }
      elsif($tok =~ /^flags$/i)  {  $flags  = $act; }

    } elsif(  /^\s*$/                     ){  # blank line
      # do nothing
    } else {                                  # unrecognized
      croak "Couldn't parse lircrc file ($self->{rcfile}) error in line: $_\n";
    }
  }
  close $rcfile;
  $self->{_commands} = \%commands;

  return;
}

# -------------------------------------------------------------------------------

sub recognized_commands {
  my $self = shift;

  my %commands = %{$self->{_commands}};
  my @list;
  foreach my $c (keys %commands){
    push @list, "$c:\n  ";
    my %conf = %{$commands{$c}};
    foreach my $i (keys %conf){
      my $a = defined $conf{$i} ? $conf{$i} : 'undef';
      push @list, "$i => $a,\n  ";
    }
    push @list, "\n";
  }
  return @list;
}

# -------------------------------------------------------------------------------


sub _get_lines {
	my $self = shift;

	# what is in the buffer now?
	print "buffer1=", $self->{_buf}, "\n" if $self->debug;

	# read anything in the pipe
	my $buf;
	my $status = sysread( $self->sock, $buf, 512 );
	( carp "bad status from read" and return ) unless defined $status;

	# what is in the buffer after the read?
	$self->{_buf} .= $buf;
	print "buffer2=", $self->{_buf}, "\n" if $self->debug;

	# separate the lines, leaving partial lines on _buf
    my @lines;
	push @lines, $1 while( $self->{_buf} =~ s/^(.+)\n// );  ## no critic
                # while() tests that s/// matched

	return @lines;
}
	
sub nextcodes {
	return $_[0]->next_codes();
}

sub next_codes {
  my $self = shift;

  my @lines = $self->_get_lines;
  print "==", join( ", ", map { defined $_ ? $_ : "undef" }  @lines ), "\n" if $self->debug;
  return () unless scalar @lines;
  my @commands = ();
  for my $line (@lines){
	  chomp $line;
	  print "Line: $line\n" if $self->debug;
	  my $command = $self->parse_line( $line );
	  print "Command: ", (defined $command ? $command : "undef"), "\n" if $self->debug;
	  push @commands, $command if defined $command;
  }
  return @commands;
}

sub nextcode {
	return $_[0]->next_code();
}

sub next_code {
  my $self = shift;

  my $fh = $self->sock;
  while( defined (my $line = <$fh>) ){
	  chomp $line;
	  print "Line: $line\n" if $self->debug;
	  my $command = $self->parse_line( $line );
	  print "Command: ", (defined $command ? $command : "undef"), "\n" if $self->debug;
	  return $command if defined $command;
  }
  return; # no command found and lirc exited?
}

# -------------------------------------------------------------------------------

sub parse_line {			# parse a line read from lircd
	my $self = shift;
	$_ = shift;

	print "> ($self->{_in_block}) $_\n" if $self->debug;

	# Take care of response blocks
	if( /^\s*BEGIN\s*$/ ){
		croak "got BEGIN inside a block from lircd: $_" if $self->{_in_block};
		$self->{_in_block} = 1;
		return;
	}
	if( /^\s*END\s*$/ ){
		croak "got END outside a block from lircd: $_" if! $self->{_in_block};
		$self->{_in_block} = 0;
		return;
	}
	return if $self->{_in_block};

	# Decipher IR Command
	# http://www.lirc.org/html/technical.html#applications
	# <hexcode> <repeat count> <button name> <remote name>
	my ($hex, $repeat, $button, $remote) = split /\s+/;
	defined $button and length $button or do {
		carp "Unable to decode.\n";
		return;
	};

	my %commands = %{$self->{_commands}};
	my $cur_mode = $self->{_mode};
	exists $commands{"$remote-$button-$cur_mode"} or return;
	my %command = %{$commands{"$remote-$button-$cur_mode"}};

	my $rep_count = 2**32;  # default repeat count
	if( defined $command{rep} && $command{rep} ){ $rep_count = $command{rep}; }

	if( hex($repeat) % $rep_count != 0 ){ return; }
	if( defined $command{mode} ){ $self->{mode} = $command{mode}; }

	print ">> $button accepted --> $command{conf}\n" if $self->debug;
	return $command{conf};
}

sub DESTROY {
	my $self = shift;
	print __PACKAGE__, ": DESTROY\n" if $self->debug;

	$self->clean_up;
    return;
}

# #########################################################
#
# Debug accessor
# 	Can work on both the instance and the class
#		$instance->debug([level]);
#		PACKAGE->debug([level]);
#
# #########################################################

sub debug {
	my $self = shift;

	if(@_){				# Set the debug level
		my $level = shift;
		if( ref($self) ){
			$self->{debug} = $level;
		} else {
			$DEBUG = $level;
		}
		# Call the parent class debug method
        # TODO: check that it is an inherited class
		# $self->SUPER::debug($debug);
	} 

	return $DEBUG || $self->{debug};
}

1;


__END__


=head1 NAME

Lirc::Client - A client library for the Linux Infrared Remote Control

=head1 SYNOPSIS

  use Lirc::Client;
  ...
  my $lirc = Lirc::Client->new( 'progname' );
  my $code;
  do {                            # Loop while getting ir codes
    $code = $lirc->next_code;     # wait for a new ir code
    print "Lirc> $code\n";
    process( $code );             # do whatever you want with the code
  } while( defined $code );       # undef will be returned when lirc dev exists

=head1 DESCRIPTION

This module provides a simple interface to the Linux Infrared Remote
Control (Lirc). The module encasuplates parsing the Lirc config file (.lircrc),
openning a connection to the Lirc device, and retrieving events from the 
device.

=head2 Use Details

=over 4

=item new( program, [rcfile], [dev], [debug], [fake] )

=item new( program, \%options )

  my $lirc = Lirc::Client->new( 'progname',    # required
               "$ENV{HOME}/.lircrc",           # optional
               '/dev/lircd', 0, 0 );           # optional

  my $lirc = Lirc::Client->new( 'progname', {     # required
               rcfile    => "$ENV{HOME}/.lircrc", # optional
               dev        => "/dev/lircd",        # optional
               debug    => 0,                     # optional
               fake    => 1,                      # optional
        } );

The constructor accepts two calling forms: an ordered list (for backwards
compatibility), and a hash ref of configuration options. The two forms
can be combined as long as the hash ref is last. 

When called the constructor defines the program token used in the Lirc
config file, opens and parses the Lirc config file (B<rcfile> defaults to
~/.lircrc if none specified), connects to the Lirc device (B<dev> defaults to
/dev/lircd if none specified), and returns the Lirc::Client object. Pass
a true value for B<debug> to have various debug information printed
(defaults to false). A true value for the B<fake> flag will cause Lirc::Client
to read STDIN rather than the lircd device (defaults to false), which is 
primarily useful for debuging.

=item recognized_commands()

  my @list = $lirc->recongnized_commands();

Returns a list of all the recongnized commands for this application (as
defined in the call to B<new>.

=item next_code()

=item nextcode()

  my $code = $lirc->next_code;

Retrieves the next IR command associated with the B<progname> as defined in
B<new()>, blocking if none is available. B<next_code> uses the stdio read
commands which are buffered. Use B<next_codes> if you are also using
select.


=item next_codes()

=item nextcodes()

  my @codes = $lirc->next_codes;

Retrieves any IR commands associated with the B<progname> as defined in the 
B<new()> constructor, blocking if none are available. B<next_codes> uses
sysread so it is compatible with B<select> driven event loops. This is 
the most efficient method to accomplish a non-blocking read.

Due to the mechanics of B<sysread> and B<select>, this version may
return multiple ir codes so the return value is an array.

Here is an example using IO::Select:

    use IO::Select;
    ....
    my $select = IO::Select->new();
    $select->add( $lirc->sock );
    while(1){
        # do your own stuff, if you want
        if( my @ready = $select->can_read(0) ){ 
            # an ir event has been received (if you are tracking other
			# filehandles, you need to make sure it is lirc)
            my @codes = $lirc->next_codes;    # should not block
            for my $code (@codes){
                process( $code );
            }
        }
    }

This is much more efficient than looping over B<next_code> in non-blocking
mode. See the B<select.t> test for the complete example. Also, checkout the
B<Event> module on cpan for a nice way to handle your event loops.

=item sock()

  my $sock = $lirc->sock();

Returns (or sets if an arguement is passed) the socket from which to read
lirc commands. This can be used to work Lirc::Client into you own event 
loop. 

=item parse_line()

  my $code = $lirc->parse_line( $line );

Takes a full line as read from the lirc device and returns code on the 
B<config> line of the lircrc file for that button. This can be used in 
combination with B<sock> to take more of the event loop control out of
Lirc::Cli

=item clean_up()

  $lirc->clean_up();

Closes the Lirc device pipe, etc. B<clean_up> will be called when the lirc
object goes out of scope, so this is not necessary.

=item debug()

  $lirc->debug;

Return the debug status for the lirc object.

=back

=head1 SEE ALSO

=over 4

=item The Lirc Project - http://www.lirc.org

=back

=head1 AUTHOR

Mark Grimes E<lt>mgrimes@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Mark Grimes

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=head1 BUGS

None of which I am aware. Please let me know if you find any.

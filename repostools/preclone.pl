#!/usr/bin/perl -wT

# A script to remove published web directories prior to a clone.
# This should be called with the username of the user whose directory
# should be removed.

use lib qw(/var/www/webperl);
use v5.12;

use Webperl::ConfigMicro;
use Webperl::Utils qw(path_join);

use FindBin;             # Work out where we are
my $scriptpath;
BEGIN {
    $ENV{"PATH"} = "/bin:/usr/bin"; # safe path.

    # $FindBin::Bin is tainted by default, so we may need to fix that
    # NOTE: This may be a potential security risk, but the chances
    # are honestly pretty low...
    if ($FindBin::Bin =~ /(.*)/) {
        $scriptpath = $1;
    }
}

## @fn void fatal_error($message)
# A simple convenience function to output fatal error messages. This
# could be done as a $SIG{__DIE__} handler, but this seems cleaner.
#
# @param message The message to print.
sub fatal_error {
    my $message = shift;

    print "FATAL: $message\n";
    exit(1);
}

my $settings = Webperl::ConfigMicro -> new(path_join($scriptpath, "..", "config", "site.cfg"))
    or fatal_error("Unable to load configuration: $Webperl::SystemModule::errstr");

my $raw_username = $ARGV[0]
    or fatal_error("No username specified.");

# Check and untaint in one go
my ($username) = $raw_username =~/^([.\w]+)$/;
fatal_error("Username is not valid")
    unless($username);

# Where should the directory be?
my $userdir = path_join($settings -> {"git"} -> {"webbasedir"}, $username);

if(-e $userdir) {
    my $res = `/bin/rm -rf $userdir`;
    fatal_error("Unable to remove user directory: $res")
        if($res);
}

my $tempdir = path_join($settings -> {"git"} -> {"webtempdir"}, $username);

if(-e $tempdir) {
    my $res = `/bin/rm -rf $tempdir`;
    fatal_error("Unable to remove user temp directory: $res")
        if($res);
}

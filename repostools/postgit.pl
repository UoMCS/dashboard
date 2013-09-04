#!/usr/bin/perl -wT

# A script to move user directories out of the work area into the web
# tree, locking them down as needed.

use lib qw(/var/www/webperl);
use v5.12;

use Webperl::ConfigMicro;
use Webperl::Utils qw(path_join save_file);

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


## @fn void create_htaccess($htaccess, $userdir)
# Create a htaccess file that restricts the user to their own directory
# and /tmp. I'd prefer not to even have the latter, but not a lot can
# really be done about it if they get uploads.
#
# @param htaccess The name of the .htaccess file to write to
# @param userdir  The location of the user's directory
sub create_htaccess {
    my $htaccess = shift;
    my $userdir  = shift;

    my $contents = "php_value open_basedir ".$userdir.":/tmp/\n";

    eval { save_file($htaccess, $contents); };
    fatal_error($@) if($@);
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

# And where should it go?
my $tempdir = path_join($settings -> {"git"} -> {"webtempdir"}, $username);

if(-e $tempdir) {
    if(-d $tempdir) {
        my $htaccess = path_join($tempdir, ".htaccess");
        my $gitdir   = path_join($tempdir, ".git");

        create_htaccess($htaccess, $userdir);

        # kill write on important files
        my ($user, $grp) = ($settings -> {"git"} -> {"webuser"}, $settings -> {"git"} -> {"webgroup"});
        my $res = `/bin/chown -R $user:$grp '$htaccess' '$gitdir' 2>&1`;
        fatal_error("Unable to set owner: $res") if($res);

        $res = `/bin/chmod -R g-w,u-w '$htaccess' '$gitdir' 2>&1`;
        fatal_error("Unable to complete setup: $res") if($res);

        fatal_error("User directory move failed: $!")
            unless(rename $tempdir, $userdir);
    } else {
        fatal_error("User directory does not appear to be a directory?");
    }
} else {
    fatal_error("No user directory found, unable to move out of working area.");
}

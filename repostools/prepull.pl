#!/usr/bin/perl -wT

# A script to move user directories into the work area, and clean them
# up ready for a pull.

use lib qw(/var/www/webperl);
use v5.12;

use Webperl::ConfigMicro;
use Webperl::Utils qw(path_join);
use Git::Repository;

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
my ($username) = $raw_username =~ /^([.\w]+)$/;
fatal_error("Username is not valid")
    unless($username);

# Path can be optional
my ($path) = $ARGV[1] =~ /^(\w+)$/
    if($ARGV[1]);

print STDERR "Running prepull for $username path $path";

# Where should the directory be?
my $userdir = path_join($settings -> {"git"} -> {"webbasedir"}, $username, $path);

# And where should it go?
my $tempdir = path_join($settings -> {"git"} -> {"webtempdir"}, $username);

if(-e $userdir) {
    if(-d $userdir) {
        if(rename $userdir, $tempdir) {
            my $htaccess = path_join($tempdir, ".htaccess");
            my $config   = path_join($tempdir, "config.inc.php");
            my $gitdir   = path_join($tempdir, ".git");

            # Add back the write perms
            foreach my $file ($htaccess, $config, $gitdir) {
                `/bin/chmod -R u+w,g+w $file` if(-e $file);
            }

            my $output = eval {
                my $repo = Git::Repository -> new(work_tree => $tempdir, { git => "/usr/bin/git", input => "" });
                $repo -> run("checkout .htaccess");
            };

            # Remove the config if it exists
            unlink($config) if(-e $config);
        } else {
            fatal_error("User directory move failed: $!");
        }
    } else {
        fatal_error("User directory does not appear to be a directory?");
    }
} else {
    fatal_error("No user directory found, unable to move to working area.");
}

print STDERR "Done prepull for $username";

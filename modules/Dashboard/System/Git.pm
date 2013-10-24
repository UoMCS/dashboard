## @file
# This file contains the implementation of the git engine.
#
# @author  Chris Page &lt;chris@starforge.co.uk&gt;
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## @class
# This class encapsulates operations involving git.
package Dashboard::System::Git;

use strict;
use base qw(Webperl::SystemModule);
use Webperl::Utils qw(path_join blind_untaint save_file);
use Git::Repository;
use v5.12;

## @method $ user_web_repo_exists($username)
# Determine whether a repo exists in the standard web directory for the
# specified user.
#
# @param username The username of the user to search for a repo for.
# @return The origin of the repo if the repo exists, false otherwise,
#         undef on error.
sub user_web_repo_exists {
    my $self     = shift;
    my $username = lc(shift);

    $self -> clear_error();

    # Path to the user's config file, if it exists
    my $config = path_join($self -> {"settings"} -> {"git"} -> {"webbasedir"}, $username, ".git", "config");

    return 0 if(!-f $config);

    # Hey, what do you know, ConfigMicro can parse git configs!
    my $settings = Webperl::ConfigMicro -> new($config)
        or return $self -> self_error("Repository check failed: ".$Webperl::SystemModule::errstr);

    return $settings -> {'remote "origin"'} -> {"url"};
}


## @method $ delete_repository($username)
# Delete the repository associated with the specified user.
#
# @param username   The name of the user cloning the repository.
# @return true on success, undef on error.
sub delete_repository {
    my $self       = shift;
    my $username   = lc(shift);

    $self -> clear_error();

    my ($safename) = $username =~/^([.\w]+)$/;
    return $self -> self_error("Clone failed: illegal username specified") if(!$safename);

    # perform the pre-clone step
    my $res = `sudo $self->{settings}->{repostools}->{preclone} $safename`;
    return $self -> self_error("Clone failed: $res") if($res);

    # that should actually be all that is needed...
    return 1;
}


## @method $ clone_repository($repository, $username)
# Clone the specified repository and move it into the user's web space.
#
# @param repository The URL of the repository to clone.
# @param username   The name of the user cloning the repository.
# @return true on success, undef on error.
sub clone_repository {
    my $self       = shift;
    my $repository = shift;
    my $username   = lc(shift);

    $self -> clear_error();

    my ($safename) = $username =~/^([.\w]+)$/;
    return $self -> self_error("Clone failed: illegal username specified") if(!$safename);

    # perform the pre-clone step
    my $res = `sudo $self->{settings}->{repostools}->{preclone} $safename`;
    return $self -> self_error("Clone failed: $res") if($res);

    # Do the clone itself
    my $target = path_join($self -> {"settings"} -> {"git"} -> {"webtempdir"}, $safename);
    my $output = eval { Git::Repository -> run(clone => $repository => $target,
                                               { git => "/usr/bin/git", input => "" }); };
    if(my $err = $@) {
        return $self -> self_error("Failed while attempting to clone a private project. Make the project public and try again.")
            if($err =~ /could not read Username for/);

        return $self -> self_error("Clone failed: $err\n");
    }

    $self -> _write_config_file($target, $username)
        or return undef;

    # clone is complete, move the clone into position
    $res = `sudo $self->{settings}->{repostools}->{postgit} $safename`;
    return $self -> self_error("Clone failed: $res") if($res);

    return 1;
}


## @method private $ _pull_cleanup($target, $username, $safename)
# Clean up after a pull (whether successful or not).
#
# @param target   The target path for the temporary directory.
# @param username The username of the user doing the pull
# @param safename The safe name of the repository
# @return true on success, undef on error.
sub _pull_cleanup {
    my $self     = shift;
    my $target   = shift;
    my $username = shift;
    my $safename = shift;

    $self -> _write_config_file($target, $username)
        or return undef;

    # pull is complete, move the repository into position
    my $res = `sudo $self->{settings}->{repostools}->{postgit} $safename`;
    return $self -> self_error("Pull failed: $res") if($res);

    return 1;
}


## @method $ pull_repository($username)
# Pull updates for the user's repository.
#
# @param username   The name of the user cloning the repository.
# @return true on success, undef on error.
sub pull_repository {
    my $self       = shift;
    my $username   = lc(shift);

    $self -> clear_error();

    my ($safename) = $username =~/^([.\w]+)$/;
    return $self -> self_error("Pull failed: illegal username specified") if(!$safename);

    # perform the pre-pull step
    my $res = `sudo $self->{settings}->{repostools}->{prepull} $safename`;
    return $self -> self_error("Pull failed: $res") if($res);

    # Do the pull
    my $target = blind_untaint(path_join($self -> {"settings"} -> {"git"} -> {"webtempdir"}, $safename));
    my $output = eval {
        my $repo = Git::Repository -> new(work_tree => $target, { git => "/usr/bin/git", input => "", fatal => [1, 127, 128, 129] });
        $repo -> run("pull");
    };

    if(my $err = $@) {
        my $cleanup = $self -> _pull_cleanup($target, $username, $safename);

        return $self -> self_error("Pull failed: unable to update from a private project. Make the project public and try again.")
            if($err =~ /could not read Username for/);

        return $self -> self_error("Pull failed (git error): $err\n");
    }

    return $self -> _pull_cleanup($target, $username, $safename);
}


## @method $ write_config($username)
# If the user's web directory exists, write a new config.inc.php to it
#
# @param username The name of the user to set the config for
# @return true on success, undef on error
sub write_config {
    my $self     = shift;
    my $username = lc(shift);

    $self -> clear_error();

    my ($safename) = $username =~/^([.\w]+)$/;
    return $self -> self_error("Config write failed: illegal username specified") if(!$safename);

    # Do nothing if the user has no web tree
    if($self -> user_web_repo_exists($safename)) {
        # perform the pre-pull step. Need to do this to get write permission!
        my $res = `sudo $self->{settings}->{repostools}->{prepull} $safename`;
        return $self -> self_error("Config write failed: $res") if($res);

        my $target = blind_untaint(path_join($self -> {"settings"} -> {"git"} -> {"webtempdir"}, $safename));
        $self -> _write_config_file($target, $safename)
            or return undef;

        # Move the web tree back again
        $res = `sudo $self->{settings}->{repostools}->{postgit} $safename`;
        return $self -> self_error("Pull failed: $res") if($res);
    }

    return 1;
}


# ============================================================================
#  Private and ghastly internals


## @method private $ _write_config_file($dir, $username)
# Write the config.inc.php for the specified user into the directory specified.
#
# @param dir      The directory to write the config.inc.php file.
# @param username The name of the user to create the file for
# @return true on success, undef on error.
sub _write_config_file {
    my $self     = shift;
    my $dir      = shift;
    my $username = shift;

    $self -> clear_error();

    # Do nothing if the user has no database
    if($self -> {"databases"} -> user_database_exists($username)) {
        my $configname = path_join($dir, "config.inc.php");
        my $pass = $self -> {"databases"} -> get_user_password($username)
            or return $self -> self_error($self -> {"databases"} -> errstr());

        my $config = "<?php\n\n\$database_host = \"dbhost.cs.man.ac.uk\";\n\$database_user = \"$username\";\n\$database_pass = \"$pass\";\n\$database_name = \"$username\";\n\n?>\n";

        eval { save_file($configname, $config); };
        return $self -> self_error("Unable to write configuration file: $@") if($@);
    }

    return 1;
}
1;

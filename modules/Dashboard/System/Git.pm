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


## @method $ user_web_repo_list($username)
# Generate a list of published repositories inside the user's web directory.
#
# @param username The username of the user to search for a repo for.
# @return A reference to an array of repository descriptions on success,
#         undef on error.
sub user_web_repo_list {
    my $self     = shift;
    my $username = lc(shift);

    $self -> clear_error();

    # First check in the base directory
    my $reposdata = $self -> user_web_repo_exists($username);
    return [ $reposdata ] if($reposdata);

    # No repository in the base, scan for subdirs
    opendir(USERDIR, path_join($self -> {"settings"} -> {"git"} -> {"webbasedir"}, $username))
        or return $self -> self_error("Unable to open userpath for $username: $!");
    my @entries = readdir(USERDIR);
    closedir(USERDIR);

    my @repos;
    foreach my $entry (sort @entries) {
        next if($entry =~ /^\.*$/); # user_web_repo_exists checks for valid path

        $reposdata = $self -> user_web_repo_exists($username, $entry);
        push(@repos, $reposdata)
            if($reposdata);
    }

    return \@repos;
}


### @method $ user_web_repo_exists($username, $subdir)
# Determine whether a repo exists in at the location specified in the
# user's web directory. If no subdir is set, the root is checked for a
# published project.
#
# @param username The username of the user to check for a repo for.
# @param subdir   The subdir to check for a repository.
# @return A reference to a hash containing the repository info on success,
#         undef on error or if the subdir does not exist/contain a
#         repository.
sub user_web_repo_exists {
    my $self     = shift;
    my $username = lc(shift);
    my $subdir   = shift;

    # Can't be a valid repository if it doesn't exist
    my $userpath = path_join($self -> {"settings"} -> {"git"} -> {"webbasedir"}, $username, $subdir);#
    return undef if(!-d $userpath);

    $self -> _parse_git_config($userpath, $subdir);
}


## @method $ delete_repository($username, $subdir)
# Delete the repository associated with the specified user.
#
# @param username   The name of the user cloning the repository.
# @param subdir     The subdir containing the repository to delete.
# @return true on success, undef on error.
sub delete_repository {
    my $self       = shift;
    my $username   = lc(shift);
    my $subdir     = shift || "";

    $self -> clear_error();

    my ($safename) = $username =~/^([.\w]+)$/;
    return $self -> self_error("Delete failed: illegal username specified") if(!$safename);

    my ($safedir) = $subdir =~ /^(\w+)?$/;
    return $self -> self_error("Delete failed: illegal subdir specified") if($subdir && !defined($safedir));
    $safedir = "" if(!defined($safedir));

    # perform the pre-clone step
    my $res = `sudo $self->{settings}->{repostools}->{preclone} $safename $safedir`;
    return $self -> self_error("Delete failed: $res") if($res);

    # that should actually be all that is needed...
    return 1;
}


## @method $ clone_repository($repository, $username, $subdir)
# Clone the specified repository and move it into the user's web space.
#
# @param repository The URL of the repository to clone.
# @param username   The name of the user cloning the repository.
# @param subdir     The name of the subdirectory to clone into.
# @return true on success, undef on error.
sub clone_repository {
    my $self       = shift;
    my $repository = shift;
    my $username   = lc(shift);
    my $subdir     = shift || "";

    $self -> clear_error();

    my ($safename) = $username =~/^([.\w]+)$/;
    return $self -> self_error("Clone failed: illegal username specified") if(!$safename);

    my ($safedir) = $subdir =~ /^(\w+)?$/;
    return $self -> self_error("Clone failed: illegal subdir specified") if($subdir && !defined($safedir));
    $safedir = "" if(!defined($safedir));

    # perform the pre-clone step
    my $res = `sudo $self->{settings}->{repostools}->{preclone} $safename $safedir`;
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

    # clone is complete, move the clone into position
    $res = `sudo $self->{settings}->{repostools}->{postgit} $safename $safedir`;
    return $self -> self_error("Clone failed: $res") if($res);

    $self -> _write_config_file(path_join($self -> {"settings"} -> {"git"} -> {"webbasedir"}, $safename), $username)
        or return undef;

    return 1;
}


## @method private $ _pull_cleanup($target, $username, $safename, $safedir)
# Clean up after a pull (whether successful or not).
#
# @param target   The target path for the temporary directory.
# @param username The username of the user doing the pull
# @param safename The safe name of the repository
# @param safedir  The safe name of the subdirectory
# @return true on success, undef on error.
sub _pull_cleanup {
    my $self     = shift;
    my $target   = shift;
    my $username = shift;
    my $safename = shift;
    my $safedir  = shift;

    # pull is complete, move the repository into position
    my $res = `sudo $self->{settings}->{repostools}->{postgit} $safename $safedir`;
    return $self -> self_error("Pull failed: $res") if($res);

    $self -> _write_config_file($target, $username)
        or return undef;

    return 1;
}


## @method $ pull_repository($username, $subdir)
# Pull updates for the user's repository.
#
# @param username   The name of the user cloning the repository.
# @param subdir     The name of the subdirectory to clone into.
# @return true on success, undef on error.
sub pull_repository {
    my $self       = shift;
    my $username   = lc(shift);
    my $subdir     = shift || "";

    $self -> clear_error();

    my ($safename) = $username =~/^([.\w]+)$/;
    return $self -> self_error("Pull failed: illegal username specified") if(!$safename);

    my ($safedir) = $subdir =~ /^(\w+)?$/;
    return $self -> self_error("Clone failed: illegal subdir specified") if($subdir && !defined($safedir));
    $safedir = "" if(!defined($safedir));

    # perform the pre-pull step
    my $res = `sudo $self->{settings}->{repostools}->{prepull} $safename $safedir`;
    return $self -> self_error("Pull failed: $res") if($res);

    # Do the pull
    my $target = blind_untaint(path_join($self -> {"settings"} -> {"git"} -> {"webtempdir"}, $safename));
    my $output = eval {
        my $repo = Git::Repository -> new(work_tree => $target, { git => "/usr/bin/git", input => "", fatal => [1, 127, 128, 129] });
        $repo -> run("pull");
    };

    my $basedir = path_join($self -> {"settings"} -> {"git"} -> {"webbasedir"}, $safename);
    if(my $err = $@) {
        my $cleanup = $self -> _pull_cleanup($basedir, $username, $safename, $safedir);

        return $self -> self_error("Pull failed: unable to update from a private project. Make the project public and try again.")
            if($err =~ /could not read Username for/);

        return $self -> self_error("Pull failed (git error): $err\n");
    }

    return $self -> _pull_cleanup($basedir, $username, $safename, $safedir);
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
    my $target = blind_untaint(path_join($self -> {"settings"} -> {"git"} -> {"webbasedir"}, $safename));
    if(-d $target) {
        $self -> _write_config_file($target, $safename)
            or return undef;
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

    my $configname = path_join($dir, "config.inc.php");

    # Do nothing if the user has no database
    if($self -> {"databases"} -> user_database_exists($username)) {
        my $pass = $self -> {"databases"} -> get_user_password($username)
            or return $self -> self_error($self -> {"databases"} -> errstr());

        my $groups = $self -> {"databases"} -> get_user_group_databases($username);
        my $grouplist = "";
        if($groups) {
            foreach my $database (sort keys(%{$groups})) {
                next if($database eq "_internal");

                $grouplist .= "    '$database',\n";
            }
        }
        $grouplist = "\$group_dbnames = array(\n$grouplist);\n\n" if($grouplist);

        my $config = "<?php\n\n\$database_host = \"dbhost.cs.man.ac.uk\";\n\$database_user = \"$username\";\n\$database_pass = \"$pass\";\n\$database_name = \"$username\";\n\n$grouplist?>\n";

        eval { save_file($configname, $config); };
        return $self -> self_error("Unable to write configuration file: $@") if($@);

        my $res = `/usr/bin/chmod o= '$configname' 2>&1`;
        return $self -> self_error("Unable to write configuration file: $res") if($res);
    } else {
        unlink $configname or return $self -> self_error("Unable to remove old config file: $!")
            if(-f $configname);
    }

    return 1;
}


## @method private $ _parse_git_config($path, $subdir)
# Parse the specified git config, and return a hash containing the
# config information pertinent to Dashboard.
#
# @param path   The path to look in for a .git directory.
# @param subdir The subdirectory of the user's web space the path corresponds to.
# @return A reference to a hash if a git repository is found, undef if
#         it is not (or an error occurred)
sub _parse_git_config {
    my $self   = shift;
    my $path   = shift;
    my $subdir = shift;

    my $config = path_join($path, ".git", "config");
    return undef if(!-f $config);

    # Hey, what do you know, ConfigMicro can parse git configs!
    my $settings = Webperl::ConfigMicro -> new($config)
        or return $self -> self_error("Repository check failed: ".$Webperl::SystemModule::errstr);

    return { "origin" => $settings -> {'remote "origin"'} -> {"url"},
             "subdir" => $subdir,
             "path"   => $path
           };
}

1;

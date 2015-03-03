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
use Webperl::Utils qw(path_join blind_untaint load_file save_file);
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

    $self -> write_primary_redirect($safename) or return undef
        if($subdir);

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

    $self -> write_config($safename)
        or return undef;

    $self -> write_primary_redirect($safename) or return undef
        if($subdir);

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

    $self -> write_config($safename)
        or return undef;

    $self -> write_primary_redirect($safename) or return undef
        if($safedir);

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
# If the user's web directory exists, write a new config.inc.php to it. If the
# user has multiple project subdirectories, this will (re)build the config files
# for all the project directories.
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

        # User has web tree, need to write config into each git repo
        my $user_repos = $self -> user_web_repo_list($safename);
        foreach my $repo (@{$user_repos}) {
            $target = path_join($self -> {"settings"} -> {"git"} -> {"webbasedir"}, $safename, $repo -> {"subdir"});
            $self -> _write_config_file($target, $safename, $repo -> {"subdir"})
                or return undef;
        }
    }

    return 1;
}


## @method $ write_primary_redirect($username)
# Update the primary site redirect information in the user's htaccess.
#
# @param username The name of the user to write the htaccess for.
# @return true on success, undef on error.
sub write_primary_redirect {
    my $self     = shift;
    my $username = lc(shift);

    # do nothing if the user's web directory doesn't exist at all
    return 1 if(!-d path_join($self -> {"settings"} -> {"git"} -> {"webbasedir"}, $username));

    # Does the user have a primary set?
    my $primary = $self -> {"repostools"} -> get_primary_site($username);
    if($primary) {
        # Is it valid?
        if(!$self -> user_web_repo_exists($username, $primary)) {
            # Nope, nuke the setting
            $self -> {"repostools"} -> set_primary_site($username, "");
            $primary = "";
        }
    }

    # Process the htaccess
    my $htaccess = path_join($self -> {"settings"} -> {"git"} -> {"webbasedir"}, $username, ".htaccess");
    my $contents = "";
    if(-f $htaccess) {
        my $res = `/bin/chmod u+w '$htaccess' 2>&1`;
        return $self -> self_error("Unable to write htaccess file: $res") if($res);

        $contents = load_file($htaccess)
            or return $self -> self_error("Error opening htaccess file: $!");

        # Kill any pre-existing settings
        $contents =~ s|RewriteEngine On\nRewriteRule \^\$ /$username/\w+/ \[L,R=301\]\n||g;
    }

    $contents .= "RewriteEngine On\nRewriteRule ^\$ /$username/$primary/ [L,R=301]\n"
        if($primary);
    eval { save_file($htaccess, $contents); };
    return $self -> self_error("Unable to write htaccess file: $@") if($@);

    my $res = `/bin/chmod u-w,g-w,o= '$htaccess' 2>&1`;
    return $self -> self_error("Unable to write htaccess file: $res") if($res);

    return 1;
}



# ============================================================================
#  Private and ghastly internals


## @method private $ _write_config_file($dir, $username, $projectdir)
# Write the config.inc.php for the specified user into the directory specified.
#
# @param dir        The directory to write the config.inc.php file.
# @param username   The name of the user to create the file for
# @param projectdir The subdirectory the project is in.
# @return true on success, undef on error.
sub _write_config_file {
    my $self       = shift;
    my $dir        = shift;
    my $username   = shift;
    my $projectdir = shift;

    $self -> clear_error();

    my $configname = path_join($dir, "config.inc.php");

    # Do nothing if the user has no database(s)
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

        my ($dbh, $dbhost, $dbuser, $dbpass) = $self -> {"databases"} -> get_user_database_server($username);
        my $dbname = $self -> {"databases"} -> get_user_database($username, $projectdir) || $username;

        my $config = "<?php\n\n\$database_host = \"".($dbhost || "Unknown error occurred")."\";\n".
                     "\$database_user = \"$username\";\n" .
                     "\$database_pass = \"$pass\";\n".
                     "\$database_name = \"$dbname\";\n".
                     "\n$grouplist?>\n";

        my $res;
        if(-f $configname) {
            $res = `/bin/chmod 640 '$configname' 2>&1`;
            return $self -> self_error("Unable to write configuration file: $res") if($res);
        }

        eval { save_file($configname, $config); };
        return $self -> self_error("Unable to write configuration file: $@") if($@);

        $res = `/bin/chmod 440 '$configname' 2>&1`;
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

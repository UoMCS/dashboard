## @file
# This file contains the implementation of the core dashboard interface.
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
package Dashboard::Dashboard;

use strict;
use experimental 'smartmatch';
use base qw(Dashboard); # This class extends the Dashboard block class
use v5.12;
use Webperl::Utils qw(path_join);
use Data::Dumper;

# ============================================================================
#  Support

## @method private $ _build_source_options($username)
# Generate the list of databases available for cloning by the user. This will
# produce an array of hashes suitable for passing to build_optionlist() or
# validate_options(), each hash containing the name of a database the user
# can use as a source for a new database. This will be a longer list than
# the user can directly access - in theory, every non-system database on the
# server will be listed!
#
# @param username The name of the user to fetch the source options for (this
#                 may be used to select a database server to use)
# @return A reference to an array of hashes containing name and value keys.
sub _build_source_options {
    my $self     = shift;
    my $username = shift;

    my $databases = $self -> {"system"} -> {"databases"} -> get_database_server_databases($username);

    my @options = ( { "name" => $self -> {"template"} -> replace_langvar("DATABASE_EXTRA_NONE"),
                      "value" => "" });
    foreach my $db (@{$databases}) {
        push(@options, { "name" => $db, "value" => $db });
    }

    return \@options;
}


## @method private $ _build_extra_databases($username)
# Generate a list of databases the user has access to. This returns the *user's*
# databases, rather than all databases on the server, in a form suitable to
# pass to build_optionlist and validate_options.
#
# @param username The name of the user to fetch the databases for.
# @return A reference to an array of hashes containing name and value keys.
sub _build_extra_databases {
    my $self     = shift;
    my $username = shift;

    my $userdbs = $self -> {"system"} -> {"databases"} -> get_user_databases($username);
    my @options = ( );
    foreach my $database (@{$userdbs}) {
        push(@options, { "name" => $database -> {"name"}, "value" => $database -> {"name"} });
    }

    return \@options;
}


# ============================================================================
#  Repository/web related

## @method private @ _validate_repository_id()
# Determine whether the user has set a subpath to operate on, and if so whether
# it corresponds to a valid path.
#
# @return Two values: a string containing any error messages generated during
#         validation, and the subpath string. If the subpath has been specified
#         but corresponds to the root, this will be the empty string.
sub _validate_repository_id {
    my $self = shift;
    my $user = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"}); # force lowercase for safety

    # Check whether an path has been specified
    my ($path, $error) = $self -> validate_string("id", {"required"   => 0,
                                                         "nicename"   => $self -> {"template"} -> replace_langvar("WEBSITE_ID"),
                                                         "maxlen"     => 24,
                                                         "formattest" => '^(-|\w+)?$',
                                                         "formatdesc" => $self -> {"template"} -> replace_langvar("WEBSITE_ERR_BADPATH"),
                                                  });
    return ($error, "") if($error);

    # If the path is -, empty it so it can be used 'as is'
    $path = "" if($path eq "-");

    # Does it exist?
    my $exists = $self -> {"system"} -> {"git"} -> user_web_repo_exists($user -> {"username"}, $path);
    return ($self -> {"template"} -> replace_langvar("WEBSITE_ERR_BADID"), $path) unless($exists);

    return ("", $path);
}


## @method private @ _validate_primary_id()
# Determine whether the user has set a subpath to use as the primary for the
# user's site, and if it corresponds to a valid path.
#
# @return Two values: a string containing any error messages generated during
#         validation, and the subpath string. If the subpath has been specified
#         but corresponds to the root, this will be the empty string.
sub _validate_primary_id {
    my $self = shift;
    my $user = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"}); # force lowercase for safety

    # Users can only set a primary if they have subdirectories
    my $repos = $self -> {"system"} -> {"git"} -> user_web_repo_list($user -> {"username"});
    return $self -> {"template"} -> replace_langvar("WEBSITE_ERR_NOREPOS")
        if(!$repos || !scalar(@{$repos}));

    # Build the options list for validation, and check for root projects at the same time
    my $hasroot = 0;
    my @options = ({"value" => "-",
                    "name"  => $self -> {"template"} -> replace_langvar("WEBSITE_PRIMINDEX")});
    foreach my $entry (@{$repos}) {
        $hasroot = 1 if(!$entry -> {"subdir"});
        push(@options, { "value" => $entry -> {"subdir"},
                         "name"  => path_join($self -> {"settings"} -> {"git"} -> {"webbaseurl"}, lc($user -> {"username"}), $entry -> {"subdir"},"/"),
                       });
    }

    return $self -> {"template"} -> replace_langvar("WEBSITE_ERR_GOTROOT")
        if($hasroot);

    # Check whether an path has been specified
    my ($path, $error) = $self -> validate_options("primary", {"required" => 1,
                                                               "nicename" => $self -> {"template"} -> replace_langvar("WEBSITE_PRIMARY"),
                                                               "source"   => \@options,
                                                  });
    return ($error, "") if($error);

    # If the path is -, empty it so it can be used 'as is'
    $path = "" if($path eq "-");

    # No errors, and path is valid.
    return ("", $path);
}


## @method private $ _validate_repository_fields($args, $user)
# Determine whether the repository field set by the user is valid and appears
# to correspond to a possible repository.
#
# @param args A reference to a hash to store validated data in.
# @param user A reference to the user data for the user submitting data.
# @return empty string on success, otherwise an error string.
sub _validate_repository_fields {
    my $self = shift;
    my $args = shift;
    my $user = shift;
    my ($errors, $error) = ("", "");

    ($args -> {"web-repos"}, $error) = $self -> validate_string("web-repos", {"required" => 1,
                                                                              "nicename" => $self -> {"template"} -> replace_langvar("WEBSITE_REPOS"),
                                                                              "minlen"   => 8,
                                                                              "formattest" => $self -> {"formats"} -> {"url"},
                                                                              "formatdesc" => $self -> {"template"} -> replace_langvar("WEBSITE_ERR_BADREPO"),
                                                                });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => $error}) if($error);

    # Force .git on the end of the url
    if($args -> {"web-repos"}) {
        $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => "{L_WEBSITE_NEEDGIT}"})
            unless($args -> {"web-repos"} =~ /\.git$/i);
    }

    ($args -> {"web-path"}, $error) = $self -> validate_string("web-path", {"required"   => 0,
                                                                            "nicename"   => $self -> {"template"} -> replace_langvar("WEBSITE_PATH"),
                                                                            "maxlen"     => 24,
                                                                            "formattest" => '^(\w+)?$',
                                                                            "formatdesc" => $self -> {"template"} -> replace_langvar("WEBSITE_ERR_BADPATH"),
                                                                });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => $error}) if($error);

    # If no path is specified, it's an attempt to publish in the root
    if(!defined($args -> {"web-path"}) || $args -> {"web-path"} eq "") {
        # Can only publish in the root if there are no projects published already
        my $reposlist = $self -> {"system"} -> {"git"} -> user_web_repo_list($user -> {"username"});

        # If the user has checked out projects, work out which error to send back
        if($reposlist && scalar(@{$reposlist})) {
            # Default to assuming the base path is in use
            $error = "{L_WEBSITE_ERR_BASEUSED}";

            # If the path is set in the first entry (which implies it is set in all others)
            # then the user has one or more published projects in subdirs
            $error = "{L_WEBSITE_ERR_GOTPROJ}"
                if($reposlist -> [0] -> {"path"});

            $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => $error});
        }

    # A path has been specified, make sure a project doesn't already exist there
    } else {
        my $exists = $self -> {"system"} -> {"git"} -> user_web_repo_exists($user -> {"username"}, $args -> {"web-path"});

        $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => "{L_WEBSITE_ERR_EXISTS}"})
            if($exists);
    }

    return $errors;
}


## @method private @ _validate_repository()
# Determine whether the repository field set by the user is valid and appears
# to correspond to a possible repository. If it is, perform the clone process
# for the user.
#
# @return Two values: a string containing any error messages generated during
#         validation, and a reference to a hash containing the arguments
#         parsed from submitted data.
sub _validate_repository {
    my $self = shift;
    my ($args, $errors, $error) = ({}, "", "", undef);
    my $user = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"}); # force lowercase for safety

    $error = $self -> _validate_repository_fields($args, $user);
    $errors .= $error if($error);

    return ($self -> {"template"} -> load_template("error/error_list.tem", {"***message***" => "{L_WEBSITE_CLONE_FAIL}",
                                                                            "***errors***"  => $errors}), $args)
        if($errors);

    $self -> log("repository", "Cloning ".$args -> {"web-repos"}." to ".$user -> {"username"});

    # The respository appears to be valid, do the clone
    $self -> {"system"} -> {"git"} -> clone_repository($args -> {"web-repos"}, $user -> {"username"}, $args -> {"web-path"}, $self -> check_permission('extended.access'))
        or return ($self -> {"template"} -> load_template("error/error_list.tem", {"***message***" => "{L_WEBSITE_CLONE_FAIL}",
                                                                                   "***errors***"  => $self -> {"template"} -> load_template("error/error_item.tem",
                                                                                                                                             {"***error***" => $self -> {"system"} -> {"git"} -> errstr(),
                                                                                                                                             })
                                                          }), $args);

    $self -> {"system"} -> {"repostools"} -> set_user_token($args -> {"web-repos"}, $user)
        or return ($self -> {"template"} -> load_template("error/error_list.tem", {"***message***" => "{L_WEBSITE_CLONE_FAIL}",
                                                                                   "***errors***"  => $self -> {"template"} -> load_template("error/error_item.tem",
                                                                                                                                             {"***error***" => $self -> {"system"} -> {"repostools"} -> errstr(),
                                                                                                                                             })
                                                          }), $args);

    return ($errors, $args);
}


## @method private $ _validate_change_repository($path)
# Change the repository at the specified path to a new origin entered by the user.
#
# @param path The path to write the new repository into. This will destroy anything
#             already there, and it must have been checked with _validate_repository_id().
# @return undef on success, otherwise an error message.
sub _validate_change_repository {
    my $self = shift;
    my $path = shift;
    my $user = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"}); # force lowercase for safety

    my ($repos, $error) = $self -> validate_string("web-repos", {"required" => 1,
                                                                 "nicename" => $self -> {"template"} -> replace_langvar("WEBSITE_REPOS"),
                                                                 "minlen"   => 8,
                                                                 "formattest" => $self -> {"formats"} -> {"url"},
                                                                 "formatdesc" => $self -> {"template"} -> replace_langvar("WEBSITE_ERR_BADREPO"),
                                                                });
    return ($error, undef) if($error);

    # The respository appears to be valid, do the clone
    $self -> {"system"} -> {"git"} -> clone_repository($repos, $user -> {"username"}, $path, $self -> check_permission('extended.access'))
        or return $self -> {"system"} -> {"git"} -> errstr();

    return (undef, $repos);
}


## @method private $ _set_repository()
# Set the user's repository to the repository they specify in the form, if possible.
#
# @return Two strings, the first containing the page title, the second containing the
#         page content.
sub _add_repository {
    my $self = shift;
    my $error = "";
    my $args  = {};

    ($error, $args) = $self -> _validate_repository();
    if(!$error) {
        my $highlight = $args -> {"web-path"} ? "site-".$args -> {"web-path"} : "site--";

        return $self -> _generate_dashboard(undef, undef, undef, $highlight);
    }

    return $self -> _generate_dashboard($args, $error);
}


# ============================================================================
#  Database related

## @method private $ _validate_database_fields($args)
# Determine whether the password fields set by the user are valid.
#
# @param args A reference to a hash to store validated data in.
# @return empty string on success, otherwise an error string.
sub _validate_database_fields {
    my $self = shift;
    my $args = shift;
    my ($errors, $error) = ("", "");

    ($args -> {"db-pass"}, $error) = $self -> validate_string("db-pass", {"required"   => 1,
                                                                          "nicename"   => $self -> {"template"} -> replace_langvar("DATABASE_PASSWORD"),
                                                                          "minlen"     => 8,
                                                                          "formattest" => '^[-.+\w]+$',
                                                                          "formatdesc" => $self -> {"template"} -> replace_langvar("DATABASE_PASSERR"),
                                                                });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => $error}) if($error);

    ($args -> {"db-conf"}, $error) = $self -> validate_string("db-conf", {"required"   => 1,
                                                                          "nicename"   => $self -> {"template"} -> replace_langvar("DATABASE_PASSCONF"),
                                                                          "minlen"     => 8,
                                                                          "formattest" => '^[-.+\w]+$',
                                                                          "formatdesc" => $self -> {"template"} -> replace_langvar("DATABASE_PASSERR"),
                                                                });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => $error}) if($error);

    # Passwords must match
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => "{L_DATABASE_PASSMATCH}"})
        unless(!$args -> {"db-pass"} || !$args -> {"db-conf"} || $args -> {"db-pass"} eq $args -> {"db-conf"});

    return $errors;
}


## @method private @ _validate_database()
# Determine whether the password fields set by the user are valid and if so set up
# the user's database.
sub _validate_database {
    my $self = shift;
    my ($args, $errors, $error) = ({}, "", "", undef);
    my $user = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"}); # force lowercase for safety

    $error = $self -> _validate_database_fields($args);
    $errors .= $error if($error);

    return ($self -> {"template"} -> load_template("error/error_list.tem", {"***message***" => "{L_DATABASE_FAIL}",
                                                                            "***errors***"  => $errors}), $args)
        if($errors);

    $self -> log("database", "Setting up account for user ".$user -> {"username"});

    # Files are valid, do the create/reset
    $self -> {"system"} -> {"databases"} -> setup_user_account($user, $args -> {"db-pass"})
        or return ($self -> {"template"} -> load_template("error/error_list.tem", {"***message***" => "{L_DATABASE_FAIL}",
                                                                                   "***errors***"  => $self -> {"template"} -> load_template("error/error_item.tem",
                                                                                                                                             {"***error***" => $self -> {"system"} -> {"databases"} -> errstr(),
                                                                                                                                             })
                                                          }), $args);

    # Write the config file if needed
    $self -> log("database", "Writing config file for user ".$user -> {"username"});
    $self -> {"system"} -> {"git"} -> write_config($user -> {"username"})
        or return ($self -> {"template"} -> load_template("error/error_list.tem", {"***message***" => "{L_DATABASE_FAIL}",
                                                                                   "***errors***"  => $self -> {"template"} -> load_template("error/error_item.tem",
                                                                                                                                             {"***error***" => $self -> {"system"} -> {"git"} -> errstr(),
                                                                                                                                             })
                                                          }), $args);

    return ($errors, $args);
}


## @method private $ _make_database()
# Create the user's database account and table.
#
# @return Two strings, the first containing the page title, the second containing the
#         page content.
sub _make_database {
    my $self = shift;
    my $error = "";
    my $args  = {};

    ($error, $args) = $self -> _validate_database();
    if(!$error) {
        return $self -> _generate_dashboard($args);
    }

    return $self -> _generate_dashboard($args, $error);
}


## @method private @ _hilight_dbadd($dbname)
# Given a databse name, generate the dashboard page including a highlight for the
# specified database. If the database does not belong to the user, this does
# nothing.
#
# @param dbname The name of the database to highlight in the user's list
# @return Two strings, the first containing the page title, the second containing the
#         page content.
sub _hilight_dbadd {
    my $self   = shift;
    my $dbname = shift;

    # Get the current user's information
    my $user  = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"});

    # If the database is valid and owned by the user, highlight it.
    my $database = $self -> {"system"} -> {"databases"} -> get_user_database_id($user -> {"username"}, $dbname);
    my $highlight = $database ? "extradb-".$dbname : "";

    return $self -> _generate_dashboard(undef, undef, undef, $highlight);
}

# ============================================================================
#  Content generation

## @method private $ _generate_web_publish($user, $args)
# Generate a block containing the information about/options for the user
# related to publishing their website via git.
#
# @param user A reference to the user's data hash.
# @param args A reference to a hash containing arguments to use in the
#             form fields as needed.
# @return A string containing the web publishing block.
sub _generate_web_publish {
    my $self = shift;
    my $user = shift;
    my $args = shift;

    # Fetch the list of repositories the user has published, falling back on the
    # default 'no repositories' content if they have none.
    my $repos = $self -> {"system"} -> {"git"} -> user_web_repo_list($user -> {"username"});
    return $self -> {"template"} -> load_template("dashboard/web/norepo.tem", {"***web-repos***" => $args -> {"web-repos"},
                                                                               "***web-path***"  => $args -> {"web-path"},
                                                                               "***docs***"      => $self -> get_documentation_url("web"),
                                                                               "***form_url***"  => $self -> build_url(block => "manage", "pathinfo" => [ "addrepos" ])})
        if(!$repos || !scalar(@{$repos}));


    my $rlist = "";
    my $hasroot = 0;
    my @options = ({"value" => "-",
                    "name"  => $self -> {"template"} -> replace_langvar("WEBSITE_PRIMINDEX")});
    # Building the list of databases for the user is safe - they won't be given the option
    # or be able to do anything if they don't have extended.databases
    my $databases = $self -> _build_extra_databases($user -> {"username"});

    # Build the list of repositories and supporting options
    foreach my $entry (@{$repos}) {
        my $extradbs = "";

        # Users with additional permissions need to be able to select a database for each project.
        if($self -> check_permission('extended.databases')) {
            my $database = $self -> {"system"} -> {"databases"} -> get_user_database($user -> {"username"}, $entry -> {"subdir"});

            $extradbs = $self -> {"template"} -> load_template("dashboard/web/repo-extrarow.tem", {"***id***"        => $entry -> {"subdir"} || "-",
                                                                                                   "***databases***" => $self -> {"template"} -> build_optionlist($databases, $database)});
        }

        $rlist .= $self -> {"template"} -> load_template("dashboard/web/repo-row.tem", {"***url***"     => path_join($self -> {"settings"} -> {"git"} -> {"webbaseurl"}, $user -> {"username"}, $entry -> {"subdir"},"/"),
                                                                                        "***subdir***"  => path_join($self -> {"settings"} -> {"git"} -> {"webbaseurl"}, $user -> {"username"}, $entry -> {"subdir"},"/"),
                                                                                        "***extradb***" => $extradbs,
                                                                                        "***id***"      => $entry -> {"subdir"} || "-",
                                                                                        "***source***"  => $entry -> {"origin"} });
        $hasroot = 1 if(!$entry -> {"subdir"});

        push(@options, { "value" => $entry -> {"subdir"},
                         "name"  => path_join($self -> {"settings"} -> {"git"} -> {"webbaseurl"}, lc($user -> {"username"}), $entry -> {"subdir"},"/"),
                       });
    }

    my $primary = $self -> {"template"} -> load_template("dashboard/web/primary_".($hasroot ? "disabled.tem" : "enabled.tem"),
                                                         {"***sites***"   => $self -> {"template"} -> build_optionlist(\@options, $self -> {"system"} -> {"repostools"} -> get_primary_site($user -> {"username"})),
                                                          "***baseurl***" => path_join($self -> {"settings"} -> {"git"} -> {"webbaseurl"}, $user -> {"username"})});

    my $addform = $self -> {"template"} -> load_template("dashboard/web/addform_".($hasroot ? "gotroot.tem" : "noroot.tem"),
                                                         { "***web-repos***" => $args -> {"web-repos"},
                                                           "***web-path***"  => $args -> {"web-path"},
                                                           "***form_url***"  => $self -> build_url(block => "manage", "pathinfo" => [ "addrepos" ])});

    my $extradbs = $self -> {"template"} -> load_template("dashboard/web/repo-extrahead.tem")
        if($self -> check_permission('extended.databases'));

    return $self -> {"template"} -> load_template("dashboard/web/repo.tem"  , {"***extradbs***"  => $extradbs,
                                                                               "***repos***"     => $rlist,
                                                                               "***addform***"   => $addform,
                                                                               "***primary***"   => $primary,
                                                                               "***docs***"      => $self -> get_documentation_url("web"),
                                                                               "***web_url***"   => path_join($self -> {"settings"} -> {"git"} -> {"webbaseurl"}, $user -> {"username"},"/"),
                                                                               "***pull_url***"  => $self -> build_url(block => "manage", "pathinfo" => [ "pullrepos" ]),
                                                                               "***nuke_url***"  => $self -> build_url(block => "manage", "pathinfo" => [ "nukerepos" ]),
                                                                               "***clone_url***" => $self -> build_url(block => "manage", "pathinfo" => [ "setrepos" ]),
                                                  });

}


## @method private $ _generate_group_database($groups)
# Generate a block containing the group database information for the user.
#
# @param groups A reference to a hash of group database information hashes.
# @return A string containing the groups database block.
sub _generate_group_database {
    my $self     = shift;
    my $groups   = shift || {};
    my $groupstr = "";

    my $dbnum = 1;
    foreach my $database (sort keys(%{$groups})) {
        next if($database eq "_internal" || !$groups -> {$database} -> {"active"});

        $groupstr .= $self -> {"template"} -> load_template("dashboard/db/grouprow.tem", {"***database***" => $database,
                                                                                          "***num***"      => $dbnum})
    }

    return $self -> {"template"} -> load_template("dashboard/db/groups.tem", {"***rows***" => $groupstr})
        if($groupstr);

    return $self -> {"template"} -> load_template("dashboard/db/nogroups.tem");
}


## @method private $ _generate_extra_databases($user)
# Determines whether the user has the 'extended.databases' capability, and
# if so this generates additional content to include in the dashboard
# page for the user.
#
# @param user A reference to the user's data hash.
# @return A string containing the extra databases content for the user, or
#         an empty string if the user does not have permission to use extra
#         databases.
sub _generate_extra_databases {
    my $self = shift;
    my $user = shift;

    if($self -> check_permission('extended.databases')) {
        my $options = $self -> _build_source_options($user -> {"username"});
        my $databases = $self -> {"system"} -> {"databases"} -> get_user_databases($user -> {"username"});

        my $extradbs = "";
        foreach my $database (@{$databases}) {
            next if($database -> {"name"} eq $user -> {"username"}); # skip the user's default database

            my $reclone = $self -> {"template"} -> load_template("dashboard/db/db-row-reclone.tem", {"***database***" => $database -> {"name"},
                                                                                                     "***id***"       => $database -> {"name"}})
                if($database -> {"source"});

            $extradbs .= $self -> {"template"} -> load_template("dashboard/db/db-row.tem", {"***database***" => $database -> {"name"},
                                                                                            "***source***"   => $database -> {"source"},
                                                                                            "***id***"       => $database -> {"name"},
                                                                                            "***reclone***"  => $reclone});
        }

        return $self -> {"template"} -> load_template("dashboard/db/extradbs.tem", {"***extradbs***" => $extradbs,
                                                                                    "***username***" => $user -> {"username"},
                                                                                    "***otherdbs***" => $self -> {"template"} -> build_optionlist($options) });
    }

    return "";
}


## @method private $ _generate_database($user, $args)
# Generate a block containing the information about/options for the user
# related to their database and/or group databases.
#
# @param user A reference to the user's data hash.
# @param args A reference to a hash containing arguments to use in the
#             form fields as needed.
# @return A string containing the web publishing block.
sub _generate_database {
    my $self = shift;
    my $user = shift;
    my $args = shift;

    # Does the user have a database?
    my $user_hasdb = $self -> {"system"} -> {"databases"} -> user_database_exists($user -> {"username"});
    if(!$user_hasdb) {
        return $self -> {"template"} -> load_template("dashboard/db/nodb.tem", {"***form_url***"  => $self -> build_url(block => "manage", "pathinfo" => [ "newdb" ]),
                                                                                "***docs***"      => $self -> get_documentation_url("db"),
                                                      });
    } else {
        # Get the list of group databases the user should have access to
        my $groups = $self -> {"system"} -> {"userdata"} -> get_user_groupnames($user -> {"username"});

        my $groupdbs = "";
        if($groups) {
           $self -> log("groups", "Doing groups for ".$user -> {"username"}.": ".join(",", @{$groups}));
           $groupdbs = $self -> {"system"} -> {"databases"} -> set_user_group_databases($user -> {"username"}, $groups);
        }

        # Update the config file if there have been changes.
        $self -> {"system"} -> {"git"} -> write_config($user -> {"username"})
            if($groupdbs && $groupdbs -> {"_internal"} -> {"save_config"});

        my ($dbh, $dbhost, $dbuser, $dbpass) = $self -> {"system"} -> {"databases"} -> get_user_database_server($user -> {"username"});

        return $self -> {"template"} -> load_template("dashboard/db/db.tem"  , {"***hostname***" => $dbhost || $self -> {"system"} -> {"databases"} -> errstr(),
                                                                                "***username***" => $user -> {"username"},
                                                                                "***password***" => "{L_DATABASE_PASSWORD_COPOUT}",
                                                                                "***docs***"     => $self -> get_documentation_url("db"),
                                                                                "***groups***"   => $self -> _generate_group_database($groupdbs),
                                                                                "***extradbs***" => $self -> _generate_extra_databases($user),
                                                      });
    }
}


# @method private @ _generate_dashboard($args, $error, $message, $highlight)
# Generate the page content for a dashboard page.
#
# @param args      An optional reference to a hash containing defaults for the form fields.
# @param error     An optional error message to display above the form if needed.
# @param message   An optional info message to display above the form if needed.
# @param highlight an optional ID of the element to highligh in the page after load.
# @return Two strings, the first containing the page title, the second containing the
#         page content.
sub _generate_dashboard {
    my $self      = shift;
    my $args      = shift || { };
    my $error     = shift;
    my $message   = shift;
    my $highlight = shift;

    # Get the current user's information
    my $user  = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"});

    # Build the web publish block
    my $webblock = $self -> _generate_web_publish($user, $args);

    # Build the web publish block
    my $dbblock = $self -> _generate_database($user, $args);

    # Wrap the error in an error box, if needed.
    $error = $self -> {"template"} -> load_template("error/error_box.tem", {"***message***" => $error})
        if($error);

    # and the info box
    $message = $self -> {"template"} -> load_template("dashboard/info_box.tem", {"***message***" => $message})
        if($message);

    $highlight = $self -> {"template"} -> load_template("dashboard/highlight.tem", {"***id***" => $highlight})
        if($highlight);

    return ($self -> {"template"} -> replace_langvar("DASHBOARD_TITLE"),
            $self -> {"template"} -> load_template("dashboard/content.tem", {"***errorbox***"  => $error,
                                                                             "***infobox***"   => $message,
                                                                             "***highlight***" => $highlight,
                                                                             "***webpart***"   => $webblock,
                                                                             "***dbpart***"    => $dbblock,
                                                   }));
}


# ============================================================================
#  API functions - website

## @method private $ _show_token()
# An API function that generates a token information string to send to the
# user.
#
# @return A string containing a block of HTML to return to the user.
sub _show_token {
    my $self   = shift;
    my $user   = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"}); # force lowercase for safety

    $self -> log("repository", "Token requested.");

    my ($errors, $path) = $self -> _validate_repository_id();
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $errors}))
        if($errors);

    my $repos = $self -> {"system"} -> {"git"} -> user_web_repo_exists($user -> {"username"}, $path)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => "{L_WEBSITE_ERR_NOREPO}"}));

    my $token = $self -> {"system"} -> {"repostools"} -> get_user_token($user -> {"user_id"}, $path)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"repostools"} -> errstr()}));

    # If the user doesn't have a token, or it somehow doesn't match the origin, make a new one
    if(!$token -> {"repos_url"} || $token -> {"repos_url"} != $repos -> {"origin"}) {
        $self -> log("repository", "User doesn't have a token, or it is incorrect. Making new");

        $token = $self -> {"system"} -> {"repostools"} -> set_user_token($repos -> {"origin"}, $user, $path)
            or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"repostools"} -> errstr()}));
    }

    return $self -> {"template"} -> load_template("dashboard/web/showtoken.tem", { "***token_url***" => $self -> build_url(fullurl  => 1,
                                                                                                                           block    => "update",
                                                                                                                           api      => [],
                                                                                                                           pathinfo => [],
                                                                                                                           params   => { "token" => $token -> {"token"}})});
}


## @method private $ _update_repository()
# An API function that triggers a git pull on the user's repository.
#
# @return Either a string containing a block of html to send back to the user,
#         or a hash encoding an API error message.
sub _update_repository {
    my $self = shift;
    my $user = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"}); # force lowercase for safety

    $self -> log("repository", "Pulling repository for user ".$user -> {"username"}.", fetching path");

    my ($errors, $path) = $self -> _validate_repository_id();
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $errors}))
        if($errors);

    $self -> log("repository", "Pulling repository for user ".$user -> {"username"}." path = $path");

    $self -> {"system"} -> {"git"} -> pull_repository($user -> {"username"}, $path, $self -> check_permission('extended.access'))
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"git"} -> errstr()}));

    return $self -> {"template"} -> load_template("dashboard/info_box.tem", {"***message***" => "{L_WEBSITE_PULL_SUCCESS}"});
}


## @method private $ _require_repository_delete_confirm()
# An API function that generates a confirmation request to show to the user
# before deleting the user's website.
#
# @return A string containing a block of HTML to return to the user.
sub _require_repository_delete_confirm {
    my $self = shift;

    $self -> log("repository", "Delete confirmation requested.");

    return $self -> {"template"} -> load_template("dashboard/web/confirmnuke.tem");
}


## @method private $ _delete_repository()
# Delete the repository that forms the user's website. This will remove the
# user's web directory entirely, and can not be undone.
#
# @return A hash containing an API response. If the delete succeeded, the response
#         contains the URL to refirect the user to, otherwise it is an error to send
#         to the user.
sub _delete_repository {
    my $self = shift;
    my $user = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"}); # force lowercase for safety

    $self -> log("repository", "Deleting repository for user ".$user -> {"username"}.", fetching path");

    my ($errors, $path) = $self -> _validate_repository_id();
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $errors}))
        if($errors);

    $self -> log("repository", "Deleting repository for user ".$user -> {"username"}." path = $path");

    $self -> {"system"} -> {"git"} -> delete_repository($user -> {"username"}, $path)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"git"} -> errstr()}));

    # Remove any database allocation associated with this project
    $self -> {"system"} -> {"databases"} -> set_user_database_project($user -> {"username"}, undef, $path)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"databases"} -> errstr()}));

    # The call to delete_repository above may have changed the primary site, so fetch it
    my $primary = $self -> {"system"} -> {"repostools"} -> get_primary_site($user -> {"username"});
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"repostools"} -> errstr()}))
        if(!defined($primary));

    return { "return" => { "primary" => $primary || "-",
                           "url"     => $self -> build_url(fullurl => 1, block => "manage", pathinfo => ["webdel"], api => []) }};
}


## @method private $ _require_repository_change_confirm()
# An API function that generates a confirmation request to show to the user
# before changing the repostitory used as the source of the user's website.
#
# @return A string containing a block of HTML to return to the user.
sub _require_repository_change_confirm {
    my $self = shift;

    $self -> log("repository", "Change confirmation requested.");

    return $self -> {"template"} -> load_template("dashboard/web/confirmchange.tem");
}


## @method private $ _change_repository()
# Update the repository used as the source of the user's website. This will check
# that the value set by the user for the repository appears to be valid, and if
# so it will remove the user's current web directory and create a new one based
# on the specified repository.
#
# @return A hash containing an API response. If the change succeeded, the response
#         contains the URL to refirect the user to, otherwise it is an error to send
#         to the user.
sub _change_repository {
    my $self = shift;

    $self -> log("repository", "Changing repository for user.");

    my ($errors, $path) = $self -> _validate_repository_id();
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $errors}))
        if($errors);

    my ($reposerr, $repos) = $self -> _validate_change_repository($path);
    return $self -> api_errorhash("validation_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $reposerr}))
        if($reposerr);

    return { "result" => { "status" => "ok",
                           "repos"  => $repos } };
}


## @method private $ _set_primary()
# Update the primary site set for the user
#
# @return A hash containing an API response.
sub _set_primary {
    my $self = shift;
    my $user = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"}); # force lowercase for safety

    $self -> log("repository", "Updating primary for user ".$user -> {"username"});

    my ($errors, $path) = $self -> _validate_primary_id();
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $errors}))
        if($errors);

    $self -> log("repository", "Setting primary for user ".$user -> {"username"}." to $path");

    $self -> {"system"} -> {"repostools"} -> set_primary_site(lc($user -> {"username"}), $path)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"repostools"} -> errstr()}));

    $self -> {"system"} -> {"git"} -> write_primary_redirect(lc($user -> {"username"}))
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"git"} -> errstr()}));

    return { 'response' => { 'status' => 'ok' } };
}


# ============================================================================
#  API functions - database

# @method private $ _require_database_change_confirm()
# An API function that generates a confirmation request to show to the user
# to request the new password for their database.
#
# @return A string containing a block of HTML to return to the user.
sub _require_database_change_confirm {
    my $self = shift;

    $self -> log("database", "Password change confirmation requested.");

    return $self -> {"template"} -> load_template("dashboard/db/confirmchange.tem");
}


## @method private $ _change_database_password()
# Update the password associated with the user's account in the database.
#
# @return A hash containing an API response. If the change succeeded, the response
#         contains the URL to refirect the user to, otherwise it is an error to send
#         to the user.
sub _change_database_password {
    my $self = shift;

    $self -> log("database", "Changing password for user.");

    my ($errors, $args) = $self -> _validate_database();
    return $self -> api_errorhash("validation_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $errors}))
        if($errors);

    return { "return" => { "url" => $self -> build_url(fullurl => 1, block => "manage", pathinfo => ["dbset"], api => []) }};
}


# @method private $ _require_database_delete_confirm()
# An API function that generates a confirmation request to show to the user
# before deleting their account and database(s).
#
# @return A string containing a block of HTML to return to the user.
sub _require_database_delete_confirm {
    my $self = shift;

    $self -> log("database", "Delete confirmation requested.");

    return $self -> {"template"} -> load_template("dashboard/db/confirmnuke.tem");
}


## @method private $ _delete_database_account()
# Delete the user's database account (and all databases they own).
#
# @return A hash containing an API response. If the delete succeeded, the response
#         contains the URL to refirect the user to, otherwise it is an error to send
#         to the user.
sub _delete_database_account {
    my $self = shift;
    my $user = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"}); # force lowercase for safety

    $self -> log("database", "Deleting database for user ".$user -> {"username"});

    $self -> {"system"} -> {"databases"} -> delete_user_account($user -> {"username"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"databases"} -> errstr()}));

    $self -> log("database", "Deleting config file for user ".$user -> {"username"});
    $self -> {"system"} -> {"git"} -> write_config($user -> {"username"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"git"} -> errstr()}));

    return { "return" => { "url" => $self -> build_url(fullurl => 1, block => "manage", pathinfo => ["dbdel"], api => []) }};
}


## @method private $ _add_database()
# Create a new database for the user, possibly cloning a database in the process.
#
# @return A reference to a hash containing the API response to sent back to the user.
sub _add_database {
    my $self = shift;

    # Users are not allowed to add databases without the extended.databases capability
    return $self -> api_errorhash("permission_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"template"} -> replace_langvar("DATABASE_APIERR_NOPERM")}))
        unless($self -> check_permission('extended.databases'));

    # Get the current user's information
    my $user  = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"});

    # mysql max database name length is 64 characters, so work out the maximum the user can set
    my $namelen = 64 - (length($user -> {"username"}) + 1);

    # User has permission, have they set the required variables?
    my ($name, $nameerr) = $self -> validate_string("extraname", {"required"   => 1,
                                                                  "nicename"   => $self -> {"template"} -> replace_langvar("DATABASE_EXTRA_NAME"),
                                                                  "minlen"     => 3,
                                                                  "maxlen"     => $namelen,
                                                                  "formattest" => '^[-.+\w]+$',
                                                                  "formatdesc" => $self -> {"template"} -> replace_langvar("DATABASE_APIERR_NAMEFORM"),
                                                    });
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $nameerr }))
        if($nameerr);

    # Check the source
    my $databases = $self -> _build_source_options($user -> {"username"});
    my ($source, $srcerr) = $self -> validate_options("extrasrc", {"required" => 0,
                                                                   "nicename" => $self -> {"template"} -> replace_langvar("DATABASE_EXTRA_SOURCE"),
                                                                   "source"   => $databases});
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $srcerr }))
        if($srcerr);

    my $dbname = $user -> {"username"}."_".$name;

    # Ensure that the name is not already used
    foreach my $database (@{$databases}) {
        return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"template"} -> replace_langvar("DATABASE_APIERR_EXISTS") }))
            if($dbname eq $database -> {"value"});
    }

    $self -> log("database", "Creating database '$dbname' for user ".$user -> {"username"});

    # Source and name are valid, create the database accordingly
    $self -> {"system"} -> {"databases"} -> create_user_database($user -> {"username"}, $dbname, ($source && $source ne "-") ? $source : undef)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"databases"} -> errstr() }));

    if($source && $source ne "-") {
        $self -> log("database", "Cloning database '$source' as '$dbname' for user ".$user -> {"username"});

        $self -> {"system"} -> {"databases"} -> clone_database($user -> {"username"}, $dbname, $source)
            or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"databases"} -> errstr() }));
    }

    return { "return" => { "url" => $self -> build_url(fullurl => 1, block => "manage", pathinfo => ["dbadd", $dbname], api => [], anchor => "database") }};
}


## @method private $ _set_project_database()
# Set the database associated with a project.
#
# @return A reference to a hash containing the API response to sent back to the user.
sub _set_project_database {
    my $self = shift;

    # Users are not allowed to set databases without the extended.databases capability
    return $self -> api_errorhash("permission_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"template"} -> replace_langvar("DATABASE_APIERR_NOPERM")}))
        unless($self -> check_permission('extended.databases'));

    # Get the current user's information
    my $user  = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"});

    $self -> log("web", "Setting project database for user ".$user -> {"username"});

    # Get the project and database information
    # first the list of valid repositories
    my $repos = $self -> {"system"} -> {"git"} -> user_web_repo_list($user -> {"username"});
    my @valid_repo_options = ();
    foreach my $proj (@{$repos}) {
        push(@valid_repo_options, { "name"  => $proj -> {"subdir"},
                                    "value" => $proj -> {"subdir"} });
    }

    # and now the list of valid databases
    my $userdbs = $self -> {"system"} -> {"databases"} -> get_user_databases($user -> {"username"});
    my @valid_db_options = ( );
    foreach my $database (@{$userdbs}) {
        push(@valid_db_options, { "name" => $database -> {"name"}, "value" => $database -> {"name"} });
    }

    # And pull in the validated info
    my ($project, $projerr) = $self -> validate_options("project", {"required" => 1,
                                                                    "nicename" => $self -> {"template"} -> replace_langvar("WEBSITE_PROJECT"),
                                                                    "source"   => \@valid_repo_options});
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $projerr }))
        if($projerr);

    my ($dbname, $dberr) = $self -> validate_options("dbname", {"required" => 1,
                                                                "nicename" => $self -> {"template"} -> replace_langvar("WEBSITE_DATABASE"),
                                                                "source"   => \@valid_db_options});
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $dberr }))
        if($dberr);

    $self -> log("web", "Setting database $dbname for project $project for user ".$user -> {"username"});

    # Got a project and database, set it
    $self -> {"system"} -> {"databases"} -> set_user_database_project($user -> {"username"}, $dbname, $project)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"databases"} -> errstr() }));

    $self -> {"system"} -> {"git"} -> write_config($user -> {"username"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"git"} -> errstr() }));

    return { "result" => { "status" => "ok" } };
}


## @method private $ _delete_database()
# Delete a user's database, clearing any project associations for it and resetting
# them to the user's default database.
#
# @return A reference to a hash containing the API response to sent back to the user.
sub _delete_database {
    my $self = shift;

    # Users are not allowed to delete databases without the extended.databases capability
    return $self -> api_errorhash("permission_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"template"} -> replace_langvar("DATABASE_APIERR_NOPERM")}))
        unless($self -> check_permission('extended.databases'));

    # Get the current user's information
    my $user  = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"});

    $self -> log("database", "Deleting database for user ".$user -> {"username"});

    # Build the list of databases the user can delete
    my $userdbs = $self -> {"system"} -> {"databases"} -> get_user_databases($user -> {"username"});
    my @valid_db_options = ( );
    foreach my $database (@{$userdbs}) {
        # Can't delete the default database
        next if($database -> {"name"} eq $user -> {"username"});

        push(@valid_db_options, { "name" => $database -> {"name"}, "value" => $database -> {"name"} });
    }

    my ($dbname, $dberr) = $self -> validate_options("dbname", {"required" => 1,
                                                                "nicename" => $self -> {"template"} -> replace_langvar("WEBSITE_DATABASE"),
                                                                "source"   => \@valid_db_options});
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $dberr }))
        if($dberr);

    $self -> log("database", "Deleting database '$dbname' for user ".$user -> {"username"});

    $self -> {"system"} -> {"databases"} -> delete_user_database($user -> {"username"}, $dbname)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"databases"} -> errstr() }));

    # Write all the config files again, to make sure that the projects do not
    # reference the removed database
    $self -> {"system"} -> {"git"} -> write_config($user -> {"username"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"git"} -> errstr() }));

    return { "result" => { "status" => "ok" } };
}


## @method private $ _reclone_database()
# Attempt to update the contents of a user's database to reflect the current state
# of the database it was originally cloned from. If the database specified by the
# caller was not cloned, this will generate an error, otherwise all the cloned tables
# in the database are replaced with the tables as they currently are in the source
# database. Tables created after the original clone are unaffected, but any data
# added to cloned tables will be lost.
#
# @return A reference to a hash containing the API response to sent back to the user.
sub _reclone_database {
    my $self = shift;

    # Users are not allowed to reclone databases without the extended.databases capability
    return $self -> api_errorhash("permission_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"template"} -> replace_langvar("DATABASE_APIERR_NOPERM")}))
        unless($self -> check_permission('extended.databases'));

    # Get the current user's information
    my $user  = $self -> {"session"} -> get_user_byid();
    $user -> {"username"} = lc($user -> {"username"});

    $self -> log("database", "Re-cloning database for user ".$user -> {"username"});

    # Build the list of databases the user can delete
    my $userdbs = $self -> {"system"} -> {"databases"} -> get_user_databases($user -> {"username"});
    my @valid_db_options = ( );
    foreach my $database (@{$userdbs}) {
        # Can't reclone the default database
        next if($database -> {"name"} eq $user -> {"username"});

        push(@valid_db_options, { "name" => $database -> {"name"}, "value" => $database -> {"name"} });
    }

    my ($dbname, $dberr) = $self -> validate_options("dbname", {"required" => 1,
                                                                "nicename" => $self -> {"template"} -> replace_langvar("WEBSITE_DATABASE"),
                                                                "source"   => \@valid_db_options});
    return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $dberr }))
        if($dberr);

    $self -> {"system"} -> {"databases"} -> clone_database($user -> {"username"}, $dbname)
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"databases"} -> errstr() }));

    return { "result" => { "status" => "ok" } };
}

# ============================================================================
#  Interface functions

## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# the compose page, including any errors or user feedback.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;
    my ($title, $content, $extrahead);

    my $error = $self -> check_login();
    return $error if($error);

    # Is this an API call, or a normal page operation?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        # API call - dispatch to appropriate handler.
        given($apiop) {
            # Repository/website operations
            when ("gettoken")     { return $self -> api_html_response($self -> _show_token()); }
            when ("pullrepo")     { return $self -> api_html_response($self -> _update_repository()); }
            when ("webnukecheck") { return $self -> api_html_response($self -> _require_repository_delete_confirm()); }
            when ("websetcheck")  { return $self -> api_html_response($self -> _require_repository_change_confirm()); }
            when ("dowebnuke")    { return $self -> api_response($self -> _delete_repository()); }
            when ("dowebchange")  { return $self -> api_response($self -> _change_repository()); }
            when ("setprimary")   { return $self -> api_response($self -> _set_primary()); }

            # database operations
            when ("dbnukecheck")  { return $self -> api_html_response($self -> _require_database_delete_confirm()); }
            when ("dbsetcheck")   { return $self -> api_html_response($self -> _require_database_change_confirm()); }

            when ("dodbchange")   { return $self -> api_response($self -> _change_database_password()); }
            when ("dodbnuke")     { return $self -> api_response($self -> _delete_database_account()); }

            # Additional database operations
            when ("adddb")        { return $self -> api_response($self -> _add_database()); }
            when ("setprojdb")    { return $self -> api_response($self -> _set_project_database()); }
            when ("deldb")        { return $self -> api_response($self -> _delete_database()); }
            when ("upddb")        { return $self -> api_response($self -> _reclone_database()); }

            default {
                return $self -> api_html_response($self -> api_errorhash('bad_op',
                                                                         $self -> {"template"} -> replace_langvar("API_BAD_OP")))
            }
        }
    } else {
        my @pathinfo = $self -> {"cgi"} -> multi_param('pathinfo');
        # Normal page operation.
        # ... handle operations here...

        if(!scalar(@pathinfo)) {
            ($title, $content, $extrahead) = $self -> _generate_dashboard();
        } else {
            given($pathinfo[0]) {
                # Repository/website operations
                when("addrepos") { ($title, $content, $extrahead) = $self -> _add_repository(); }

                # Database operations
                when("newdb")    { ($title, $content, $extrahead) = $self -> _make_database();  }
                when("dbadd")    { ($title, $content, $extrahead) = $self -> _hilight_dbadd($pathinfo[1]); }

                default {
                    ($title, $content, $extrahead) = $self -> _generate_dashboard();
                }
            }
        }

        $extrahead .= $self -> {"template"} -> load_template("dashboard/extrahead.tem");
        return $self -> generate_dashboard_page($title, $content, $extrahead, 'dashboard');
    }
}

1;

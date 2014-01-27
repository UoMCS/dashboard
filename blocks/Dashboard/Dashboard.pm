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
use base qw(Dashboard); # This class extends the Dashboard block class
use v5.12;
use Webperl::Utils qw(path_join);
use Data::Dumper;

# ============================================================================
#  Repository/web related

## @method private $ _validate_repository_fields($args)
# Determine whether the repository field set by the user is valid and appears
# to correspond to a possible repository.
#
# @param args A reference to a hash to store validated data in.
# @return empty string on success, otherwise an error string.
sub _validate_repository_fields {
    my $self = shift;
    my $args = shift;
    my ($errors, $error) = ("", "");

    ($args -> {"web-repos"}, $error) = $self -> validate_string("web-repos", {"required" => 1,
                                                                              "nicename" => $self -> {"template"} -> replace_langvar("WEBSITE_REPOS"),
                                                                              "minlen"   => 8,
                                                                              "formattest" => $self -> {"formats"} -> {"url"},
                                                                              "formatdesc" => $self -> {"template"} -> replace_langvar("WEBSITE_REPOS_ERRDESC"),
                                                                });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => $error}) if($error);

    ($args -> {"web-path"}, $error) = $self -> validate_string("web-path", {"required" => 0,
                                                                            "nicename" => $self -> {"template"} -> replace_langvar("WEBSITE_PATH"),
                                                                });
    $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => $error}) if($error);

    # Force .git on the end of the url
    if($args -> {"web-repos"}) {
        $errors .= $self -> {"template"} -> load_template("error/error_item.tem", {"***error***" => "{L_WEBSITE_NEEDGIT}"})
            unless($args -> {"web-repos"} =~ /\.git$/i);
    }

    return $errors;
}


## @method private @ _validate_repository()
# Determine whether the repository field set by the user is valid and appears
# to correspond to a possible repository. If it is, perform the clone process
# for the user.
#
sub _validate_repository {
    my $self = shift;
    my ($args, $errors, $error) = ({}, "", "", undef);
    my $user = $self -> {"session"} -> get_user_byid();

    $error = $self -> _validate_repository_fields($args);
    $errors .= $error if($error);

    return ($self -> {"template"} -> load_template("error/error_list.tem", {"***message***" => "{L_WEBSITE_CLONE_FAIL}",
                                                                            "***errors***"  => $errors}), $args)
        if($errors);

    $self -> log("repository", "Cloning ".$args -> {"web-repos"}." to ".$user -> {"username"});

    # The respository appears to be valid, do the clone
    $self -> {"system"} -> {"git"} -> clone_repository($args -> {"web-repos"}, $user -> {"username"}, $args -> {"web-path"})
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
        print $self -> {"cgi"} -> redirect($self -> build_url(pathinfo => ["cloned"]));
        exit;
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
        print $self -> {"cgi"} -> redirect($self -> build_url(pathinfo => ["newdbok"]));
        exit;
    }

    return $self -> _generate_dashboard($args, $error);
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

    # First up, does the user have an existing repository in place?
    my $repos = $self -> {"system"} -> {"git"} -> user_web_repo_exists($user -> {"username"});
    return $self -> {"template"} -> load_template("dashboard/web/norepo.tem", {"***web-repos***" => $args -> {"web-repos"},
                                                                               "***web-path***"  => $args -> {"web-path"},
                                                                               "***form_url***"  => $self -> build_url(block => "manage", "pathinfo" => [ "addrepos" ])})
        if(!$repos || !scalar(@{$repos}));


    my $rlist = "";
    my $hasroot = 0;
    foreach my $entry (@{$repos}) {
        $rlist .= $self -> {"template"} -> load_template("dashboard/web/repo-row.tem", {"***url***"     => path_join($self -> {"settings"} -> {"git"} -> {"webbaseurl"}, lc($user -> {"username"}), $entry -> {"subdir"},"/"),
                                                                                        "***subdir***"  => path_join($self -> {"settings"} -> {"git"} -> {"webbaseurl"}, lc($user -> {"username"}), $entry -> {"subdir"},"/"),
                                                                                        "***id***"      => $entry -> {"subdir"} || "-",
                                                                                        "***source***"  => $entry -> {"origin"} });
        $hasroot = 1 if(!$entry -> {"subdir"});
    }

    my $addform = $self -> {"template"} -> load_template("dashboard/web/addform_".($hasroot ? "gotroot.tem" : "noroot.tem"),
                                                         { "***web-repos***" => $args -> {"web-repos"},
                                                           "***web-path***"  => $args -> {"web-path"},
                                                           "***form_url***"  => $self -> build_url(block => "manage", "pathinfo" => [ "addrepos" ])});

    return $self -> {"template"} -> load_template("dashboard/web/repo.tem"  , {"***repos***"     => $rlist,
                                                                               "***addform***"   => $addform,
                                                                               "***web_url***"   => path_join($self -> {"settings"} -> {"git"} -> {"webbaseurl"}, lc($user -> {"username"}),"/"),
                                                                               "***pull_url***"  => $self -> build_url(block => "manage", "pathinfo" => [ "pullrepos" ]),
                                                                               "***nuke_url***"  => $self -> build_url(block => "manage", "pathinfo" => [ "nukerepos" ]),
                                                                               "***clone_url***" => $self -> build_url(block => "manage", "pathinfo" => [ "setrepos" ]),
                                                  });

}


## @method provate $ _generate_group_database($groups)
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
        return $self -> {"template"} -> load_template("dashboard/db/nodb.tem", {"***form_url***"  => $self -> build_url(block => "manage", "pathinfo" => [ "newdb" ])});
    } else {
        # Get the list of group databases the user should have access to
        my $groups = $self -> {"system"} -> {"userdata"} -> get_user_groupnames($user -> {"username"});

        my $groupdbs = $self -> {"system"} -> {"databases"} -> set_user_group_databases($user -> {"username"}, $groups)
            if($groups);

        # Update the config file if there have been changes.
        $self -> {"system"} -> {"git"} -> write_config($user -> {"username"})
            if($groupdbs && $groupdbs -> {"_internal"} -> {"save_config"});

        return $self -> {"template"} -> load_template("dashboard/db/db.tem"  , {"***username***" => lc($user -> {"username"}),
                                                                                "***password***" => "{L_DATABASE_PASSWORD_COPOUT}",
                                                                                "***groups***"   => $self -> _generate_group_database($groupdbs),
                                                      });
    }
}


# @method private @ _generate_dashboard($args, $error, $message)
# Generate the page content for a dashboard page.
#
# @param args    An optional reference to a hash containing defaults for the form fields.
# @param error   An optional error message to display above the form if needed.
# @param message An optional info message to display above the form if needed.
# @return Two strings, the first containing the page title, the second containing the
#         page content.
sub _generate_dashboard {
    my $self    = shift;
    my $args    = shift || { };
    my $error   = shift;
    my $message = shift;

    # Get the current user's information
    my $user  = $self -> {"session"} -> get_user_byid();

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

    return ($self -> {"template"} -> replace_langvar("DASHBOARD_TITLE"),
            $self -> {"template"} -> load_template("dashboard/content.tem", {"***errorbox***" => $error,
                                                                             "***infobox***"  => $message,
                                                                             "***webpart***"  => $webblock,
                                                                             "***dbpart***"   => $dbblock,
                                                   }));
}


# ============================================================================
#  API functions

## @method private $ _show_token()
# An API function that generates a token information string to send to the
# user.
#
# @return A string containing a block of HTML to return to the user.
sub _show_token {
    my $self   = shift;
    my $user   = $self -> {"session"} -> get_user_byid();

    $self -> log("repository", "Token requested.");

    my $origin = $self -> {"system"} -> {"git"} -> user_web_repo_exists($user -> {"username"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => "{L_WEBSITE_ERR_NOREPO}"}));

    my $token = $self -> {"system"} -> {"repostools"} -> get_user_token($user -> {"user_id"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"repostools"} -> errstr()}));

    # If the user doesn't have a token, or it somehow doesn't match the origin, make a new one
    if(!$token -> {"repos_url"} || $token -> {"repos_url"} != $origin) {
        $self -> log("repository", "User doesn't have a token, or it is incorrect. Making new");

        $token = $self -> {"system"} -> {"repostools"} -> set_user_token($origin, $user)
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

    $self -> log("repository", "Pulling repository for user ".$user -> {"username"});

    $self -> {"system"} -> {"git"} -> pull_repository($user -> {"username"})
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

    $self -> log("repository", "Deleting repository for user ".$user -> {"username"});

    $self -> {"system"} -> {"git"} -> delete_repository($user -> {"username"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"git"} -> errstr()}));

    return { "return" => { "url" => $self -> build_url(fullurl => 1, block => "manage", pathinfo => ["webdel"], api => []) }};
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

    my ($errors, $args) = $self -> _validate_repository();
    return $self -> api_errorhash("validation_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $errors}))
        if($errors);

    return { "return" => { "url" => $self -> build_url(fullurl => 1, block => "manage", pathinfo => ["webset"], api => []) }};
}


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


## @method private $ _change_database()
# Update the password associated with the user's account in the database.
#
# @return A hash containing an API response. If the change succeeded, the response
#         contains the URL to refirect the user to, otherwise it is an error to send
#         to the user.
sub _change_database {
    my $self = shift;

    $self -> log("database", "Changing password for user.");

    my ($errors, $args) = $self -> _validate_database();
    return $self -> api_errorhash("validation_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $errors}))
        if($errors);

    return { "return" => { "url" => $self -> build_url(fullurl => 1, block => "manage", pathinfo => ["dbset"], api => []) }};
}


# @method private $ _require_database_delete_confirm()
# An API function that generates a confirmation request to show to the user
# tbefore deleting their account and database.
#
# @return A string containing a block of HTML to return to the user.
sub _require_database_delete_confirm {
    my $self = shift;

    $self -> log("database", "Delete confirmation requested.");

    return $self -> {"template"} -> load_template("dashboard/db/confirmnuke.tem");
}


## @method private $ _delete_database()
# Delete the user's database.
#
# @return A hash containing an API response. If the delete succeeded, the response
#         contains the URL to refirect the user to, otherwise it is an error to send
#         to the user.
sub _delete_database {
    my $self = shift;
    my $user = $self -> {"session"} -> get_user_byid();

    $self -> log("database", "Deleting database for user ".$user -> {"username"});

    $self -> {"system"} -> {"databases"} -> delete_user_account($user -> {"username"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"databases"} -> errstr()}));

    $self -> log("database", "Deleting config file for user ".$user -> {"username"});
    $self -> {"system"} -> {"git"} -> write_config($user -> {"username"})
        or return $self -> api_errorhash("internal_error", $self -> {"template"} -> replace_langvar("API_ERROR", {"***error***" => $self -> {"system"} -> {"git"} -> errstr()}));

    return { "return" => { "url" => $self -> build_url(fullurl => 1, block => "manage", pathinfo => ["dbdel"], api => []) }};
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

            # database operations
            when ("dbnukecheck")  { return $self -> api_html_response($self -> _require_database_delete_confirm()); }
            when ("dbsetcheck")   { return $self -> api_html_response($self -> _require_database_change_confirm()); }

            when ("dodbchange")   { return $self -> api_response($self -> _change_database()); }
            when ("dodbnuke")     { return $self -> api_response($self -> _delete_database()); }
            default {
                return $self -> api_html_response($self -> api_errorhash('bad_op',
                                                                         $self -> {"template"} -> replace_langvar("API_BAD_OP")))
            }
        }
    } else {
        my @pathinfo = $self -> {"cgi"} -> param('pathinfo');
        # Normal page operation.
        # ... handle operations here...

        if(!scalar(@pathinfo)) {
            ($title, $content, $extrahead) = $self -> _generate_dashboard();
        } else {
            given($pathinfo[0]) {
                # Repository/website operations
                when("addrepos") { ($title, $content, $extrahead) = $self -> _add_repository(); }
                when("cloned")   { ($title, $content, $extrahead) = $self -> _generate_dashboard(undef, undef, "{L_WEBSITE_CLONE_SUCCESS}"); }
                when("webdel")   { ($title, $content, $extrahead) = $self -> _generate_dashboard(undef, undef, "{L_WEBSITE_NUKE_SUCCESS}"); }
                when("webset")   { ($title, $content, $extrahead) = $self -> _generate_dashboard(undef, undef, "{L_WEBSITE_CHANGE_SUCCESS}"); }

                # Database operations
                when("newdb")    { ($title, $content, $extrahead) = $self -> _make_database(); }
                when("newdbok")  { ($title, $content, $extrahead) = $self -> _generate_dashboard(undef, undef, "{L_DATABASE_SETUP_SUCCESS}"); }
                when("dbset")    { ($title, $content, $extrahead) = $self -> _generate_dashboard(undef, undef, "{L_DATABASE_CHANGE_SUCCESS}"); }
                when("dbdel")    { ($title, $content, $extrahead) = $self -> _generate_dashboard(undef, undef, "{L_DATABASE_NUKE_SUCCESS}"); }

                default {
                    ($title, $content, $extrahead) = $self -> _generate_dashboard();
                }
            }
        }

        $extrahead .= $self -> {"template"} -> load_template("dashboard/extrahead.tem");
        return $self -> generate_dashboard_page($title, $content, $extrahead);
    }
}

1;

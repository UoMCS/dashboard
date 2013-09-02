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


# ============================================================================
#  Repository/web related

## @method private @ _validate_repository_fields($args)
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

    return $errors;
}



## @method private $ _set_repository()
# Set the user's repository to the repository they specify in the form, if possible.
#
# @return Two strings, the first containing the page title, the second containing the
#         page content.
sub _set_repository {
    my $self = shift;



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
    my $origin = $self -> {"system"} -> {"git"} ->user_web_repo_exists($user -> {"username"});
    if(!$origin) {
        return $self -> {"template"} -> load_template("dashboard/web/norepo.tem", {"***web-repos***" => $args -> {"web-repos"},
                                                                                   "***form_url***"  => $self -> build_url(block => "dashboard", "pathinfo" => [ "setrepos" ])});
    }
}


# @method private @ _generate_dashboard($args, $error)
# Generate the page content for a dashboard page.
#
# @param args  An optional reference to a hash containing defaults for the form fields.
# @param error An optional error message to display above the form if needed.
# @return Two strings, the first containing the page title, the second containing the
#         page content.
sub _generate_dashboard {
    my $self  = shift;
    my $args  = shift || { };
    my $error = shift;

    # Get the current user's information
    my $user  = $self -> {"session"} -> get_user_byid();

    # Build the web publish block
    my $webblock = $self -> _generate_web_publish($user, $args);

    # Wrap the error in an error box, if needed.
    $error = $self -> {"template"} -> load_template("error/error_box.tem", {"***message***" => $error})
        if($error);

    return ($self -> {"template"} -> replace_langvar("DASHBOARD_TITLE"),
            $self -> {"template"} -> load_template("dashboard/content.tem", {"***errorbox***" => $error,
                                                                             "***webpart***"  => $webblock,
                                                   }));
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

    # Exit with a permission error unless the user has permission to use the system
    if(!$self -> check_permission("view")) {
        $self -> log("error:permission", "User does not have permission to view the dashboard");

        my $userbar = $self -> {"module"} -> load_module("Dashboard::Userbar");
        my $message = $self -> {"template"} -> message_box("{L_PERMISSION_FAILED_TITLE}",
                                                           "error",
                                                           "{L_PERMISSION_FAILED_SUMMARY}",
                                                           "{L_PERMISSION_USER_PERM}",
                                                           undef,
                                                           "errorcore",
                                                           [ {"message" => $self -> {"template"} -> replace_langvar("SITE_CONTINUE"),
                                                              "colour"  => "blue",
                                                              "action"  => "location.href='".$self -> build_url(block => "compose", pathinfo => [])."'"} ]);

        return $self -> {"template"} -> load_template("error/general.tem",
                                                      {"***title***"     => "{L_PERMISSION_FAILED_TITLE}",
                                                       "***message***"   => $message,
                                                       "***extrahead***" => "",
                                                       "***userbar***"   => $userbar -> block_display("{L_PERMISSION_FAILED_TITLE}"),
                                                      })
    }

    # Is this an API call, or a normal page operation?
    my $apiop = $self -> is_api_operation();
    if(defined($apiop)) {
        # API call - dispatch to appropriate handler.
        given($apiop) {
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
                when("setrepos") { ($title, $content, $extrahead) = $self -> _set_repository(); }
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

## @file
# This file contains the implementation of the standalone repository updated.
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
package Dashboard::UpdateWebsite;

use strict;
use base qw(Dashboard); # This class extends the Dashboard block class
use v5.12;
use JSON;
use DateTime;
use DateTime::Format::RFC3339;

## @method private $ _update_repository($token)
# An API-like function that triggers a git pull on a user's repository. The user
# to update is determiend by the provided token.
#
# @param token The token to use when updating
# @return A reference to a hash containing success or error information.
sub _update_repository {
    my $self  = shift;
    my $token = shift;

    return $self -> _json_hash("error", "no token", $self -> {"template"} -> replace_langvar("TOKEN_ERR_NOTOKEN"))
        if(!$token);

    # check the token for dodgyness
    return $self -> _json_hash("error", "bad token", $self -> {"template"} -> replace_langvar("TOKEN_ERR_BADTOKEN"))
        unless($token =~ m|^[0-9a-zA-Z+/]+$|);

    $self -> log("remote", "Looking for owner of token $token");

    my $usertoken = $self -> {"system"} -> {"repostools"} -> get_token($token);
    return $self -> _json_hash("error", "bad token", $self -> {"template"} -> replace_langvar("TOKEN_ERR_BADTOKEN"))
        if(!$usertoken || !$usertoken -> {"user_id"});

    # Find the user the token belongs to
    my $user = $self -> {"session"} -> get_user_byid($usertoken -> {"user_id"});

    $self -> log("remote", "Pulling repository for user ".$user -> {"username"});

    $self -> {"system"} -> {"git"} -> pull_repository($user -> {"username"})
        or return $self -> _json_hash("error", "pull failed", $self -> {"system"} -> {"git"} -> errstr());

    return $self -> _json_hash("success");
}


## @method private $ _json_hash($status, $short, $desc)
# Generate a reference to a hash that can be passed to _json_response(). This
# builds a hash in a form suitable for passing to _json_response() based on
# the contents of the specified parameters.
#
# @param status Should be "success" or "error".
# @param short  If `status` is "error", this should contain a short error code
#               for the caller to use.
# @param desc   If `status` is "error", this should contain a longer description
#               of the cause of the error.
# @return A reference to a hash.
sub _json_hash {
    my $self   = shift;
    my $status = shift;
    my $short  = shift;
    my $desc   = shift;

    my $date = DateTime -> now(time_zone => "UTC", formatter => DateTime::Format::RFC3339 -> new());

    my $hash = { "status"    => $status,
                 "timestamp" => "$date",
    };

    if($status eq "error") {
        $hash -> {"information"} = { "reason"  => $short,
                                     "message" => $desc
        };
        $self -> log("remote", "Building error hash with '$short': '$desc'");
    }

    return $hash;
}


## @method private void _json_response($hash)
# Send a JSON formatted response back to the client, using the contents of the
# provided hash as the data to convert to JSON. This function will not return:
# it sends the response and then exits cleanly.
#
# @param hash A reference to a hash containing data to send to the user.
sub _json_response {
    my $self = shift;
    my $hash = shift;

    print $self -> {"cgi"} -> header(-type => 'application/json',
                                     -charset => 'utf-8');
    print Encode::encode_utf8(JSON -> new -> pretty -> encode($hash));
    $self -> {"template"} -> set_module_obj(undef);
    $self -> {"messages"} -> set_module_obj(undef);
    $self -> {"system"} -> clear() if($self -> {"system"});
    $self -> {"session"} -> {"auth"} -> {"app"} -> set_system(undef) if($self -> {"session"} -> {"auth"} -> {"app"});

    $self -> {"dbh"} -> disconnect();
    $self -> {"logger"} -> end_log();

    exit;
}


## @method $ page_display()
# Produce the string containing this block's full page content. This generates
# the compose page, including any errors or user feedback.
#
# @return The string containing this block's page content.
sub page_display {
    my $self = shift;

    my $token = $self -> {"cgi"} -> param('token');
    return $self -> _json_response($self -> _update_repository($token));
}

1;

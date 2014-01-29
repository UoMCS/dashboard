## @file
# This file contains the implementation of the repository engine.
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
# This class encapsulates operations involving repositories.
package Dashboard::System::ReposTools;

use strict;
use base qw(Webperl::SystemModule);
use Digest::SHA qw(sha256_base64);
use Data::Dumper;
use v5.12;


## @method $ set_user_token($reposurl, $user, $path)
# Create and store a remote update token for the user.
#
# @param reposurl The URL of the repository the user has cloned.
# @param user     A reference to the user's data
# @param path     The subdirectory path containing the project
# @return A reference to the user's token data on success, undef on error.
sub set_user_token {
    my $self     = shift;
    my $reposurl = shift;
    my $user     = shift;
    my $path     = shift || "";

    $self -> clear_error();

    my $nukeold = $self -> {"dbh"} -> prepare("DELETE FROM `".$self -> {"settings"} -> {"database"} -> {"tokens"}."`
                                               WHERE `user_id` = ? AND `path` LIKE ?");
    $nukeold -> execute($user -> {"user_id"}, $path)
        or return $self -> self_error("Unable to perform user token cleanup: ".$self -> {"dbh"} -> errstr);

    my $newtok = $self -> {"dbh"} -> prepare("INSERT INTO  `".$self -> {"settings"} -> {"database"} -> {"tokens"}."`
                                              (`user_id`, `path`, `token`, `repos_url`)
                                              VALUES(?, ?, ?, ?)");
    my $result = $newtok -> execute($user -> {"user_id"}, $path, sha256_base64($reposurl."-".Dumper($user)."-".$path."-".time()), $reposurl);
    return $self -> self_error("Unable to create remote update token: ".$self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Remote update token creation failed, no rows added") if($result eq "0E0");

    return $self -> get_user_token($user -> {"user_id"}, $path);
}


## @method $ get_user_token($userid, $path)
# Given a user ID, fetch the remote update token data for the user.
#
# @param userid The ID of the user to fetch the token data for.
# @param path     The subdirectory path containing the project
# @return A reference to a hash containing the user's token data on
#         success, an empty hashref if the user has no token, undef
#         on error.
sub get_user_token {
    my $self   = shift;
    my $userid = shift;
    my $path   = shift || "";

    $self -> clear_error();

    my $tokeh = $self -> {"dbh"} -> prepare("SELECT * FROM `".$self -> {"settings"} -> {"database"} -> {"tokens"}."`
                                             WHERE `user_id` = ? AND `path` LIKE ?");
    $tokeh -> execute($userid, $path)
        or return $self -> self_error("Unable to perform user token lookup: ".$self -> {"dbh"} -> errstr);

    return $tokeh -> fetchrow_hashref() || {};
}


## @method $ get_token($token)
# Given a token, fetch the remote update token data for the token.
#
# @param token The token string to fetch the data for.
# @return A reference to a hash containing the token data on
#         success, an empty hashref if the user has no token, undef
#         on error.
sub get_token {
    my $self  = shift;
    my $token = shift;

    $self -> clear_error();

    my $tokeh = $self -> {"dbh"} -> prepare("SELECT * FROM `".$self -> {"settings"} -> {"database"} -> {"tokens"}."`
                                             WHERE `token` = ?");
    $tokeh -> execute($token)
        or return $self -> self_error("Unable to perform token lookup: ".$self -> {"dbh"} -> errstr);

    return $tokeh -> fetchrow_hashref() || {};
}


## @method $ set_primary_site($username, $path)
# Update the primary site selection for the specified user.
#
# @param username The name of the user to set the primary site for
# @param path     The subdirectory path to use as the primary. If this is not set,
#                 the user's primary site selection is deleted.
# @return True on success, undef on error.
sub set_primary_site {
    my $self     = shift;
    my $username = lc(shift);
    my $path     = shift;

    $self -> clear_error();

    my $nukeold = $self -> {"dbh"} -> prepare("DELETE FROM `".$self -> {"settings"} -> {"database"} -> {"primary"}."`
                                               WHERE `username` LIKE ?");
    $nukeold -> execute($username)
        or return $self -> self_error("Unable to perform user primary site cleanup: ".$self -> {"dbh"} -> errstr);

    if($path) {
        my $newpri = $self -> {"dbh"} -> prepare("INSERT INTO  `".$self -> {"settings"} -> {"database"} -> {"primary"}."`
                                                  (`username`, `subdir`)
                                                  VALUES(?, ?)");
        my $result = $newpri -> execute($username, $path);
        return $self -> self_error("Unable to create primary site: ".$self -> {"dbh"} -> errstr) if(!$result);
        return $self -> self_error("Primary site creation failed, no rows added") if($result eq "0E0");
    }

    return 1;
}


## @method $ get_primary_site($username)
# Fetch the subdir name of the primary site set by the user.
#
# @param username The name of the user to fetch the primary site path for.
# @return The site path on success, the empty string if the user has not set
#         a primary, undef on error.
sub get_primary_site {
    my $self     = shift;
    my $username = lc(shift);

    $self -> clear_error();

    my $siteh = $self -> {"dbh"} -> prepare("SELECT `subdir`
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"primary"}."`
                                             WHERE `username` LIKE ?");
    $siteh -> execute($username)
        or return $self -> self_error("Unable to perform user primary site lookup: ".$self -> {"dbh"} -> errstr);

    my $site = $siteh -> fetchrow_arrayref();
    return $site ? $site -> [0] : "";
}

1;

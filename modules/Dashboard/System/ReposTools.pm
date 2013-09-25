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


## @method $ set_user_token($reposurl, $user)
# Create and store a remote update token for the user.
#
# @param reposurl The URL of the repository the user has cloned.
# @param user     A reference to the user's data
# @return A reference to the user's token data on success, undef on error.
sub set_user_token {
    my $self     = shift;
    my $reposurl = shift;
    my $user     = shift;

    $self -> clear_error();

    my $nukeold = $self -> {"dbh"} -> prepare("DELETE FROM `".$self -> {"settings"} -> {"database"} -> {"tokens"}."`
                                               WHERE `user_id` = ?");
    $nukeold -> execute($user -> {"user_id"})
        or return $self -> self_error("Unable to perform user token cleanup: ".$self -> {"dbh"} -> errstr);

    my $newtok = $self -> {"dbh"} -> prepare("INSERT INTO  `".$self -> {"settings"} -> {"database"} -> {"tokens"}."`
                                              (`user_id`, `token`, `repos_url`)
                                              VALUES(?, ?, ?)");
    my $result = $newtok -> execute($user -> {"user_id"}, sha256_base64($reposurl."-".Dumper($user)."-".time()), $reposurl);
    return $self -> self_error("Unable to create remote update token: ".$self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Remote update token creation failed, no rows added") if($result eq "0E0");

    return $self -> get_user_token($user -> {"user_id"});
}


## @method $ get_user_token($userid)
# Given a user ID, fetch the remote update token data for the user.
#
# @param userid The ID of the user to fetch the token data for.
# @return A reference to a hash containing the user's token data on
#         success, an empty hashref if the user has no token, undef
#         on error.
sub get_user_token {
    my $self   = shift;
    my $userid = shift;

    $self -> clear_error();

    my $tokeh = $self -> {"dbh"} -> prepare("SELECT * FROM `".$self -> {"settings"} -> {"database"} -> {"tokens"}."`
                                             WHERE `user_id` = ?");
    $tokeh -> execute($userid)
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


1;

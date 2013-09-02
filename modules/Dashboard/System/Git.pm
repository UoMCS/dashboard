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
use Webperl::Utils qw(path_join);
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
    my $username = shift;

    $self -> clear_error();

    # Path to the user's config file, if it exists
    my $config = path_join($self -> {"settings"} -> {"Git:web_repo_base"}, $username, ".git", "config");

    return 0 if(!-f $config);

    # Hey, what do you know, ConfigMicro can parse git configs!
    my $config = Webperl::ConfigMicro -> new($config)
        or return $self -> self_error("Repository check failed: ".$Webperl::SystemModule::errstr);

    return $config -> {'remote "origin"'} -> {"url"};
}

1;

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

    # perform the pre-clone step
    my $res = `sudo $self->{settings}->{repostools}->{preclone} $username`;
    return $self -> self_error("Clone failed: $res") if($res);

    # Do the clone itself
    my $target = path_join($self -> {"settings"} -> {"git"} -> {"webtempdir"}, $username);
    my $output = eval { Git::Repository -> run(clone => $repository => $target,
                                               { git => "/usr/bin/git", input => "" }); };
    if(my $err = $@) {
        return $self -> self_error("Failed while attempting to clone a private project. Make the project public and try again.")
            if($err =~ /could not read Username for/);

        return $self -> self_error("Clone failed: $err\n");
    }

    # clone is complete, move the clone into position
    $res = `sudo $self->{settings}->{repostools}->{postgit} $username`;
    return $self -> self_error("Clone failed: $res") if($res);

    return 1;
}


1;

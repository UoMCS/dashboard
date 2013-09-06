## @file
# This file contains the implementation of the database management engine.
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
# This class encapsulates operations involving user databases.
package Dashboard::System::Databases;

use strict;
use base qw(Webperl::SystemModule);
use Webperl::Utils qw(path_join blind_untaint);
use DBI;
use v5.12;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)

sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(allowed_hosts => ['localhost',
                                                          '130.88.%',
                                        ],
                                        @_)
        or return undef;

    $self -> {"user_dbh"} = DBI->connect($self -> {"settings"} -> {"userdatabase"} -> {"database"},
                                         $self -> {"settings"} -> {"userdatabase"} -> {"username"},
                                         $self -> {"settings"} -> {"userdatabase"} -> {"password"},
                                          { RaiseError => 0, AutoCommit => 1, mysql_enable_utf8 => 1 })
        or return Webperl::SystemModule::set_error("Unable to connect to user database server: ".$DBI::errstr);

    return $self;
}


# ============================================================================
#  Checking code

## @method $ safe_username($username)
# Determine whether the specified username is safe, return an untainted version
# if it is.
#
# @param username The name of the user to check.
# @return A lowercase, untainted, safe version of the name on success, undef
#         on error.
sub safe_username {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    return $self -> self_error("No username specified") if(!$username);

    $username = lc($username);

    my ($safename) = $username =~ /^([-\w]+)$/;
    return $self -> self_error("Username '$username' contains illegal characters") if(!$safename);

    return $safename;
}


# ============================================================================
#  Database handling

## @method $ user_database_exists($username)
# Determine whether a database exists in the system for for the
# specified user.
#
# @param username The username of the user to search for a database for.
# @return True if the user's database exists, false if it does not, undef on error.
sub user_database_exists {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    $username = $self -> safe_username($username)
        or return undef;

    # check for the user first
    my $userh = $self -> {"user_dbh"} -> prepare("SELECT COUNT(*)
                                                  FROM user
                                                  WHERE User LIKE ?");
    $userh -> execute($username)
        or return $self -> self_error("Unable to perform user check: ".$self -> {"user_dbh"} -> errstr);

    my $usercount = $userh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to retrieve user account count.");

    # If the number of entries in the database for the user is less than the number
    # of hosts set up for the user, indicate a problem.
    return 0 if($usercount -> [0] < scalar(@{$self -> {"allowed_hosts"}}));

    # Now check that the user's database exists
    return $self -> _user_database_exists($username);
}


## @method $ setup_user_account($user, $password)
# Do a full setup of the user's account and database
#
# @param user     A reference to the user's data hash.
# @param password The password to set for the user's account.
# @return true on success, undef on error
sub setup_user_account {
    my $self     = shift;
    my $user     = shift;
    my $password = shift;

    $self -> clear_error();

    my $username = $self -> safe_username($user -> {"username"})
        or return undef;

    $self -> create_user_account($username, $password)
        or return undef;

    $self -> create_user_database($username)
        or return undef;

    $self -> flush_privileges()
        or return undef;

    $self -> store_user_password($user -> {"user_id"}, $password)
        or return undef;

    return 1;
}


## @method $ create_user_account($username, $password)
# Create or update the accounts associated with the specified user.
#
# @param username The name of the user to create or update the account for.
# @param password The password to set for the user's account.
# @return true on success, undef on error
sub create_user_account {
    my $self     = shift;
    my $username = shift;
    my $password = shift;

    $self -> clear_error();

    $username = $self -> safe_username($username)
        or return undef;

    foreach my $host (@{$self -> {"allowed_hosts"}}) {
        $self -> _create_update_user($username, $host, $password)
            or return undef;
    }

    return 1;
}


## @method $ create_user_database($username)
# Create a database for the specified user and grant access to the user from
# all allowed hosts. If the user's database already exists, this does nothing.
#
# @param username The name of the user to create the database for.
# @return true on success, undef on error.
sub create_user_database {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    $username = $self -> safe_username($username)
        or return undef;

    foreach my $host (@{$self -> {"allowed_hosts"}}) {
        $self -> _create_database($username, $host)
            or return undef;
    }

    return 1;
}


# @method $ delete_user_account($username)
# Delete the user's database and accounts in the system. This is a no-way-back
# process, so make sure it gets confirmed!
#
# @param username The name of the user to nuke the account for.
# @return true on succes, undef on error.
sub delete_user_account {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    $username = $self -> safe_username($username)
        or return undef;

    $self -> _delete_database($username)
        or return undef;

    foreach my $host (@{$self -> {"allowed_hosts"}}) {
        $self -> _delete_user($username, $host)
            or return undef;
    }

    return 1;
}


## @method $ _flush_privileges()
# Flush the privileges to pick up the new user.
#
# @return true on success, undef on error.
sub flush_privileges {
    my $self = shift;

    $self -> clear_error();

    my $privh = $self -> {"user_dbh"} -> prepare("FLUSH PRIVILEGES");
    $privh -> execute()
        or return $self -> self_error("Unable to perform privileges update: ".$self -> {"user_dbh"} -> errstr);

    return 1;
}


## @method $ store_user_password($userid, $password)
# Store the password set by the user for their database. This is... less than ideal,
# but it is the only way in which the config.inc.php can be generated at runtime
# and persist across repository updates.
#
# @param userid   The ID of the user's account.
# @param password The password the user set for their database
# @return true on success, undef on error.
sub store_user_password {
    my $self     = shift;
    my $userid   = shift;
    my $password = shift;

    $self -> clear_error();

    my $setpassh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"userdbs"}."`
                                                (user_id, user_pass)
                                                VALUES(?, ?)
                                                ON DUPLICATE KEY UPDATE user_pass = VALUES(user_pass)");
    $setpassh -> execute($userid, $password)
        or return $self -> self_error("Unable to record user database information: ".$self -> {"dbh"} -> errstr);

    return 1;
}


## @method $ get_user_password($username)
# Given a username, obtain the password that user set on their database.
#
# @param username The name of the user to fetch the password for.
# @return The password on success, undef on error.
sub get_user_password {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    $username = $self -> safe_username($username)
        or return undef;

    my $getpassh = $self -> {"dbh"} -> prepare("SELECT user_pass
                                                FROM `".$self -> {"settings"} -> {"database"} -> {"userdbs"}."` AS p,
                                                     `".$self -> {"settings"} -> {"database"} -> {"users"}."` AS u
                                                WHERE p.user_id = u.user_id
                                                AND u.username LIKE ?");
    $getpassh -> execute($username)
        or return $self -> self_error("Unable to check user database information: ".$self -> {"dbh"} -> errstr);

    my $pass = $getpassh -> fetchrow_arrayref()
        or return $self -> self_error("No information stored for user $username");

    return $pass -> [0];
}


# ============================================================================
#  Private and ghastly internals


## @method private $ _get_user_account($username, $host)
# Look up the specified user in the user table.
#
# @param username The name of the user account to fetch.
# @param host     The host the user can connect from. This must be specified,
#                 and wildcards are treated as literals rather than wildcards.
# @return A reference to a hash containing the user's data on success, an empty
#         hash if the account does not exist, or undef on error.
sub _get_user_account {
    my $self     = shift;
    my $username = shift;
    my $host     = shift;

    $self -> clear_error();

    # Does the user account exist?
    my $userh = $self -> {"user_dbh"} -> prepare("SELECT * FROM `user`
                                                  WHERE `User` = ?
                                                  AND `Host` = ?");
    $userh -> execute($username, $host)
        or return $self -> self_error("Unable to execute user lookup: ".$self -> {"user_dbh"} -> errstr);

    return $userh -> fetchrow_hashref() || {};
}


## @method private $ _user_database_exists($username)
# Determine whether a database for the specified name exists in the system.
#
# @param username The username to determine whether a database exists for.
# @return true if the database exists, false if it does not, undef on error.
sub _user_database_exists {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    my $datah = $self -> {"user_dbh"} -> prepare("SHOW DATABASES LIKE ?");
    $datah -> execute($username)
        or return $self -> self_error("Unable to perform user check: ".$self -> {"user_dbh"} -> errstr);

    my $database = $datah -> fetchrow_arrayref();

    return $database ? 1 : 0;
}


## @method private $ _create_update_user($username, $host, $password)
# Create a user account with the specified host and password, or update the password
# if the account already exists.
#
# @param username The name of the user account to create/update.
# @param host     The host to use for the user.
# @param password The password to set for the user account
# @return true on success, undef on error
sub _create_update_user {
    my $self     = shift;
    my $username = shift;
    my $host     = shift;
    my $password = shift;

    $self -> clear_error();

    my $user = $self -> _get_user_account($username, $host)
        or return undef;

    if($user -> {"User"}) {
        # User exists, need to update the password.
        my $passh = $self -> {"user_dbh"} -> prepare("UPDATE `user`
                                                      SET `Password` = PASSWORD(?)
                                                      WHERE `User` = ?
                                                      AND `Host` = ?");
        my $result = $passh -> execute($password, $username, $host);
        return $self -> self_error("Unable to execute user update: ".$self -> {"user_dbh"} -> errstr) if(!$result);
        return $self -> self_error("User update failed: no rows updated") if($result eq "0E0");

    } else {
        # User does not exist, create the account
        my $acch = $self -> {"user_dbh"} -> prepare('CREATE USER ?@? IDENTIFIED BY ?');
        $acch -> execute($username, $host, $password)
            or return $self -> self_error("Unable to create new user: ".$self -> {"user_dbh"} -> errstr);

        # Confirm that the user account exists
        $user = $self -> _get_user_account($username, $host)
            or return undef;

        return $self -> self_error("User account creation failed, please try again later.")
            if(!$user -> {"User"});
    }

    # User account exists, update the account's grant settings.
    my $granth = $self -> {"user_dbh"} -> prepare('GRANT USAGE ON *.* TO ?@? WITH MAX_USER_CONNECTIONS 2');
    $granth -> execute($username, $host)
        or return $self -> self_error("Unable to grant usage rights to user account: ".$self -> {"user_dbh"} -> errstr);

    return 1;
}


## @method private $ _delete_user($username, $host)
# Delete the specified user from the system, revoking any privileges the user
# may hold.
#
# @param username The name of the user to delete. Must have been passed through
#                 safe_username() first!
# @param host     The host to use for the user.
# @return true on success, undef on error.
sub _delete_user {
    my $self     = shift;
    my $username = shift;
    my $host     = shift;

    $self -> clear_error();

    my $nukeh = $self -> {"user_dbh"} -> prepare('DROP USER ?@?');
    $nukeh -> execute($username, $host)
        or return $self -> self_error("Unable to delete user account: ".$self -> {"user_dbh"} -> errstr());

    return 1;
}


## @method private $ _create_database($username, $host)
# Create a database for the specified user if it does not exist, and
# grant access to the user from the specified host.
#
# @param username The name of the user account to create the database for.
#                 Must have been passed through safe_username() first!
# @param host     The host to use for the user.
# @return true on success, undef on error.
sub _create_database {
    my $self     = shift;
    my $username = shift;
    my $host     = shift;

    $self -> clear_error();

    # Does the database already exist?
    if(!$self -> _user_database_exists($username)) {
        # Create the database...
        my $newh = $self -> {"user_dbh"} -> prepare("CREATE DATABASE IF NOT EXISTS `$username`
                                                     DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci");
        $newh -> execute()
            or return $self -> self_error("Unable to create database for $username: ".$self -> {"user_dbh"} -> errstr);

        # Make sure it exists....
        return $self -> self_error("Creation of user database failed, please try again later.")
            if(!$self -> _user_database_exists($username));
    }

    # Now give the user access
    my $accessh = $self -> {"user_dbh"} -> prepare("GRANT ALL PRIVILEGES ON `$username`.* TO ?\@?");
    $accessh -> execute($username, $host)
        or return $self -> self_error("Unable to grant access to database for $username: ".$self -> {"user_dbh"} -> errstr);

    return 1;
}


## @method private $ _delete_database($username)
# Delete the specified database from the system. Use with caution.
#
# @param username The name of the user to delete the database for.
# @return true on nukeage, false otherwise
sub _delete_database {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    my $nukeh = $self -> {"user_dbh"} -> prepare("DROP DATABASE IF EXISTS `$username`");
    $nukeh -> execute()
        or return $self -> self_error("Unable to remove user database: ".$self -> {"user_dbh"} -> errstr);

    return 1;
}

1;

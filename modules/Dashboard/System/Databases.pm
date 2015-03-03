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

    return $self;
}


# ============================================================================
#  Utility

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


## @method void log($type, $message)
# Log the current user's actions in the system. This is a convenience wrapper around the
# Logger::log function.
#
# @param type     The type of log entry to make, may be up to 64 characters long.
# @param message  The message to attach to the log entry, avoid messages over 128 characters.
sub log {
    my $self     = shift;
    my $type     = shift;
    my $message  = shift;

    $self -> {"logger"} -> log($type, 0, undef, $message);
}


# ============================================================================
#  Database handling

## @method @ get_user_database_server($username)
# Given a username, fetch the hostname of the machine the user's database is on.
# This will establish the connection to the user dabase server if it is not already
# available.
#
# @param username The username of the user to fetch the databae hostname for.
# @return The hostname of the machine the user's database is on, the username used
#         to connect to it, and the password used.
sub get_user_database_server {
    my $self = shift;

    $self -> clear_error();

    if(!$self -> {"user_dbh"}) {
        $self -> {"user_dbh"} = DBI->connect($self -> {"settings"} -> {"userdatabase"} -> {"database"},
                                             $self -> {"settings"} -> {"userdatabase"} -> {"username"},
                                             $self -> {"settings"} -> {"userdatabase"} -> {"password"},
                                             { RaiseError => 0, AutoCommit => 1, mysql_enable_utf8 => 1 })
            or return $self -> self_error("Unable to connect to user database server: ".$DBI::errstr);
    }

    return ( $self -> {"user_dbh"},
             $self -> {"settings"} -> {"userdatabase"} -> {"hostname"},
             $self -> {"settings"} -> {"userdatabase"} -> {"username"},
             $self -> {"settings"} -> {"userdatabase"} -> {"password"} );
}


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

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    # check for the user first
    my $userh = $dbh -> prepare("SELECT COUNT(*)
                                 FROM user
                                 WHERE User LIKE ?");
    $userh -> execute($username)
        or return $self -> self_error("Unable to perform user check: ".$dbh -> errstr);

    my $usercount = $userh -> fetchrow_arrayref()
        or return $self -> self_error("Unable to retrieve user account count.");

    # If the number of entries in the database for the user is less than the number
    # of hosts set up for the user, indicate a problem.
    return 0 if($usercount -> [0] < scalar(@{$self -> {"allowed_hosts"}}));

    # Now check that the user's database exists
    return $self -> _database_exists($username, $username);
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

    $self -> log("database", "Setting up user account for $username");

    $self -> create_user_account($username, $password)
        or return undef;

    $self -> create_user_database($username)
        or return undef;

    $self -> flush_privileges($username)
        or return undef;

    $self -> store_user_password($username, $user -> {"user_id"}, $password)
        or return undef;

    $self -> log("database", "Completed user account for $username");

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


## @method $ create_user_database($username, $dbname)
# Create a database for the specified user and grant access to the user from
# all allowed hosts. If the user's database already exists, this does nothing.
#
# @param username The name of the user to create the database for.
# @param dbname   An optional database name. If not set, this defaults to
#                 the username.
# @return true on success, undef on error.
sub create_user_database {
    my $self     = shift;
    my $username = shift;
    my $dbname   = shift || $username;

    $self -> clear_error();

    $username = $self -> safe_username($username)
        or return undef;

    foreach my $host (@{$self -> {"allowed_hosts"}}) {
        $self -> _create_user_database($username, $dbname, $host)
            or return undef;
    }

    $self -> set_user_database($username, $dbname)
        or return undef;

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

    my $databases = $self -> get_user_databases($username)
        or return undef;

    foreach my $database (@{$databases}) {
        $self -> delete_user_database($username, $database -> {"name"})
            or return undef;
    }

    foreach my $host (@{$self -> {"allowed_hosts"}}) {
        $self -> _delete_user($username, $host)
            or return undef;
    }

    return 1;
}


## @method $ _flush_privileges($username)
# Flush the privileges to pick up the new user.
#
# @param username The name of the user triggering the flush.
# @return true on success, undef on error.
sub flush_privileges {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    my $privh = $dbh -> prepare("FLUSH PRIVILEGES");
    $privh -> execute()
        or return $self -> self_error("Unable to perform privileges update: ".$dbh -> errstr);

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

    my $setpassh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"useraccts"}."`
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
                                                FROM `".$self -> {"settings"} -> {"database"} -> {"useraccts"}."` AS p,
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
#  Multi-database support stuff


## @method $ set_user_database($username, $dbname, $project, $source)
# Associate the specified database with the provided user. This allows the system
# to keep track of which databases belong specifically to a given user (rather
# than shared between users, as with group databases). Most users will only have
# a single database, but users with elevated permissions may have multiple.
#
# @param username The name of the user the database belongs to.
# @param dbname   The name of the database.
# @param project  The project directory to associate the database with. If NULL,
#                 it is the user's default global database.
# @param source   If the database is a clone of another, this is the name of
#                 the source database. undef if not a clone.
# @return true on success, undef on error.
sub set_user_database {
    my $self     = shift;
    my $username = shift;
    my $dbname   = shift;
    my $project  = shift;
    my $source   = shift;

    $self -> clear_error();

    my $user = $self -> {"session"} -> get_user($username, 1)
        or return $self -> self_error("Unable to get details for user '$username': ".$self -> {"session"} -> errstr());

    # Use the unique constraint on the (userid,dbname) index to allow updates to source
    # without special update code.
    my $setudbh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"userdatabases"}."`
                                               (`user_id`, `dbname`, `source`) VALUES(?, ?, ?)
                                               ON DUPLICATE KEY UPDATE
                                               `source` = VALUES(`source`)");
    $setudbh -> execute($user -> {"user_id"}, $dbname, $source)
        or return $self -> self_error("Unable to set user database: ".$self -> {"dbh"} -> errstr());

    return $self -> set_user_database_project($username, $dbname, $project)
        if($project);

    return 1;
}


## @method $ delete_user_database($username, $dbname)
# Remove the specfified database from the user's list of databases. This will also
# remove any project allocations for the database for the user.
#
# @param username The name of the user who owns the database.
# @param dbname   The name of the database to delete.
# @return true on success, undef on error.
sub delete_user_database {
    my $self     = shift;
    my $username = shift;
    my $dbname   = shift;

    $self -> clear_error();

    $self -> _delete_database($username, $database -> {"name"})
        or return undef;

    my $user = $self -> {"session"} -> get_user($username, 1)
        or return $self -> self_error("Unable to get details for user '$username': ".$self -> {"session"} -> errstr());

    # Find the ID for the database, this will handily ensure it exists too
    my $dbid = $self -> _get_user_database_id($username, $dbname)
        or return undef;

    # Nuke the database...
    my $nukeh = $self -> {"dbh"} -> prepare("DELETE FROM `".$self -> {"settings"} -> {"database"} -> {"userdatabases"}."`
                                             WHERE `user_id` = ?
                                             AND `dbname` LIKE ?");
    $nukeh -> execute($user -> {"id"}, $dbname)
        or return $self -> self_error("Unable to delete user database row: ".$self -> {"dbh"} -> errstr());

    # and any project mappings that reference it
    my $maph = $self -> {"dbh"} -> prepare("DELETE FROM `".$self -> {"settings"} -> {"database"} -> {"userprojdbs"}."`
                                            WHERE `database_id` = ?");
    $maph -> execute($dbid)
        or return $self -> self_error("Unable to remove database-project mappings for $dbname:".$self -> {"dbh"} -> errstr());

    return 1;
}


## @method @ get_user_databases($username)
# Fetch a list of all databases owned by the specified user, and if possible the
# project(s) those databases are associated with.
#
# @param username The name of the user to fetchthe database list for.
# @return A reference to an array of database hashes, each element contains the
#         name and a reference to an array of projects the database is
#         associated with, or undef on error.
sub get_user_databases {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    my $user = $self -> {"session"} -> get_user($username, 1)
        or return $self -> self_error("Unable to get details for user '$username': ".$self -> {"session"} -> errstr());

    # Query to locate all the databases owned by the user
    my $dbdatah = $self -> {"dbh"} -> prepare("SELECT *
                                               FROM `".$self -> {"settings"} -> {"database"} -> {"userdatabases"}."`
                                               WHERE `user_id` = ?");

    # Query to fetch the projects a database is associated with
    my $dbprojh = $self -> {"dbh"} -> prepare("SELECT `project`
                                               FROM `".$self -> {"settings"} -> {"database"} -> {"userprojdbs"}."`
                                               WHERE `user_id` = ?
                                               AND `database_id` = ?");

    $dbdatah -> execute($user -> {"id"})
        or return $self -> self_error("Unable to execute user database lookup: ".$self -> {"dbh"} -> errstr());

    my @databases = ();
    while(my $data = $dbdatah -> fetchrow_hashref()) {
        $dbprojh -> execute($user -> {"id"}, $data -> {"id"})
            or return $self -> self_error("Unable to look up upser project database information: ".$self -> {"dbh"} -> errstr);

        my @projects = ();
        while(my $proj = $dbprojh -> fetchrow_arrayref()) {
            push(@projects, $proj -> [0]);
        }

        push(@databases, { "id"   => $data -> {"id"},
                           "name" => $data -> {"dbname"},
                           "project" => \@projects });
    }

    return \@databases;
}


## @method $ set_user_database_project($username, $database, $project)
# Associate a database with a project directory.
#
# @param username The name of the user to set the database for.
# @param database The name of the database to set.
# @param project  The name of the project directory (NOT the full path!)
# @return true on success, undef on error
sub set_user_database_project {
    my $self     = shift;
    my $username = shift;
    my $database = shift;
    my $project  = shift;

    $self -> clear_error();

    my $user = $self -> {"session"} -> get_user($username, 1)
        or return $self -> self_error("Unable to get details for user '$username': ".$self -> {"session"} -> errstr());

    my $dbid = $self -> _get_user_database_id($username, $database)
        or return undef;

    # Does a relation already exist for this database and project?
    my $checkh = $self -> {"dbh"} -> prepare("SELECT `id`
                                              FROM `".$self -> {"settings"} -> {"database"} -> {"userprojdbs"}."`
                                              WHERE `database_id` = ?
                                              AND `user_id` = ?
                                              AND `project` LIKE ?");
    $checkh -> execute($dbid, $user -> {"id"}, $project)
        or return $self -> self_error("Unable to check whether project relation exists: ".$self -> {"dbh"} -> errstr);

    # If the row exists, nothing to do here...
    my $exists = $checkh -> fetchrow_arrayref();
    return 1 if($exists && $exists -> [0]);

    # doesn't exist, so make it so...
    my $newh = $self -> {"dbh"} -> prepare("INSERT INTO `".$self -> {"settings"} -> {"database"} -> {"userprojdbs"}."`
                                            (`database_id`, `user_id`, `project`)
                                            VALUES(?, ?, ?)");
    my $result = $newh -> execute($dbid, $user -> {"id"}, $project);
    return $self -> self_error("Unable to execute database-project relation insert: ".$self -> {"dbh"} -> errstr) if(!$result);
    return $self -> self_error("Database-project relation creation failed: no rows added") if($result eq "0E0");

    return 1;
}


## @method $ get_user_database($username, $project)
# Fetch the database set for the specified project directory for the user.
# This looks up the database associated withteh specified project for the
# user, and returns the name if found. If no database has been associated
# with the project - or the project is not set - this returns the user's
# primary database name (the oen with their username).
#
# @param username The user to fetch the database name for.
# @param project  The project directory to filter the lookup by. If not
#                 set, this function returns the user's primary database.
# @return the database name to use for the user on success, undef on error.
sub get_user_database {
    my $self     = shift;
    my $username = shift;
    my $project  = shift;

    $self -> clear_error();

    my $user = $self -> {"session"} -> get_user($username, 1)
        or return $self -> self_error("Unable to get details for user '$username': ".$self -> {"session"} -> errstr());

    # If a project directory has been specified, look for it
    if($project) {
        my $dbnameh = $self -> {"dbh"} -> prepare("SELECT `db`.`dbname`
                                                   FROM `".$self -> {"settings"} -> {"database"} -> {"userdatabases"}."` AS `db`,
                                                        `".$self -> {"settings"} -> {"database"} -> {"userprojdbs"}."` AS `prj`
                                                   WHERE `prj`.`database_id` = `db`.`id`
                                                   AND `db`.`user_id` = ?
                                                   AND `prj`.`project` LIKE ?
                                                   ORDER BY `dbname`
                                                   LIMIT 1");
        $dbnameh -> execute($user -> {"id"}, $project)
            or return $self -> self_error("Unable to look up user database name: ".$self -> {"dbh"} -> errstr);

        # found a row? If so, return it
        my $dbname = $dbnameh -> fetchrow_arrayref();
        return $dbname -> [0] if($dbname);
    }

    # Use the default user database otherwise.
    return $username;
}


# ============================================================================
#  Group database related

## @method $ populate_group_database($groupdb)
# Attempt to populate the specified group database from a mysql script. This will
# extract the course name from the specified group database name, determine
# whether a script exists for that course, and if so it will run the script.
#
# @note This should only be called immediately after database creation. Calling
#       it more than once may result in user data loss or errors.
#
# @param groupdb The name of the group database to populate.
# @return true on success, undef on error.
sub populate_group_database {
    my $self    = shift;
    my $groupdb = shift;

    $self -> clear_error();

    # Pull out the course
    my ($course) = $groupdb =~ /^\d+_([a-z0-9]+)_\w+$/;
    return $self -> self_error("Unable to parse course name from group database '$groupdb'")
        unless($course);

    # does a script exist for the course?
    my $script = path_join($self -> {"settings"} -> {"config"} -> {"base"},
                           $self -> {"settings"} -> {"userdatabase"} -> {"grouppath"},
                           $course.".sql");
    if(-f $script) {
        # Script exists, run it
        my $cmd = $self -> {"settings"} -> {"userdatabase"} -> {"runscript"};
        $cmd =~ s/%d/$groupdb/;
        $cmd =~ s/%f/$script/;

        my $output = `$cmd`;
        if($output) {
            $self -> log("database", "Error running script for $groupdb: $output");
            return $self -> self_error("Unable to execute mysql script. Please report this error!");
        }

    } else {
        $self -> log("database", "No initialiser script for $groupdb ($script not found)");
    }

    return 1;
}


## @method $ get_user_group_databases($username)
# Obtain a list of group databases the specified user has access to. This will
# check the 'mysql.db' table for the list of databases the user can access, and
# filter out the user's own database.
#
# @param username The name of the user to fetch the database list for
# @return A reference to a hash containing the group databases the user has
#         access to, each database also includes a subhash indicating which hosts
#         the user can access it from.
sub get_user_group_databases {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    $username = $self -> safe_username($username)
        or return undef;

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    # We're interested in any databases the user has access to that do not have the same
    # name as the username (ie: not personal databases)
    my $grouph = $dbh -> prepare("SELECT Host,Db
                                  FROM `db`
                                  WHERE `User` = ?
                                  AND `Db` != `User`");
    $grouph -> execute($username)
        or return $self -> self_error("Unable to execute database list lookup");

    my $grouphash = {};
    # convert the results to a has for faster lookups
    while(my $group = $grouph -> fetchrow_hashref()) {
        $grouphash -> {$group -> {"Db"}} -> {$group -> {"Host"}} -> {"access"} = 1;
    }

    return $grouphash;
}


## @method $ set_user_group_databases($username, $grouplist)
# Ensure that the specified user has access to the provided group databases, and
# remove access from any group databases the user should not have access to.
#
# @param username  The username of the user to set the group database access for.
# @param grouplist A reference to a list of group database names.
# @return A reference to a hash containing the database access information, undef on error.
sub set_user_group_databases {
    my $self      = shift;
    my $username  = shift;
    my $grouplist = shift;
    my @newdbs    = ();

    $self -> clear_error();

    $self -> log("database", "Updating group database accounts for $username");

    $username = $self -> safe_username($username)
        or return undef;

    # first find out which databases the user has access to
    my $groups = $self -> get_user_group_databases($username)
        or return undef;

    # Now check through the list of groups the user /should/ have access to. If
    # the database doesn't exist at all, it needs to be created, then the user
    # access from all allowed hosts to that database need to be checked
    foreach my $groupname (@{$grouplist}) {
        $self -> _set_group_database($username, $groupname, $groups)
            or return undef;
    }

    # now go through the list of group databases the user has access to,
    # removing access to databases they no longer should be able see
    foreach my $database (keys(%{$groups})) {
        next if($database eq "_internal");

        foreach my $host (@{$self -> {"allowed_hosts"}}) {
            next if($groups -> {$database} -> {"active"}); # Keep access to active groups

            $self -> log("database", "Removing access to $database from $username\@$host");
            $self -> _revoke_all($username, $database, $host)
                or return undef;

            $groups -> {"_internal"} -> {"save_config"} = 1; # mark the need to save the config
        }
    }

    return $groups;
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

    $username = $self -> safe_username($username)
        or return undef;

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    # Does the user account exist?
    my $userh = $dbh -> prepare("SELECT * FROM `user`
                                 WHERE `User` = ?
                                 AND `Host` = ?");
    $userh -> execute($username, $host)
        or return $self -> self_error("Unable to execute user lookup: ".$dbh -> errstr);

    return $userh -> fetchrow_hashref() || {};
}


## @method private $ _database_exists($username, $dbname)
# Determine whether a database with the specified name exists in the system.
#
# @param username The name of the user this is a database for.
# @param dbname   The name of the database to check the existence of.
# @return true if the database exists, false if it does not, undef on error.
sub _database_exists {
    my $self     = shift;
    my $username = shift;
    my $dbname   = shift;

    $self -> clear_error();

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    my $datah = $dbh -> prepare("SHOW DATABASES LIKE ?");
    $datah -> execute($dbname)
        or return $self -> self_error("Unable to perform user check: ".$dbh -> errstr);

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

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    if($user -> {"User"}) {
        $self -> log("database", "Updating account for $username\@$host");

        # User exists, need to update the password.
        my $passh = $dbh -> prepare("UPDATE `user`
                                     SET `Password` = PASSWORD(?)
                                     WHERE `User` = ?
                                     AND `Host` = ?");
        my $result = $passh -> execute($password, $username, $host);
        return $self -> self_error("Unable to execute user update: ".$dbh -> errstr) if(!$result);
        return $self -> self_error("User update failed: no rows updated") if($result eq "0E0");

    } else {
        $self -> log("database", "Creating account for $username\@$host");

        # User does not exist, create the account
        my $acch = $dbh -> prepare('CREATE USER ?@? IDENTIFIED BY ?');
        $acch -> execute($username, $host, $password)
            or return $self -> self_error("Unable to create new user: ".$dbh -> errstr);

        # Confirm that the user account exists
        $user = $self -> _get_user_account($username, $host)
            or return undef;

        return $self -> self_error("User account creation failed, please try again later.")
            if(!$user -> {"User"});
    }

    # User account exists, update the account's grant settings.
    my $granth = $dbh -> prepare('GRANT USAGE ON *.* TO ?@? WITH MAX_USER_CONNECTIONS 2');
    $granth -> execute($username, $host)
        or return $self -> self_error("Unable to grant usage rights to user account: ".$dbh -> errstr);

    $self -> log("database", "Account for $username\@$host set up");

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
    $self -> log("database", "Deleting user account $username\@$host");

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    my $nukeh = $dbh -> prepare('DROP USER ?@?');
    $nukeh -> execute($username, $host)
        or return $self -> self_error("Unable to delete user account: ".$dbh -> errstr());

    return 1;
}


## @method private $ _create_database($username, $name)
# Create a database with the specified name.
#
# @param username The user this is a database for.
# @param name     The name of the database to create.
# @return true on success, undef on error
sub _create_database {
    my $self     = shift;
    my $username = shift;
    my $name     = shift;

    $self -> clear_error();
    $self -> log("database", "Creating database $name for $username");

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    # Create the database...
    my $newh = $dbh -> prepare("CREATE DATABASE IF NOT EXISTS `$name`
                                DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci");
    $newh -> execute()
        or return $self -> self_error("Unable to create database '$name': ".$dbh -> errstr);

    # Make sure it exists....
    return $self -> self_error("Creation of database failed, please try again later.")
        if(!$self -> _database_exists($username, $name));

    $self -> log("database", "Database $name created");

    return 1;
}


## @method private $ _create_user_database($username, $dbname, $host)
# Create a database for the specified user if it does not exist, and
# grant access to the user from the specified host.
#
# @param username The name of the user account to create the database for.
#                 Must have been passed through safe_username() first!
# @param name     The name of the database to create.
# @param host     The host to use for the user.
# @return true on success, undef on error.
sub _create_user_database {
    my $self     = shift;
    my $username = shift;
    my $dbname   = shift;
    my $host     = shift;

    $self -> clear_error();

    # Create the database if it doesn't exist.
    $self -> _create_database($username, $dbname) or return undef
        unless($self -> _database_exists($username, $dbname));

    # Now give the user access
    $self -> _grant_all($username, $dbname, $host)
        or return undef;

    return 1;
}


## @method private $ _delete_database($username, $name)
# Delete the specified database from the system. Use with caution.
#
# @param username The user the database is for.
# @param name The name of the database to delete.
# @return true if the database was deleted (or did not exist!), false otherwise
sub _delete_database {
    my $self     = shift;
    my $username = shift;
    my $name     = shift;

    $self -> clear_error();

    $self -> log("database", "Deleting database $name");

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    my $nukeh = $dbh -> prepare("DROP DATABASE IF EXISTS `$name`");
    $nukeh -> execute()
        or return $self -> self_error("Unable to remove user database: ".$dbh -> errstr);

    return 1;
}


## @method private $ _set_group_database($username, $groupname, $grouphash)
# Grant the specified user access to the database for the specified group. This will
# create the group database if it does not exist, and give the user access to it
# (if the user does not exist, they will get access as soon as their account is
# created). If the user already has access to the group database, this simply
# records the access as current and returns. The specified group hash should be
# of the form
#
# { databasename => { hostname => { access => 0|1 (1 if the user has access from this host, 0 if not)
#                                 },
#                     hostname => { access => 0|1
#                                 },
#                   },
#   etc...
# }
#
# During this function, the access flag for each allowed host may be updated to
# reflect whether the user has access. This will also set a 'created' flag if the
# datbase is created by setting grouphash -> {groupname} -> {"created"} to true.
# This will also mark each database -> {hostname} -> {"active"} to true when
# called for a given database.
#
# @param username  The name of the user to grant access to.
# @param groupname The name of the group database to give the user access to.
# @param grouphash A reference to a hash containing group database info,
#                  as generated by the get_user_group_databases() function.
# @return true on success, undef on error.
sub _set_group_database {
    my $self      = shift;
    my $username  = shift;
    my $groupname = shift;
    my $grouphash = shift;

    $self -> clear_error();

    $self -> log("database", "Granting access to $groupname for $username");

    # does the database exist? If not, make it
    if(!$self -> _database_exists($username, $groupname)) {
        $self -> _create_database($username, $groupname)
            or return undef;

        # record that the database was created so it can be populated later if needed
        $grouphash -> {$groupname} -> {"created"} = 1;

        # Run the populate script if needed
        $self -> populate_group_database($groupname)
            or return undef;
    }

    # Does the user have access from each host?
    foreach my $host (@{$self -> {"allowed_hosts"}}) {
        if(!$grouphash -> {$groupname} -> {$host} -> {"access"}) {
            $self -> _grant_all($username, $groupname, $host)
                or return undef;

            $grouphash -> {$groupname} -> {$host} -> {"access"} = 1;
            $grouphash -> {"_internal"} -> {"save_config"} = 1; # mark the need to save the config
        }

        # Mark the access as current, so old access can be revoked
        $grouphash -> {$groupname} -> {"active"} = 1;
    }

    return 1;
}


## @method private $ _grant_all($username, $dbname, $host)
# Give all privileges on the specified database to the provided user.
#
# @param username The name of the user to give the access to.
# @param database The name of the database to grant access to.
# @param host     The host the user is connecting from.
# @return true on success, undef on error
sub _grant_all {
    my $self     = shift;
    my $username = shift;
    my $dbname   = shift;
    my $host     = shift;

    $self -> log("database", "Granting all privileges on $dbname to $username\@$host");

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    my $accessh = $dbh -> prepare("GRANT ALL PRIVILEGES ON `$dbname`.* TO ?\@?");
    $accessh -> execute($username, $host)
        or return $self -> self_error("Unable to grant access to $dbname for $username: ".$dbh -> errstr);

    return 1;
}


## @method private $ _revoke_all($username, $dbname, $host)
# Remove all privileges on the specified database from the provided user.
#
# @param username The name of the user to remove the access from.
# @param database The name of the database to remove access to.
# @param host     The host the user is connecting from.
# @return true on success, undef on error
sub _revoke_all {
    my $self     = shift;
    my $username = shift;
    my $dbname   = shift;
    my $host     = shift;

    $self -> log("database", "Revoking all privileges on $dbname from $username\@$host");

    my ($dbh) = $self -> get_user_database_server($username)
        or return undef;

    my $accessh = $dbh -> prepare("REVOKE ALL PRIVILEGES ON `$dbname`.* FROM ?\@?");
    $accessh -> execute($username, $host)
        or return $self -> self_error("Unable to revoke access to $dbname from $username: ".$dbh -> errstr);

    return 1;
}


## @method private $ _get_user_database_id($username, $database)
# Given a username and database name, locate the ID of the row that
# associates the database with the user.
#
# @param username The name of the user that owns the database
# @param database The name of the database to fetch the Id for.
# @return The database row Id on success, undef on error.
sub _get_user_database_id {
    my $self = shift;
    my $username = shift;
    my $database = shift;

    $self -> clear_error();

    my $user = $self -> {"session"} -> get_user($username, 1)
        or return $self -> self_error("Unable to get details for user '$username': ".$self -> {"session"} -> errstr());

    my $dbidh = $self -> {"dbh"} -> prepare("SELECT `id`
                                             FROM `".$self -> {"settings"} -> {"database"} -> {"userdatabases"}."`
                                             WHERE `user_id` = ?
                                             AND `database` LIKE ?");
    $dbidh -> execute($user -> {"id"}, $database)
        or return $self -> self_error("Unable to look up user database: ".$self -> {"dbh"} -> errstr);

    my $dbid = $dbidh -> fetchrow_arrayref();

    return $dbid ? $dbid -> [0] : $self -> self_error("Unable to find database '$database' for user '$username'");
}

1;

## @file
# This file contains the implementation of the bridge to the userdata databse.
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
package Dashboard::System::UserDataBridge;

use strict;
use base qw(Webperl::SystemModule); # This class extends the system module
use v5.12;

# ============================================================================
#  Constructor

## @cmethod $ new(%args)
# Create a new Matrix object to manage matrix interaction.
# The minimum values you need to provide are:
#
# * dbh       - The database handle to use for queries.
# * settings  - The system settings object
# * metadata  - The system Metadata object.
# * roles     - The system Roles object.
# * logger    - The system logger object.
#
# @param args A hash of key value pairs to initialise the object with.
# @return A new Matrix object, or undef if a problem occured.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;
    my $self     = $class -> SUPER::new(@_)
        or return undef;

    # Check that the required objects are present
    return Webperl::SystemModule::set_error("No metadata object available.") if(!$self -> {"metadata"});
    return Webperl::SystemModule::set_error("No roles object available.")    if(!$self -> {"roles"});

    $self -> {"udata_dbh"} = DBI->connect($self -> {"settings"} -> {"userdata"} -> {"database"},
                                          $self -> {"settings"} -> {"userdata"} -> {"username"},
                                          $self -> {"settings"} -> {"userdata"} -> {"password"},
                                          { RaiseError => 0, AutoCommit => 1, mysql_enable_utf8 => 1 })
        or return Webperl::SystemModule::set_error("Unable to connect to userdata database: ".$DBI::errstr);

    return $self;
}


# ============================================================================
#  Data access

## @method $ get_valid_years($as_options)
# Obtain a list of academic years for which there is user information in the userdata
# database.
#
# @param as_options If this is set to true, the reference returned by this function
#                   contains the year data in a format suitable for use as <select>
#                   options via Webperl::Template::build_optionlist().
# @return A reference to an array containing year data hashrefs on success, undef
#         on error.
sub get_valid_years {
    my $self       = shift;
    my $as_options = shift;

    $self -> clear_error();

    my $lookuph = $self -> {"udata_dbh"} -> prepare("SELECT DISTINCT y.*
                                                     FROM `".$self -> {"settings"} -> {"userdata"} -> {"user_years"}."` AS `l`,
                                                          `".$self -> {"settings"} -> {"userdata"} -> {"acyears"}."` AS `y`
                                                     WHERE `y`.`id` = `l`.`year_id`
                                                     ORDER BY `y`.`start_year` DESC");
    $lookuph -> execute()
        or return $self -> self_error("Unable to execute academic year lookup: ".$self -> {"udata_dbh"} -> errstr);

    my $rows = $lookuph -> fetchall_arrayref({})
        or return $self -> self_error("Error fetching rows from year lookup");

    # If the data should be returned as-is, do so.
    return $rows if(!$as_options);

    # Otherwise, convert to an options-friendly format

    my @yearlist = ();
    foreach my $year (@{$rows}) {
        push(@yearlist, { "value" => $year -> {"id"},
                          "name"  => $year -> {"start_year"}."/".$year -> {"end_year"}});
    }

    return \@yearlist;
}


## @method private $ _add_multiparam($settings, $params, $table, $field, $type, $mode)
# Construct a potentially multi-parameter where clause based on the spcified settings.
# This creates a where clause that compares the specified table and field to each
# of the comma separated values in the settings.
#
# @param settings A comma separated string of values to use in the where clause.
# @param params   A reference to an array to store bind variable parameters in.
# @param table    The name of the table to apply there where clauses in.
# @param field    The name of the field in the table to perform the where on.
# @param type     The type of comparison to use, defaults to "=".
# @param mode     The where mode, defaults to "AND" (all values in the settings must
#                 match), or "OR" (at least one of the settings must match).
# @return A string containing the where clause text.
sub _add_multiparam {
    my $self      = shift;
    my $settings  = shift;
    my $params    = shift;
    my $table     = shift;
    my $field     = shift;
    my $type      = shift || "=";
    my $mode      = shift || "AND";

    my @entries = split(/,/, $settings);
    my @wheres = ();
    foreach my $entry (@entries) {
        push(@wheres, "`$table`.`$field` $type ?");
        push(@{$params}, $entry);
    }

    my $where = join(" $mode ", @wheres);

    return "AND ($where) ";
}


## @method $ get_user_addresses($settings)
# Fetch an array of all user addresses that match the query controlled by the
# specified settings. The settings hash provided may contain:
#
# - `yearid`: the academic year to fetch students for (this should always be
#       specified.
# - `level`: academic level, seperate multiple levels with commas, supported values are:
#       0 = PGR, 1 = UG Year 1, 2 = UG Year 2, 3 = UG Year 3, 4 = UG Year 4, 6 = PGT
# - `plan`: A comma separated list of plan names to include (if
#           set, and a student is not on a listed programme, they are
#           not included in the list). This may include wildcards.
# - `exlplan`: A comma seperated list of plan names to exclude (if set,
#              students are included as long as they are not on the specified
#              plan(s))
# - `course`: A comma separated list of courses the student must be in. Note that
#             the student must be in all of the courses.
sub get_user_addresses {
    my $self     = shift;
    my $settings = shift;

    my $tables  = '`'.$self -> {"settings"} -> {"userdata"} -> {"users"}.'` AS `u`';
    my @params = ();
    my $where  = "";

    # All students at a given level in a given year
    if(defined($settings -> {"level"}) && defined($settings -> {"yearid"})) {
        $tables .= ", `".$self -> {"settings"} -> {"userdata"} -> {"user_years"}."` AS `l`";
        $where  .= "`u`.`user_id` = `l`.`student_id` AND `l`.`year_id` = ? ";
        push(@params, $settings -> {"yearid"});

        $where .= $self -> _add_multiparam($settings -> {"level"}, \@params, "l", "level")

    # All students in a given year
    } elsif(defined($settings -> {"yearid"})) {
        $tables .= ", `".$self -> {"settings"} -> {"userdata"} -> {"user_years"}."` AS l";
        $where  .= "`u`.`user_id` = `l`.`student_id` AND `l`.`year_id` = ? ";
        push(@params, $settings -> {"yearid"});
    }

    # plan filtering, inclusive
    if(defined($settings -> {"plan"})) {
        $tables .= ", `".$self -> {"settings"} -> {"userdata"} -> {"acplans"}."` AS `pl`";
        $tables .= ", `".$self -> {"settings"} -> {"userdata"} -> {"user_plans"}."` AS `p`";
        $where  .= "AND" if($where);
        $where  .= " `p`.`student_id` = `u`.`user_id` AND `pl`.`id` = `p`.`plan_id` ";

        $where .= $self -> _add_multiparam($settings -> {"plan"}, \@params, "pl", "name", "LIKE");

        # Allow for exclusion at the same time as inclusion.
        $where .= $self -> _add_multiparam($settings -> {"exlplan"}, \@params, "pl", "name", "NOT LIKE")
            if(defined($settings -> {"exlplan"}));

    } elsif(defined($settings -> {"exlplan"})) {
        $tables .= ", `".$self -> {"settings"} -> {"userdata"} -> {"acplans"}."` AS `pl`";
        $tables .= ", `".$self -> {"settings"} -> {"userdata"} -> {"user_plans"}."` AS `p`";
        $where  .= "AND" if($where);
        $where  .= " `p`.`student_id` = `u`.`user_id` AND `pl`.`id` = `p`.`plan_id` ";

        $where .= $self -> _add_multiparam($settings -> {"exlplan"}, \@params, "pl", "name", "NOT LIKE");
    }

    if(defined($settings -> {"course"}) && defined($settings -> {"yearid"})) {
        $tables .= ", `".$self -> {"settings"} -> {"userdata"} -> {"courses"}."` AS `c`";
        $tables .= ", `".$self -> {"settings"} -> {"userdata"} -> {"user_course"}."` AS `uc`";
        $where  .= "AND `uc`.`user_id` = `u`.`user_id` AND `c`.`id` = `uc`.`course_id` AND `uc`.`year_id` = ? ";
        push(@params, $settings -> {"yearid"});

        $where .= $self -> _add_multiparam($settings -> {"course"}, \@params, "c", "course_id", "LIKE", "OR");
    }

    my $query = "SELECT `u`.`email`
                 FROM $tables
                 WHERE $where";
    my $queryh = $self -> {"udata_dbh"} -> prepare($query);
    $queryh -> execute(@params)
        or return $self -> self_error("Unable to execute student lookup: ".$self -> {"udata_dbh"} -> errstr);

    my @emails = ();
    while(my $row = $queryh -> fetchrow_arrayref()) {
        push(@emails, $row -> [0]);
    }

    return \@emails;
}


## @method $ get_user_groupnames($username)
# Given a username, obtain a list of course groups the user should have
# access to. The group names returned take the form <year>_<course>_<group>,
# and all characters are lowercase.
#
# @param username The username of the user to fetch the group list for
# @return A reference to an array of group names the user should have access
#         to (which may be empty), undef on error.
sub get_user_groupnames {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    # Get the user's data
    my $user = $self -> _get_user($username)
        or return undef;

    # And the list of groups the user is in
    my $groups = $self -> _get_user_coursegroups($user -> {"user_id"})
        or return undef;

    # now convert the list above into a single list of strings
    my @grouplist = ();
    foreach my $group (@{$groups}) {
        # Always force lowercase; mixed case/uppercase could be a pain later
        push(@grouplist, lc($group -> {"year"}."_".$group -> {"course"}."_".$group -> {"group"}))
    }

    return \@grouplist;
}


# ============================================================================
#  Private support stuff


## @method private $ _get_user($username)
# Given a username, obtain the user information for the specified user.
#
# @param username The username of the user to fetch the data for.
# @return A reference to the user's data on success, undef on error.
sub _get_user {
    my $self     = shift;
    my $username = shift;

    $self -> clear_error();

    my $userh = $self -> {"udata_dbh"} -> prepare("SELECT *
                                                   FROM `".$self -> {"settings"} -> {"userdata"} -> {"users"}."`
                                                   WHERE `username` LIKE ?
                                                   LIMIT 1");
    $userh -> execute($username)
        or return $self -> self_error("Unable to execute userdata user lookup: ".$self -> {"dbh"} -> errstr);

    return $userh -> fetchrow_hashref()
        or $self -> self_error("No userdata user information for '$username'");
}


## @method private $ _get_user_coursegroups($userid, $active)
# Given a userid, obtain a list of the course group names, courses, and years the user was
# a member of the group.
#
# @param userid The ID of the user to fetch the group list for.
# @param active If set to 1 (the default) this will return only groups the user is currently
#               in (or was in in previous years). If set to 0, this will return groups the
#               user was in but was removed from.
# @return A reference to a list of hashrefs containing the group year, course name, and name
#         for each group the user is in (which may be an empty list if the user isnot in
#         any groups) on success, undef on error.
sub _get_user_coursegroups {
    my $self   = shift;
    my $userid = shift;
    my $active = shift;

    $self -> clear_error();

    $active = 1 if(!defined($active));

    my $groupsh = $self -> {"udata_dbh"} -> prepare("SELECT `y`.`start_year` AS `year`, `c`.`course_id` AS `course`, `g`.`name` AS `group`
                                                     FROM `".$self -> {"settings"} -> {"userdata"} -> {"acyears"}."` AS `y`,
                                                          `".$self -> {"settings"} -> {"userdata"} -> {"courses"}."` AS `c`,
                                                          `".$self -> {"settings"} -> {"userdata"} -> {"groups"}."` AS `g`,
                                                          `".$self -> {"settings"} -> {"userdata"} -> {"user_groups"}."` AS `ug`
                                                     WHERE `ug`.`student_id` = ?
                                                     AND `ug`.`active` = ?
                                                     AND `y`.`id` = `ug`.`year_id`
                                                     AND `g`.`id` = `ug`.`group_id`
                                                     AND `c`.`id` = `g`.`course_id`");
    $groupsh -> execute($userid, $active)
        or return $self -> self_error("Unable to execute userdata group lookup: ".$self -> {"dbh"} -> errstr);

    return $groupsh -> fetchall_arrayref({});
}


1;

#!/bin/bash

# Get the latest tag annotation out of git.
VERS=`git tag -n1 | sort -V | tail -n1 | perl -e '$tag = <STDIN>; $tag =~ s/^.*?\s\s+(.*)$/$1/; print $tag;'`

# Generate the documentation with the project number updated with the tag.
(cat supportfiles/Doxyfile; echo "PROJECT_NUMBER = \"$VERS\"") | doxygen -

#!/bin/bash
#
# Script used as bridge between Net-SNMP and any structured (memory) filesystem.
#
# Copyright (C) 2012 Fabrício Godoy <skarllot@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.
#
# Authors: Fabrício Godoy <skarllot@gmail.com>
#

readonly PROG=snmpget.sh
RETVAL=0
VERBOSE=0

# Mandatory variables
validate_vars() {
    [ $VERBOSE -eq 1 ] && echo "Validating variables..."

    if [ -z $ROOT ]; then
        [ $VERBOSE -eq 1 ] && echo "ROOT variable is not defined"
        exit 1
    fi
    if [ -z $KEY_FILE ]; then
        [ $VERBOSE -eq 1 ] && echo "KEY_FILE variable is not defined"
        exit 1
    fi
    if [ ! -r $KEY_FILE ]; then
        [ $VERBOSE -eq 1 ] && echo "$KEY_FILE file is not found"
        exit 1
    fi

    # Exit if requested OID don't belong to this script
    if [ ! $(echo "$OID" | grep "^$ROOT" | wc -l) -eq 1 ]; then
        [ $VERBOSE -eq 1 ] && echo "The requested OID \"$OID\" is invalid"
        exit 1
    fi
}

key_load() {
    [ $VERBOSE -eq 1 ] && echo "Loading KEY..."

    KEY_CONTENT=$(cat $KEY_FILE)
    KEYS_COUNT=$(echo "$KEY_CONTENT" | wc -l)
    # All single instance keys
    KEY_CONTENT_SI=$(echo "$KEY_CONTENT" | grep -v "\$LNODE")
    # All multiple instance keys
    KEY_CONTENT_MI=$(echo "$KEY_CONTENT" | grep "\$LNODE")

    # TREE var building
    TREE=${OID//${ROOT}/}
    [ "${TREE:0:1}" == "." ] && TREE=${TREE:1}

    # Last node and Key node
    # Eg: TREE=1.2.3.4.5 -> KNODE=1.2.3.4 and LNODE=5
    # LNODE var is reserved to multiple instances key, it indicates intance number.
    LNODE=$(echo $TREE | awk -F. '{print $NF}')
    KNODE=$(echo $TREE | awk -F. '{out=$1; for(i=2;i<NF;i++) \
    {out=out"."$i}; print out}')

    # Is a single instance?
    COUNT=$(echo "$KEY_CONTENT_SI" | grep "^$TREE\W" | wc -l)
    KEY=""

    if [ $COUNT -eq 1 ]; then   # Single instance
        KEY=$(echo "$KEY_CONTENT_SI" | grep "^$TREE\W")
        LNODE=""
    else    # Multiple instance
        COUNT=$(echo "$KEY_CONTENT_MI" | grep "^$KNODE\W" | wc -l)

        if [ $COUNT -eq 1 ]; then   # $TREE has $LNODE part
            KEY=$(echo "$KEY_CONTENT_MI" | grep "^$KNODE\W")
        else    # $LNODE part of $TREE is missing
            COUNT=$(echo "$KEY_CONTENT_MI" | grep "^$TREE\W" | wc -l)

            if [ $COUNT -eq 1 ]; then
                KEY=$(echo "$KEY_CONTENT_MI" | grep "^$TREE\W")
                KNODE=$TREE
                LNODE=""
            else    # Requested key is not found
                [ $VERBOSE -eq 1 ] && echo "The key \"$TREE\" is invalid"
            fi
        fi
    fi

    # Get line number where $KEY is found
    LINENUM=$(echo "$KEY_CONTENT" | grep -n "$KEY" | awk -F: '{print $1}')
}


# GET request
get() {
    [ $VERBOSE -eq 1 ] && echo "GET response:"
    if [ -z "$KEY" ]; then
        [ $VERBOSE -eq 1 ] && echo "No key defined"
        exit 1
    fi

    FILENAME=$(eval echo $(echo $KEY | awk '{print $3}'))
    if [ ! -f $FILENAME ]; then
        [ $VERBOSE -eq 1 ] && echo "The file \"$FILENAME\" is not found"
        exit 1
    fi

    echo "${ROOT}.${TREE}"
    echo $KEY | awk '{print $2}'
    cat "$FILENAME"

    return 0
}

# GETNEXT request
getnext() {
    [ $VERBOSE -eq 1 ] && echo "GETNEXT response:"

    if [ -z "$KEY" ]; then
        # No key beside ROOT, then pick the first one
        KEY=$(echo "$KEY_CONTENT" | head -n 1)
    else
        # $LNODE keyword indicates that a property
        # has multiple instances

        CHKNEXT=0
        # Has "$LNODE" keyword?
        COUNT=$(echo "$KEY" | grep "\$LNODE" | wc -l)

        if [ $COUNT -eq 0 ]; then
            # No "$LNODE" keyword, then get next line
            LINENUM=$(( $LINENUM + 1 ))
            LNODE=0
            CHKNEXT=1
        else
            if [ -z "$LNODE" ]; then
                # If no $LNODE defined, set to 1
                LNODE=1
            else
                # Set to next instance
                LNODE=$(( $LNODE + 1 ))
            fi

            FILENAME=$(eval echo $(echo $KEY | awk '{print $3}'))

            if [ ! -f $FILENAME ]; then
                # Instance do not exist, then get next key
                LINENUM=$(( $LINENUM + 1 ))
                LNODE=0
                CHKNEXT=1
            fi
        fi

        if [ $LINENUM -gt $KEYS_COUNT ]; then
            [ $VERBOSE -eq 1 ] && echo "Last key reached, exit"
            exit 1
        fi

        # Need to check next key?
        if [ $CHKNEXT -eq 1 ]; then
            RPT=1
            while [ $RPT -eq 1 ]; do
                RPT=0

                # Get line from number
                KEY=$(echo "$KEY_CONTENT" | head -n $LINENUM | tail -n 1)
                COUNT=$(echo "$KEY" | grep "\$LNODE" | wc -l)

                # Next key is multiple instance?
                if [ ! $COUNT -eq 0 ]; then
                    LNODE=$(( $LNODE + 1 ))
                    FILENAME=$(eval echo $(echo $KEY | awk '{print $3}'))

                    if [ ! -f $FILENAME ]; then
                        # Instance do not exist, then get next key
                        LINENUM=$(( $LINENUM + 1 ))
                        LNODE=0
                        RPT=1
                    fi
                fi

                if [ $LINENUM -gt $KEYS_COUNT ]; then
                    [ $VERBOSE -eq 1 ] && echo "Last key reached, exit"
                    exit 1
                fi
            done
        fi

    fi

    TREE=$(echo $KEY | awk '{print $1}')
    COUNT=$(echo "$KEY" | grep "\$LNODE" | wc -l)
    [ ! $COUNT -eq 0 ] && TREE="${TREE}.${LNODE}"
}

# Parameters parsing
ARGS=$(getopt -o "vg:n:" -l "verbose,debug" -n "$PROG" -- "$@")
[ $? -ne 0 ] && exit 1
eval set -- "$ARGS"

OPT=
OID=
while true; do
    case "$1" in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -g|-n)
            if [ ! -z $OPT ]; then
                echo "The parameters \"-g\" and \"-n\" cannot be defined both"
                OPT="ERROR"
                break
            fi
            OPT=$1
            OID=$2
            shift 2
            ;;
        --debug)
            set -x
            ;;
        --)
            shift
            break
            ;;
    esac
done

case "$OPT" in
    -n)
        validate_vars
        key_load
        getnext
        get
        RETVAL=$?
        ;;
    -g)
        validate_vars
        key_load
        get
        RETVAL=$?
        ;;
    *)
        echo "Usage: $0 [ --verbose ] [ {-g|-n} <OID> ]"
        RETVAL=1
esac

exit $RETVAL

# vim: set ts=4 sw=4 et

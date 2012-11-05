#!/bin/bash

[ ! `echo "$2" | grep "^$ROOT" | wc -l` -eq 1 ] && exit 1
[ "$1" != "-g" ] && [ "$1" != "-n" ] && exit 1

TREE=`echo "$2" | sed -e "s/$ROOT//"`

if [ "${TREE:0:1}" == "." ]; then
   TREE=${TREE:1}
fi

# Last node and Key node
LNODE=`echo $TREE | awk -F. "{print \\$NF}"`
KNODE=`echo $TREE | awk -F. "{out=\\$1; for(i=2;i<NF;i++){out=out\".\"\\$i}; print out}"`

echo "TREE: $TREE"
echo "LNODE: $LNODE"
echo "KNODE: $KNODE"
echo ""

COUNT=`cat $KEY_FILE | grep "^$TREE\W" | grep -v "\\$LNODE"| wc -l`
KEY=""

if [ $COUNT -eq 1 ]; then
   KEY=`cat $KEY_FILE | grep "^$TREE\W" | grep -v "\\$LNODE"`
   LNODE=""
else
   COUNT=`cat $KEY_FILE | grep "^$KNODE\W" | grep "\\$LNODE" | wc -l`

   if [ $COUNT -eq 1 ]; then
      KEY=`cat $KEY_FILE | grep "^$KNODE\W" | grep "\\$LNODE"`
   else  # LNODE is missing!
      COUNT=`cat $KEY_FILE | grep "^$TREE\W" | grep "\\$LNODE" | wc -l`

      if [ $COUNT -eq 1 ]; then
         KEY=`cat $KEY_FILE | grep "^$TREE\W" | grep "\\$LNODE"`
         KNODE=$TREE
         LNODE=""
      fi
   fi
fi

LINENUM=`cat $KEY_FILE | grep -n "$KEY" | awk -F: "{print \\$1}"`

# === SNMP NEXT ===

if [ "$1" == "-n" ]; then
   if [ -z "$KEY" ]; then
      KEY=`cat $KEY_FILE | head -n 1`
   else
      CHKNEXT=0
      COUNT=`echo "$KEY" | grep "\\$LNODE" | wc -l`

      if [ $COUNT -eq 0 ]; then
         LINENUM=$(( $LINENUM + 1 ))
         LNODE=0
         CHKNEXT=1
      else
         [ -z "$LNODE" ] && LNODE=0

         LNODE=$(( $LNODE + 1 ))
         FILENAME=$(eval echo `echo $KEY | awk "{print \\$3}"`)

         if [ ! -f $FILENAME ]; then
            LINENUM=$(( $LINENUM + 1 ))
            LNODE=0
            CHKNEXT=1
         fi
      fi

      if [ $CHKNEXT -eq 1 ]; then
         RPT=1
         while [ $RPT -eq 1 ]; do
            RPT=0

            # Get line from number
            KEY=`cat $KEY_FILE | head -n $LINENUM | tail -n 1`
            COUNT=`echo "$KEY" | grep "\\$LNODE" | wc -l`

            if [ ! $COUNT -eq 0 ]; then
               LNODE=$(( $LNODE + 1 ))
               FILENAME=$(eval echo `echo $KEY | awk "{print \\$3}"`)

               if [ ! -f $FILENAME ]; then
                  LINENUM=$(( $LINENUM + 1 ))
                  LNODE=0
                  RPT=1
               fi
            fi
         done
      fi

   fi

   TREE=`echo $KEY | awk "{print \\$1}"`
   COUNT=`echo "$KEY" | grep "\\$LNODE" | wc -l`
   [ ! $COUNT -eq 0 ] && TREE="${TREE}.${LNODE}"
fi

# === SNMP GET ===

[ -z "$KEY" ] && exit 1

FILENAME=$(eval echo `echo $KEY | awk "{print \\$3}"`)
[ ! -f $FILENAME ] && exit 1

echo "${ROOT}.${TREE}"
echo "`echo $KEY | awk "{print \\$2}"`"
cat "$FILENAME"

echo ""
echo $KEY


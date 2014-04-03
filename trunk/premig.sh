#!/bin/bash
#~ Wininsis to valid MARC txt for yaz-marcdump tool
#~ * AUTHOR:
	#~ 2011 (c) Pablo A. Bianchi
	#~ http://www.pabloabianchi.com.ar/
#~ @TODO: (look @TODOs all over source code)
	#~ //FIX when more than two TABs on a line?
	#~ Add option to start directly from a txt (like yaz-marcdump ones, to process ISO2709 files).
	#~ Put everything in functions!
	#~ Read with CDS/Isis Linux tool id2i instead o openisis!
	#~ Read CDS/Isis files with http://search.cpan.org/dist/Biblio-Isis/lib/Biblio/Isis.pm
	#~ Validate if database name is all in same case (necessary for openisis)
	#~ Add a \n at the end of output so rec2marc process the last record
	#~ Create statistics of what it changes (autocorrections)
	#~ //Create on a DIFFERENT script a VALIDATOR...
	#~ use only ONE var "temp", create a function "movetemps()"
	#~ Remove generated "DBNAME.OXI"
	#~ Append to log the table
		#~ log to file when [err3] are for eg <1% or >99% of cases (parameter)
	#~ clean and separate logs (repots/errors/warnings)
	#~ WARNING: In Isis world is possible to use a tag>999, like Catalis use 1106
	#~ Clean regexs using sed -E
	#~ Use getopts bash builtin command: http://wiki.bash-hackers.org/howto/getopts_tutorial
	#~ added some quoting to variables, to take into account the possibility of filenames with spaces?
	#~ Log errors to stderr: cho "DEBUG: current i=$i" >&2
	#~ Add # trap ctrl-c and call ctrl_c() \ntrap ctrl_c INT
#~ 
#~ * REFERENCES
#~ err1 = Data without valid subfield.	For eg.: ^Schawn	to	^1[err1]Schawn
#~ err2 = Data out of subfields on a field with subfields.	For eg.: banana^aTomato	to	^1[err2]banana^aTomato
#~ err3 = Fields that sometimes have sf and sometimes no.	For eg.: 10	0521369800	to	10	^1[err3]0521369800	(if other OCC have subfields)
#~ 
#~ * NOTES
#~ pcregrep - grep utility that uses perl 5 compatible regexes.	#~ prep () { perl -nle 'print if '"$1"';' $2 }

function debuger {
	echo "---------------------------------"
	cat $tempA | grep -e ^98 -e ^28 -e ^85 -e ^913 -e 3[^0-9] | grep -A 7 AIG00001977 $tempA ###
	echo "---"
	cat $tempA | grep -e ^98 -e ^28 -e ^85 -e ^913 -e 3[^0-9] | grep -A 20 AIG00004025 $tempA ###
}

function removeTempFiles {
	# Final: Removing temps files
	rm --force $tempA $tempB;
	sedTempFiles=`ls -1 | grep -P "^sed......$" | wc -l`;	# ToDo: chmod 777 sed* && rm sed*
	if [ $sedTempFiles -gt 0 ]; then
		echo >&2 "Warning: Some sed temporary files had been created...";
	fi
}


echo " *** Wininsis to valid MARC line txt tool *** ";
if [ $# -ne 1 ]; then
	echo >&2 -e "Usage, for BASE.MST and BASE.XRF: $0 BASE ";	# MST have the data, XRF the position of each record.
	exit 1;
fi

#CONFIG:
input="$1";	# Database name if openisis input (For eg "BIBUN")
output=$1"-";
finalOutput=$1".txt";
finalMrcOutput=$1".mrc";
errorsFile=$1".log";
 fromCoding="CP850";	# CP850 by default. Try utrac to detect encoding, might be CP437 or latin1. wxis uses CP1252 (windows-1252)
toCoding="UTF8";
tempA="tempA";
tempB="tempB";
mode="openisis";	# Prepare to different outputs Modes: "openisis" (to rec2marc.pl), "yaz-marcdump" (to yaz-marcdump), "marcedit" (MRK).
rec2marcScript="rec2marc-PAB.pl";
errorSubfield=9;	#  (Edit: $9, "local"..) Subfield $1 is recommended. Only used on 880 and 886, very rarely: http://www.loc.gov/marc/bibliographic/ecbdlist.html

rm --force "$finalOutput";

# ATENTION: Openisis CAN'T read files with extensions in lowercase!
if [ ! -f ./$input.MST ] || [ ! -f ./$input.XRF ] || [ ! -x ./openisis ]; then
	echo >&2 "Error: Database or openisis missing. Check case.";
	exit 1;
fi

echo "ERRORS LOG FILE" > $errorsFile;

echo "INPUT: $input";
echo "OUTPUT: $finalOutput";
echo "ERRORS: $errorsFile";
echo;

#~ echo "Removing all EOLs...";
#~ perl -i -pne 's/\R//g;' $input

echo "Extracting from CDS/Isis database...";
./openisis -db $input > $tempA;
#cp $tempA $input".TXT";
rm --force "$input.OXI" "$input.oxi";
rm --force "$input.PTR" "$input.ptr";

echo "Converting coding from $fromCoding to $toCoding...";
hash yaz-iconv 2>&- || { echo >&2 "I require «yaz-iconv» but yaz package it's not installed. Aborting."; exit 1; }
`yaz-iconv -f $fromCoding -t $toCoding $tempA > $tempB`;


sed -i 's/\t//2g' $tempB;	# Removes (removes?) tabs except the first one
twoTabs=`cat $tempB | sed "s/^[0-9]\+\t\(.*\)$/\1/g" | grep -P "\t" | wc -l`;	# More than two TABs on a line?
if [ $twoTabs -gt 0 ]; then
	echo >&2 "Error: More than two TABs on a line...";
	exit 1;
fi

 #tempB="entrada";	# TEST only, using previously output as an input
echo "Removing dirty characters...";
sed -i 's/^0\t//g' $tempB;	# @TODO: remove it correctly while removing dirty EOLs
sed -i 's/\\//g' $tempB;	# Removes "\" character (problematic with sed (sed bug?)
sed -i "s/\t//2g" $tempB;	# second or more case, live the first (from http://www.grymoire.com/Unix/Sed.html )

echo "Removing dirty EOLs...";	# Remove completly CRLF
hash perl 2>&- || { echo >&2 "I require «perl» but package it's not installed. Aborting."; exit 1; }
#@TODO: Add counter and send to error log && Check if Perl installed first
perl -p -e 's/\r\n//' < $tempB > $tempA;

# AUTOCORRECT
echo "Trimming all subfields...";	# BEFORE Removing empty subfields because this clean the subfield
 #echo -e "\nTrim all subfields" >> $errorsFile && cat $tempA| grep -P '\^.\^' >> $errorsFile
sed -i 's/\t \+/\t/g' $tempA	#PRE: One or more spaces AFTER TAB
sed -i 's/ \+\^/\^/g' $tempA	#IN: Spaces BEFORE ^
sed -i 's/\(\^.\) \+/\1/g' $tempA	#IN: Spaces between ^a and DATA (^a   Data)
sed -i 's/ \+$//g' $tempA	#POST: Spaces before EOL

echo "Removing empty subfields (~"`cat $tempA| grep -P '\^.\^' | wc -l`")...";	# @WARNING: Ask if it should be empty subfields...
echo -e "\n=== Empty subfields" >> $errorsFile && cat $tempA| grep -P '\^.\^' >> $errorsFile
sed -i 's/\^\+/^/g' $tempA	# ^^^ to ^  Two or more ^s to only one
sed -i 's/\^. *\^/^/g' $tempA	# ^.^aSomething  to  ^aSomething (where . is ANY character)
sed -i 's/\^. *\^/^/g' $tempA	# Again...
 #sed -i 's/\^. \+\^/^/g' $tempA	# Subfields with space(s) only: "^a   ^b"  to  "^b"	# Duplicated action: Eliminated
sed -i 's/\^.\{1\}$//g' $tempA	# ^.\n
 ##sed -i "s/ \{2,\}/ /g" $tempA # Two or more consecutive spaces

# AFTER removing empty subfields: Cleaning subfields could led on an empty field
echo "Removing empty fields ("`cat $tempA| grep -P '^[0-9]+\t$' | wc -l`")...";	# @WARNING: Ask if it should be empty fields...
echo -e "\n=== Empty fields" >> $errorsFile && cat $tempA| grep -P '^[0-9]+\t$' >> $errorsFile	#  @OBS: It seems -P change UTF-8 chars like Ñ...
sed -i '/^[0-9]\+\t$/d' $tempA

echo "Moving invalid subfields ("`cat $tempA | grep -P '\^[^[:lower:]]' | wc -l`") to subfield $errorSubfield with preffix [err1] (^Alicia)...";	# Hypothesis: No "^^"s any more.
echo -e "\n=== Invalid subfields [err1]" >> $errorsFile && cat $tempA | grep -P '\^[^[:lower:]]' >> $errorsFile
sed -i "s/\^\([^[:lower:]]\)/^$errorSubfield[err1]\1/g" $tempA	# Convert ^Schaum  to  ^1[err1]Schaum
 #cat $tempA | grep -P '\^[^[:lower:]]\[err1\]' --color

echo "Moving invalid subfields ("`cat $tempA | grep -P '\t[^\^].+\^' | wc -l`") to subfield $errorSubfield with preffix [err2] (Alicia^bBob)...";
echo -e "\n=== Invalid subfields [err2]" >> $errorsFile && cat $tempA | cat $tempA | grep -P '\t[^\^].+\^' >> $errorsFile
sed -i "s/\t\([^\^].*\^\)/\t^$errorSubfield[err2]\1/1" $tempA;	# Convert banana^aTomato  to  ^1[err2]banana^aTomato

ssTotal=`cat $tempA | grep -oP '[^ ] {2,}[^ ]' | wc -l`;	# -o outputs every occurrence on a new line
ssTwo=`cat $tempA | grep -P '[^ ] {2}[^ ]' | wc -l`;
ssThree=`cat $tempA | grep -P '[^ ] {3}[^ ]' | wc -l`;
ssFour=`cat $tempA | grep -P '[^ ] {4}[^ ]' | wc -l`;
ssMoreThanFour=`cat $tempA | grep -P '[^ ] {5,}[^ ]' | wc -l`;
echo "Removing two or more consecutive spaces (Total:~$ssTotal 2:$ssTwo 3:$ssThree 4:$ssFour >4:$ssMoreThanFour)..."; # If there is more than one match on a line, sum will not match Total
echo -e "\n=== Two or more consecutive spaces" >> $errorsFile && cat $tempA | grep -P ' {2,}' >> $errorsFile
sed -i "s/ \{2,\}/ /g" $tempA
 #cat $tempA | grep -P '[^ ] {2,}[^ ]' --color

echo "Fields with subfield in some cases and without in others:";
echo "Search them in Winsis using something like:  ? p(v123) AND (NOT(v123:'^'))  or similar:  ?p(v123) AND (a(v123^a))";
echo -e " Field \t W-SF \t WO-SF \t Prop. (%) ";
join \
 <(cat $tempA | grep -P "\^"| grep -oP "^[0-9]{1,3}" | sort -n | uniq -c | sort -k2 | awk '{ print $2 "\t" $1}') \
 <(cat $tempA | grep -vP "\^"| grep -oP "^[0-9]{1,3}" | sort -n | uniq -c | sort -k2 | awk '{ print $2 "\t" $1}') | \
 sort -n -k1 | \
 awk '{ printf "%s\t%s\t%s\t%2.2f \n",  $1, $2, $3, ($2)/($2+$3)*100 }';
echo -e " W-SF:\tFields with subfields";
echo -e " WO-SF:\tFields without subfields";
echo -e " Prop:\tProportion of fields with subfields in relation to total";

fields=($(join <(cat $tempA | grep -P "\^"| grep -oP "^[0-9]{1,3}" | sort -n | uniq | sort) <(cat $tempA | grep -vP "\^"| grep -oP "^[0-9]{1,3}" | sort -n | uniq | sort) | sort -n));	# The two parentheses are necessary
echo "Adding leading subfield $errorSubfield with preffix [err3] to fields that sometimes have sf and sometimes no (${#fields[@]})..."
echo -n "  Field: ";
echo -e "\n=== Fields that sometimes have sf and sometimes no [err3]" >> $errorsFile && \
	echo "${fields[@]}" >> $errorsFile
for field in "${fields[@]}"
do
	#echo -e "\n=== Invalid subfields [err2]" >> $errorsFile && cat $tempA | cat $tempA |grep -P '\t[^\^].+\^' >> $errorsFile
	echo -n "$field ";
	sed -i "s/^\($field\t\)\([^\^]\)/\1^$errorSubfield[err3]\2/1" $tempA;
done
echo -ne "\n";

# @BUG @TODO: El encontrador de errores los tira en ^1[errN], eso puede pasar en 
#	campos sin leading subfield, convieriendolo en "a veces tiene a veces no".

leadingSubfield="a";
echo "Adding leading subfield  «$leadingSubfield» to fields without subfields, never ("`cat $tempA | grep -vP "\t\^"| grep -oP "^[0-9]{1,3}" | sort -n | uniq | wc -l`")..."
echo -e "\n=== Fields without subfields, never" >> $errorsFile && cat $tempA | grep -vP "\t\^"| grep -oP "^[0-9]{1,3}" | sort -n | uniq >> $errorsFile
sed -i "s@\t\([^\^]\)@\t^$leadingSubfield\1@1" $tempA;	# BUG: Seting leading default subfield to ALL subfields, even the one that sometimes has and sometimes no ([err3])..

#~ fieldsWOSnever=($(cat $tempA | grep -vP "\t\^"| grep -oP "^[0-9]{1,3}" | sort -n | uniq));	# The two parentheses are necessary


# /AUTOCORRECT

echo 'Change dollar signs,"$" to "{dollar}"...';
sed -i "s/\\$ */{dollar}/g" $tempA;	#Also sanitizing a little bit...

cp $tempA $tempB	# REMOVE AFTER ALL WITH "$temp"!

# CHANGES (not cleaning)
offset=91;	# Moving to 91x
timesUsedOffsetField=`cat $tempB | grep -P "^$offset[0-9]\t.+$" | wc -l`;
echo "Moving data from control-tags to data-tags using $offset|x as offset (previously used $timesUsedOffsetField times)...";
if [ $timesUsedOffsetField -gt 0 ]; then
	echo >&2 "Error: Tring to move 00x fields (control) to used fields (on $offset|x)";	# We cant move to fields already used.
	removeTempFiles
	exit 1;
fi
sed -i "s/^\([0-9]\t.*\)$/$offset\1/g" $tempB;

		# delete all CONSECUTIVE blank lines from file except the first; also
		# deletes all blank lines from top and end of file (emulates "cat -s")
		#sed '/./,/^$/!d'          # method 1, allows 0 blanks at top, 1 at EOF
		#sed '/^$/N;/\n$/D'        # method 2, allows 1 blank at top, 0 at EOF
	#`cat -s < $tempA > $tempB`;	#FIRST, if more than one blank line between records... @TODO: use mv to keep using sed -i with same names.. Use SED instead
	sed -i '1s/^$//p;/./,/^$/!d' $tempB;	# Emulates cat -s. From: http://sed.sourceforge.net/local/docs/emulating_unix.txt

case "$mode" in
"openisis")	# No leader, nor reformat from TAB to SPACES
	echo "Openisis-rec2marc mode:" # rec2marc: create ldr, convert ^ to $
	echo "LDR and conversion to MRC, made by $rec2marcScript"
	sed -i 's/\t/\t  /1' $tempB	# data fields (add two blank indicators)
	echo "Removing first line...";	# AFTER "Add fixed leader", to ad leader to first line also
	sed -i 1d $tempB;
	echo -ne "\n" >> $tempB;	# A \n at the end so rec2marc read the last record.
	cp $tempB $finalOutput;
	if [ -x ./$rec2marcScript ]; then
		echo "Converting TXT to MRC MARC file ($rec2marcScript)...";
		./$rec2marcScript < $finalOutput > $finalMrcOutput;
		echo "Done.";
	else
		echo >&2 "rec2marc not found. Now, try ./rec2marc-PAB.pl < $finalOutput > $finalMrcOutput";
	fi
	;;
"yaz-marcdump")	echo "YAZ-marcdump mode:"
	# OBS: rec2marc.pl already do this
	circumflex="^";
	dollarsign="$";
	echo "Change subfield separators from $circumflex to $dollarsign...";
	sed -i "s/\\$circumflex/$dollarsign/g" $tempB;

	# yaz-marcdump -f UTF8 -t UTF8 -i line -o line FILE autogenerate his fixed LDR: NO! Is a constant leader too..
	leader="00000cam a22003334a 4500";	# See migration table...
	echo "Add fixed leader to all records ($leader)"...;
	sed -i "s/^$/\n$leader/" $tempB;

	# CONVERT FROM OPENISIS TO YAZ-MARCDUMP LINE SYNTAX
	echo 'Converting from "openisis" to "yaz-marc line" syntax...';
	sed -i 's/^\([0-9]\t.*\)$/00\1/1' $tempB	# Leading zeros: 7 to 007 (shouldn't do nothing...)
	sed -i 's/^\([0-9][0-9]\t.*\)$/0\1/1' $tempB	# Leading zeros: 69 to 069

	#sed -i 's/\t/ /1' $tempB	# control fields (no hay)
	sed -i 's/\t/   /1' $tempB	# data fields (add wo blank indicators)
	sed -i 's/\(\$[a-z0-9]\)/ \1 /g' $tempB	# spaces left and right the subfield header
	;;
"marcedit")	echo "MarcEdit (MRK) mode:"
	echo "Not implemented yet!"
	;;
"i")	echo "«i» mode (like Isis id2i tool):"
	echo "Not implemented yet!"
	;;
*) echo "Please set output mode on  mode  var"
	exit 1;
	;;
esac

removeTempFiles

echo "Generated files:";
echo " - $finalOutput";
echo " - $errorsFile";
if [ -f ./$finalMrcOutput ]; then
	echo " - $finalMrcOutput";
fi
echo "Done. :)";
exit 0;

#-----------------------------------------------------------------------

#shopt -s nocaseglob;	# Make Bash case-insensitive
#shopt -u nocaseglob;	# Make bash case-sensitive again

# print only lines which match regular expression (emulates "grep")
 sed -n '/regexp/p'           # method 1
 sed '/regexp/!d'             # method 2

# print only lines which do NOT match regexp (emulates "grep -v")
 sed -n '/regexp/!p'          # method 1, corresponds to above
 sed '/regexp/d'              # method 2, simpler syntax

The expand filter converts tabs to spaces. It is often used in a pipe.

# VALIDATIONS
1 ==? `cat $tempA | grep -vP '^[0-9]{1,3}\t.+$' | uniq | wc -l`


---
in_array() {
    local hay needle=$1
    shift
    for hay; do
        [[ $hay == $needle ]] && return 0
    done
    return 1
}
---
#BIBUN-statistics.log
	#campos usados
	#campos usados sin subcampos en NINGUN caso ($a como leading subfield)
	#campos usados con subcampos en ALGUNA ocurrenciA del mismo (ej ISBN :S)


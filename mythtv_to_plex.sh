#!/bin/bash
# Justin Alcorn justin@jalcorn.net
# Based on original script by:
# Ian Thiele
# icthiele@gmail.com
#
# Uses mythcommflag, ffmpeg, and mkvmerge to cut commercials out of h.264 encoded mpg files #
# MPEG2 Recordings from the HDHomeRun use mythtranscode to cut commercials
# MPEG4 Recordings from the HDPVR have to use ffmpeg to cut the commercials.
#
# N.B. There is a section of my personalized processing. You should review and modify or delete this section.
#    Look for "PERSONALIZED PROCESSING"
#
# I like underscores in my filenames.  Plex does OK with them in TV Shows libraries. If you prefer 
#     spaces, then change this
separator="_"
# Where to put the log file
logdir="/home/mythtv/save"
# TV Show Library, for archiving TV Shows
tvlib="/mnt/disk/share/tv"
# Home Video Llibrary, where shows not in the TV Show library will be stored
reclib="/mnt/disk/share/recordings"
# Where per-show thumbnail images are found
thumbdir="/home/mythtv"

# Options: mp4,mkv
finalext="mp4"
# Options: any preset, common are Universal, Normal, High Profile
#   HandBrake v >1.0 - better presets. 
# The quality I like.  
quality=' --align-av  --audio=1,1 --aencoder=aac,copy --mixdown=stereo,5point1  -e x264 --encoder-preset=fast --encoder-profile=main --encoder-level=4.1 -q 20 --two-pass --subtitle-lang-list eng --all-subtitles  -l 720 -F '
# But I actually transcode later, just copy for now
quality="COPY"
# MySQL Config file with username and password (DON'T PASS THEM ON COMMAND LINE)
mysqlinfo="/home/mythtv/.mythtv/mysql.cnf"

if [ ! -t 1 ];then

	logfile=${logdir}/$$.log
	# Close STDOUT file descriptor
	exec 1<&-
	# Close STDERR FD
	exec 2<&-

	# Open STDOUT as $LOG_FILE file for read and write.
	exec 1<>$logfile

	# Redirect STDERR to STDOUT
	exec 2>&1
fi

if [ -z ${1} ];then
	echo "Usage: $0 <fullfilepath>"
	exit 1
fi


if [ -n "${2}" ]; then
	INPUTFILE="${1}/${2}"
else
	INPUTFILE=${1}
fi

workdir="/tmp/$$"
mkdir -p ${workdir}

if [ ! -f "$INPUTFILE" ]; then
    echo "file \"${INPUTFILE}\" doesn't exist, aborting."
    exit 1
fi

#let's make sure we have a sane environment
if [ -z "`which ffmpeg`" ]; then
    echo "FFMpeg not present in the path. Adjust environment or install ffmpeg"
    exit 1
fi
######
# I should check for all the other executables here.....
#
########
if [ ! -x "/usr/bin/HandBrakeCLI" ]; then
    echo "Can't find HandBrakeCLI. Adjust settings"
    exit 1
fi
R=$(/usr/bin/HandBrakeCLI -z 2>&1 | grep "Very Fast 1080p30") 
if [ $? -eq 1 ];
then
    echo "Using a very old Handbrake, will limit to Legacy presets"
    echo "Suggest you use official HandBrake from http://handbrake.fr"
    #quality="Universal"
    oldversion=1
else
    oldversion=0
fi
if [ -z "`which mythutil`" ]; then
    echo "mythutil not present in the path. Adjust environment or install mythutil"
    exit 1
fi
if [ -z "`which mythtranscode`" ]; then
    echo "mythtranscode not present in the path. Adjust environment or install mythtranscode"
    exit 1
fi

#connect to DB
mysqlconnect="mysql --defaults-extra-file=${mysqlinfo} -N "
export mysqlconnect
if echo "SELECT 1 from plexnames LIMIT 1;" | $mysqlconnect > /dev/null 2>&1;  then echo "Database Setup looks OK"; else echo "Cannot see plexnames table, is MySQL Set up correctly?"; exit 1;fi

RECDIR=`dirname $INPUTFILE`
FILENAME=`basename $INPUTFILE`
TEMPNAME=`basename $INPUTFILE .ts`

#deteremine directory and filename
RECDIR=`dirname $INPUTFILE`
BASENAME=`basename $INPUTFILE`
if [ "$TEMPNAME" != "$FILENAME" ];then
	newbname=`basename $BASENAME .ts`
else
	newbname=`basename $BASENAME .mpg`
fi
WORKFILEBASE="${workdir}/${newbname}"

#determine chanid and starttime from recorded table
chanid=`echo "select chanid from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
starttime=`echo "select starttime from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
if [ -z "$chanid" -o -z "$starttime" ];then 
	echo "Info not found for select chanid from recorded where basename=\"$BASENAME\""
	exit;
fi

if [ -z "$chanid" ] || [ -z "$starttime" ]
then
    echo "Recording not found in MythTV database, script aborted."
    exit 1
fi

echo '**************************************************************'
echo `date`
echo "CHANID $chanid STARTTIME $starttime"
title=`echo "select title from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
subtitle=`echo "select subtitle from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
programid=`echo "select programid from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
######
#
# For titles that need specific names in Ples, store the updates in mythconverg database in a table:
#+-----------+--------------+------+-----+---------+----------------+
#| Field     | Type         | Null | Key | Default | Extra          |
#+-----------+--------------+------+-----+---------+----------------+
#| id        | int(11)      | NO   | PRI | NULL    | auto_increment |
#| title     | varchar(255) | NO   |     | NULL    |                |
#| plextitle | varchar(255) | NO   |     | NULL    |                |
#+-----------+--------------+------+-----+---------+----------------+
######
plextitle=`echo "select plextitle from plexnames where title=\"$title\";" | $mysqlconnect`
if [ -z "$plextitle" ];then
	plextitle=`echo $title |  sed -e "s/ /${separator}/g" | sed -e "s/[,\/\"\'\.()]//g"`
fi
season=`echo "select season from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
episode=`echo "select episode from recorded where basename=\"$BASENAME\";" | $mysqlconnect`

info=`echo "select title, subtitle from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
echo "Basename = $BASENAME"
echo "Season $season Episode $episode"
echo $info
echo '**************************************************************'

if [ $episode -gt 0 ]
then
	s=`printf %02d $season`
	e=`printf %02d $episode`
	se="S${s}E${e}."
else
	se=""
fi

if [ -n "$subtitle" ];then
	t=`echo $subtitle |  sed -e "s/ /${separator}/g" | sed -e "s/[,;\/\"\'\.()]//g"`
	t="${t}."
else 
	t=""
fi
######
# Plex TV shows are in directory structure.  If a MythTV recording does NOT match a TV title in the TV library
#     then the output is put into a "Home Videos" library with the date and time as part of the Filename.
#
#     This is used for shows that are watched and then deleted in Plex, rather than watched and archived.
# For some reason, the file names in the Videos library need to have spaces to keep them separated in Plex
#
# ToDo: Automatically create directories in the TV Shows Library?  Maybe.
############################################
echo "Checking for Movie or Directory ${tvlib}/${plextitle}"
if [[ $programid =~ ^MV ]];then
	airdate=`echo "SELECT airdate FROM program WHERE programid = '${programid}';" | $mysqlconnect`
	if [ -z "$airdate" ];then
		airdate=`echo "SELECT originalairdate FROM recorded WHERE  basename=\"$BASENAME\";" | $mysqlconnect`
		mvyear=`echo $airdate | cut -d'-' -f1`
	else
		mvyear=`echo $airdate | cut -d' ' -f1`
	fi
	if [ ! -e "/mnt/disk/share/movies/${plextitle}.${mvyear}" ];then
		mkdir "/mnt/disk/share/movies/${plextitle}.${mvyear}"
	fi
	FINALFILE="/mnt/disk/share/movies/${plextitle}.${mvyear}/${plextitle}.${mvyear}.${finalext}"
elif [ -d "${tvlib}/${plextitle}" ]
then
	FINALFILE="${tvlib}/${plextitle}/${plextitle}.${se}${t}${finalext}"
	if [ -z "${se}" ];then
		echo $FINALFILE | mail -s "No Season/Episode for ${FINALFILE}" jbalcorn@gmail.com
		# Any TV Show recorded before 1000 hours UTC (before 6am ET) is assumed to be a rebroadcast from the night before.
		PREFIXDT=$(date -d "${starttime} UTC-599 minutes" "+%Y-%m-%d")
		FINALFILE="${tvlib}/${plextitle}/${plextitle}.${PREFIXDT}.${finalext}"
	fi
else
	# For sports, us the UTC date. 
	# If the recording starts after 23:30 UTC, Assume the game starts at the top of the hour, which means the 
	#    Official game date is tomorrow
	echo "Sporting event. Checking Start date of ${starttime}"
	min=$(TZ=UTC date -d "${starttime} UTC" "+%M")
	if [[ $min > 30 ]];then 
		PREFIXDT=$(TZ=UTC date -d "${starttime} UTC +30 minutes" "+%Y-%m-%d")
		echo "Assuming recording started before event"
	else
		PREFIXDT=$(TZ=UTC date -d "${starttime} UTC" "+%Y-%m-%d")
	fi
	echo "Using Start Date of ${PREFIXDT} for TheSportsDB"
	PREFIXTITLE=`echo $plextitle | sed -e "s/${separator}/ /g"`
	FINALFILE="${reclib}/${PREFIXTITLE} ${PREFIXDT}.${t}${finalext}"
	echo "does ${thumbdir}/${plextitle}.jpg exist?"
	if [ -e "${thumbdir}/${plextitle}.jpg" ];then
		FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
		echo "cp \"${thumbdir}/${plextitle}.jpg\" \"${FINALFILETHUMB}\""
		cp "${thumbdir}/${plextitle}.jpg" "${FINALFILETHUMB}"
		FINALFILETHUMB=`echo $FINALFILE | sed -e "s/\.${finalext}$/-fanart.jpg/"`
		echo "cp \"${thumbdir}/${plextitle}.jpg\" \"${FINALFILETHUMB}\""
		cp "${thumbdir}/${plextitle}.jpg" "${FINALFILETHUMB}"
	fi
	#quality="Very Fast 720p30"
fi

##########################
# BEGINNING OF PERSONALIZED PROCESSING. DELETE OR MODIFY THIS SECTION
#
# I want my soccer to be copied without trancoding or lowering quality, and I want Plex to use a logo rather than put
#   spoilers in the frame grabed picture for any of these games.
#
# Liverpool and Columbus Crew get their own logos, because they're my teams.
#   others get EPL and MLS logos.
#
# 2022
# WithSportScanner now working more reliably, got rid of all the logo code.  Also can use .SportScanner files to mark the OTA
#    Spanish language broadcasts in Plex.
#########################################
##
#  To enable automatic matching via theSportScanner agent in Plex:
#  Translate all team names to ones that match thesportsdb.com.  You need to pre-load this as recordings get scheduled.  
# e.g.
#+----+---------------------+----------------------+
#| id | title               | plextitle            |
#+----+---------------------+----------------------+
#| 85 | León                | Leon                 |
#| 86 | América             | CF_America           |
#| 87 | Pumas UNAM          | Pumas                |
#| 88 | Tigres_UANL         | Tigres               |
#| 89 | Estados_Unidos      | USA                  |
#| 90 | Pumas_UNAM          | Pumas                |
#| 91 | México              | Mexico               |
#| 92 | Panamá              | Panama               |
#| 93 | Atlético_San_Luis   | Atletico_de_San_Luis |
#| 94 | Alavés              | Alaves               |
#| 95 | Atletico San Luis   | Atletico_de_San_Luis |
#| 96 | Atlético de Madrid  | Ath_Madrid           |
#+----+---------------------+----------------------+

echo $t
if [[ $t =~ (.*)_at_(.*)\. ]];
then
	team1=${BASH_REMATCH[2]}
	team2=${BASH_REMATCH[1]}
fi
if [[ $t =~ (.*)_vs_(.*)\. ]];
then
	team1=${BASH_REMATCH[1]}
	team2=${BASH_REMATCH[2]}
fi
echo "$team1 $team2"
if [[ -n "$team1" && -n "$team2" ]];
then
	#
	# Because the men's and women's teams may both be "United States", start with
	#   Event and Name just to be sure
	sql="select plextitle from plexnames where title=\"${plextitle}-${team1}\";" 
	echo $sql
	team1name=`echo $sql | $mysqlconnect`
	if [ -z "$team1name" ];then
		sql="select plextitle from plexnames where title=\"${team1}\";" 
		echo $sql
		team1name=`echo $sql | $mysqlconnect`
		if [ -z "$team1name" ];then
			echo "No plexnames found for ${plextitle}-${team1}."
			team1name=$team1
		fi
	fi
	echo "Home team plexname: ${team1name}"
	sql="select plextitle from plexnames where title=\"${plextitle}-${team2}\";" 
	echo $sql
	team2name=`echo $sql | $mysqlconnect`
	if [ -z "$team2name" ];then
		sql="select plextitle from plexnames where title=\"${team2}\";" 
		echo $sql
		team2name=`echo $sql | $mysqlconnect`
		if [ -z "$team2name" ];then
			echo "No plexnames found for ${plextitle}-${team2}."
			team2name=$team2
		fi
	fi
	echo "Away team plexname: ${team2name}"
	t="${team1name}_vs_${team2name}."
fi
echo "plexname translation: ${t}"
#
# Kludgy, but it works.  I've moved to using a SportScanner.txt file to determine seasons rather
#   than season directories, so I don't have to edit this as seasons change.  I could data drive all
#   this but it seems like overkill.
#
# No more moving jpg files in as thumbnails because the thumbnail image download in the SportScanner
#   has been fixed
#
if [[ "$FINALFILE" =~ "Fútbol Premier League" ]];then
	PREFIXTITLE="English_Premier_League"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
	echo "1
(Spanish)" > "${BASEFILE}SportScanner"
elif [[ "$FINALFILE" =~ "Premier League" ]];then
	PREFIXTITLE="English_Premier_League"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
elif [[ "$FINALFILE" =~ "Fútbol UEFA Champions League" ]];then
	PREFIXTITLE="UEFA_Champions_League"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
	echo "1
(Spanish)" > "${BASEFILE}SportScanner"
elif [[ "$FINALFILE" =~ "UEFA Champions League" ]];then
	PREFIXTITLE="UEFA_Champions_League"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
	#quality="Fast 720p30"
elif [[ "$FINALFILE" =~ "Spanish Primera Division" ]];then
	PREFIXTITLE="Spanish_La_Liga"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
elif [[ "$FINALFILE"  =~ "Fútbol Mexicano Primera División" ]];
then
	PREFIXTITLE="Mexican_Primera_League"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
	echo "1
(Spanish)" > "${BASEFILE}SportScanner"
elif [[ "$FINALFILE"  =~ "FIFA Eliminatorias Copa Mundial" ]];
then
	PREFIXTITLE="FIFA_World_Cup"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/Season 2122/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
	echo "1
(Spanish)" > "${BASEFILE}SportScanner"
elif [[ "$FINALFILE" =~ "Fútbol UEFA Europa League" ]];then
	PREFIXTITLE="UEFA_Europa_League"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
	echo "1
(Spanish)" > "${BASEFILE}SportScanner"
elif [[ "$FINALFILE"  =~ "NFL " || "$FINALFILE"  =~ "Super Bowl" ]];
then
	PREFIXTITLE="NFL"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
elif [[ "$FINALFILE"  =~ "Fútbol MLS" ]];
then
	PREFIXTITLE="MLS"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
	echo "1
(Spanish)" > "${BASEFILE}SportScanner"
elif [[ "$FINALFILE"  =~ "MLS " ]];
then
	PREFIXTITLE="MLS"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
elif [[ "$FINALFILE"  =~ "NBA " ]];
then
	PREFIXTITLE="NBA"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
elif [[ "$FINALFILE"  =~ 'NHL ' ]];
then
	PREFIXTITLE="NHL"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
elif [[ "$FINALFILE"  =~ 'MLB Baseball' ]];
then
	PREFIXTITLE="MLB"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
elif [[ "$FINALFILE"  =~ 'Torneo de Francia' ]];
then
	PREFIXTITLE="Tournoi_de_France"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
	echo "1
(Spanish)" > "${BASEFILE}SportScanner"
elif [[ "$FINALFILE"  =~ 'Fútbol CONMEBOL Libertadores' ]];
then
	PREFIXTITLE="Copa_Libertadores"
	BASEFILE="/mnt/disk/share/sports/${PREFIXTITLE}/${PREFIXTITLE}.${PREFIXDT}.${t}"
	FINALFILE="${BASEFILE}${finalext}"
	echo "1
(Spanish)" > "${BASEFILE}SportScanner"
else 
	searchtitle=$( echo $title |  sed -e "s/[,\/\"\'\.()]//g" )
echo $searchtitle
	if [ -d "/mnt/disk/share/sports/$searchtitle" ];
	then
		FINALFILE="/mnt/disk/share/sports/${searchtitle}/${PREFIXTITLE}.${PREFIXDT}.${t}${finalext}"
	fi
fi

echo "Final File will be ${FINALFILE}"
#################
# End of PERSONALIZED PROCESSING
#################
#lets make sure we have a cutlist before we proceed
if [ -z "`mythutil --getcutlist --chanid $chanid --starttime "$starttime" | grep Cutlist | sed 's/Cutlist: $//'`" ]; then
    echo "no cutlist found....generating new cutlist"
    mythutil --chanid $chanid --starttime "$starttime" --gencutlist #&>${logfile}
fi   

#############################
# If we still do't have a cutlist, We assume it's either commercial free or I don't care. 
# If I'm going to cut commercials, I mark the video in a different process
############################
if [ -z "`mythutil --getcutlist --chanid $chanid --starttime "$starttime" | grep Cutlist | sed 's/Cutlist: $//'`" ]; then
	echo "Still no cutlist found....Assuming Commercial Free"
	WORKFILE=${INPUTFILE}
else
	# Now we split. 
	# MPEG2 Recordings from the HDHomeRun use mythtranscode to cut commercials
	# MPEG4 Recordings from the HDPVR have to use ffmpeg to cut the commercials.
	#
	# 2021
	# We just use ffmpeg for all cutting now

	format=`mediainfo --Inform="Video;%Format%" ${INPUTFILE}`

	echo "Format = $format"
	#cutlist provides a list of frames in the format start-end,[start1-end1,....] to cut 
	# for FFMpeg, we swap this list so that it provides the ranges of video we want in the format
	#	start-end start1:end1 ....
	# For Mythtranscode, we use the Cutlist as it is. (DEPRECATED)
	CUTLIST=`mythutil --chanid $chanid --starttime "$starttime" --getcutlist | grep Cutlist | sed 's/Cutlist: //' | sed 's/-/,/g' `
	echo "CUTLIST=${CUTLIST}"

	echo "Cutting and Transcoding $format Video"
	#
	# Determine if we're keeping the even or the odd chunks
	if [[ $CUTLIST =~ ^0, ]];then
	CUTLIST=$( echo $CUTLIST | sed -e 's/^0,//' )
		AWKCMD='NR%2==1'
	else
		CUTLIST="0,${CUTLIST}"
		AWKCMD='NR%2!=1'
	fi
	WORKFILE=${WORKFILEBASE}.mp4
	CUTLIST=`echo $CUTLIST | sed 's/,/ /g'`
	echo $CUTLIST
	### Code from cutDV
	lag=4
	scope=2000
	query="select data from recordedmarkup where chanid=$chanid and starttime='$starttime' and type=33 ; "
	echo ${query}
	totaldurationms=$(echo ${query} | $mysqlconnect)

	query="select data from recordedmarkup where chanid=$chanid and starttime='$starttime' and type=34 ; "
	echo ${query}
	totalframes=$(echo ${query} | $mysqlconnect)

	#
	# Get the list of keyframes and the list of millisecond markers from the mythtv database
	KEYLIST=`for frame in $CUTLIST;do  i=$(( ${frame} - ${lag} )); j=$(( ${i} + ${scope} )); query="select mark FROM recordedseek where chanid=$chanid and starttime='$starttime' and type=33 and mark >= ${i} and mark < ${j}  order by offset limit 3 ;"; echo ${query} | $mysqlconnect 2>/dev/null; done | sed -n '1,${p;n;n}' | tr "\n" " "`
	MSLIST=`for frame in $CUTLIST;do  i=$(( ${frame} - ${lag} )); j=$(( ${i} + ${scope} )); query="select offset FROM recordedseek where chanid=$chanid and starttime='$starttime' and type=33 and mark >= ${i} and mark < ${j}  order by offset limit 3 ;"; echo ${query} | $mysqlconnect 2>/dev/null; done | sed -n '1,${p;n;n}' | tr "\n" " "`

	LASTMSLIST=$(echo ${MSLIST} | sed -e 's/.* //')
	MSLEFT=$(( ${totaldurationms} - ${LASTMSLIST} ))
	if [ $MSLEFT -gt 10000 ]
	then
		MSLIST="${MSLIST} ${totaldurationms}"
		KEYLIST="${KEYLIST} ${totalframes}"
	fi
	echo "Keyframe List: ${KEYLIST}"
	echo "Microsecond List: ${MSLIST}"

	ms2sf() {
		local s
		s=$(echo "scale=4;  $1  / 1000.0 " | bc -l )
		printf "%.4f" $s
	}

	chunkhead="out"
	chunk=0
	while [ $(echo ${MSLIST} | wc -w) -gt 1 ]
	do
		msstart=$(echo $MSLIST | awk '{print $1}')
		msend=$(echo $MSLIST | awk '{print $2}')
		msduration=$(( $msend - $msstart ))
		MSLIST=$(echo $MSLIST | awk '{$1=""}1' | awk '{$1=""}1')
		CMD="ffmpeg -fflags +genpts -flags +global_header \
		-ss $(ms2sf ${msstart}) -i ${INPUTFILE} \
		-t $(ms2sf ${msduration})  \
		-map 0 -c:v  copy -c:a  copy -c:s copy \
		-avoid_negative_ts 1   ${workdir}/${chunkhead}_${chunk}.ts"
		echo ${CMD}
		$CMD
		echo "file ${workdir}/${chunkhead}_${chunk}.ts" >> ${workdir}/out.concat
		chunk=$(( $chunk + 1 ))
	done
	#
	# stitch the chunks together
	CMD="ffmpeg -fflags +genpts -flags +global_header -y -f concat -safe 0 -i ${workdir}/out.concat -c copy  ${WORKFILE}"
	echo ${CMD}
	$CMD
fi
umask 177
mkdir -p $(dirname ${FINALFILE})
#
# Offload the transcoding to a later process if it's COPY 
if [[ "${quality}" == "COPY" ]];
then
	echo "Copying ${WORKFILE} to ${FINALFILE} without transcoding"
	cp ${WORKFILE} "${FINALFILE}"
	echo ${FINALFILE} >> /home/mythtv/save/transcode.txt
else
	echo "/usr/bin/HandBrakeCLI -i \"${WORKFILE}\" -o \"${FINALFILE}\" ${quality}"
	/usr/bin/HandBrakeCLI -i "${WORKFILE}" -o "${FINALFILE}" ${quality}
fi

rc=$?

if [  $rc -eq 0 ];then
	rm -rf ${workdir}
	ls -l "${FINALFILE}" | mail -s "Finished cutting ${FINALFILE}" mythtv
else
	echo "" | mail -s "Encode failed in ${workdir}" mythtv
fi


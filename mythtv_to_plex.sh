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
		# Anything recorded before 1000 hours UTC (before 6am ET) is assumed to be a rebroadcast from the night before.
		PREFIXDT=$(date -d "${starttime} UTC-599 minutes" "+%Y-%m-%d")
		FINALFILE="${tvlib}/${plextitle}/${plextitle}.${PREFIXDT}.${finalext}"
	fi
else
	PREFIXDT=`date -d "${starttime} UTC" "+%Y-%m-%d"`
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
#########################################
##
#  Translate all team names to ones that match thesportsdb.com
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
	team1name=`echo "select plextitle from plexnames where title=\"${team1}\";" | $mysqlconnect`
	if [ -z "$team1name" ];then
		team1name=$team1
	fi
	team2name=`echo "select plextitle from plexnames where title=\"${team2}\";" | $mysqlconnect`
	if [ -z "$team2name" ];then
		team2name=$team2
	fi
	t="${team1name}_vs_${team2name}."
fi
echo $t
if [[ `echo $FINALFILE | tr '[:upper:]' '[:lower:]'` =~ 'liverpool' ]]; 
then
	if [[ "$FINALFILE" =~ "Premier League" ]];then
		PREFIXTITLE="English_Premier_League"
		FINALFILE="/mnt/disk/share/sports/English Premier League/Season 2021/${PREFIXTITLE}.${PREFIXDT}.${t}${finalext}"
	fi
	if [[ "$FINALFILE" =~ "UEFA Champions League Soccer" ]];then
		PREFIXTITLE="UEFA_Champions_League"
		FINALFILE="/mnt/disk/share/sports/UEFA Champions League/Season 2021/${PREFIXTITLE}.${PREFIXDT}.${t}${finalext}"
	fi
	###FINALFILETHUMB=`echo $(dirname "$FINALFILE")"/"$(basename "$FINALFILE" ${finalext})"jpg"`
	###FINALFILE=`echo $(dirname "$FINALFILE")"/"$(basename "$FINALFILE" ${finalext})"mpg"`
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/liverpool_logo.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/liverpool_logo.jpg "${FINALFILETHUMB}"
	WORKFILE=${INPUTFILE}
	#quality="Fast 720p30"
elif [[ `echo $FINALFILE | tr '[:upper:]' '[:lower:]'` =~ 'columbus_crew' ]]; 
then
	if [[ "$FINALFILE" =~ "MLS Soccer" ]]; then
		PREFIXTITLE="MLS"
		FINALFILE="/mnt/disk/share/sports/MLS/Season 2021/${PREFIXTITLE}.${PREFIXDT}.${t}${finalext}"
	fi
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/ColumbusCrewSC1.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/ColumbusCrewSC1.jpg "${FINALFILETHUMB}"
	WORKFILE=${INPUTFILE}
	#quality="Very Fast 1080p30"
elif [[ "$FINALFILE"  =~ "Premier League Soccer" ]];
then
	PREFIXTITLE="English_Premier_League"
	FINALFILE="/mnt/disk/share/sports/English Premier League/Season 2021/${PREFIXTITLE}.${PREFIXDT}.${t}${finalext}"
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/PremierLeague.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/PremierLeague.jpg "${FINALFILETHUMB}"
	WORKFILE=${INPUTFILE}
	#quality="Fast 1080p30"
elif [[ "$FINALFILE"  =~ "NFL Football" ]];
then
	PREFIXTITLE="NFL"
	FINALFILE="/mnt/disk/share/sports/NFL/Season 2021/${PREFIXTITLE}.${PREFIXDT}.${t}${finalext}"
	WORKFILE=${INPUTFILE}
elif [[ "$FINALFILE"  =~ "MLS " ]];
then
	PREFIXDT=`date -d "${starttime} UTC" "+%Y-%m-%d"`
	if [[ "$FINALFILE" =~ "MLS Soccer" ]]; then
		PREFIXTITLE="MLS"
		FINALFILE="/mnt/disk/share/sports/MLS/Season 2021/${PREFIXTITLE}.${PREFIXDT}.${t}${finalext}"
	fi
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/mls.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/mls.jpg "${FINALFILETHUMB}"
	WORKFILE=${INPUTFILE}
	#quality="Very Fast 1080p30"
elif [[ "$FINALFILE"  =~ 'MLB Baseball' ]];
then
	PREFIXTITLE="MLB"
	if [[ $t =~ _at_ ]];then
		t=`echo $t | sed -e 's/\(.*\)_at_\(.*\)/\2_vs_\1/'`
	fi 
	FINALFILE="/mnt/disk/share/sports/MLB/Season 2020/${PREFIXTITLE}.${PREFIXDT}.${t}${finalext}"
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/mlblogo.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/mlblogo.jpg "${FINALFILETHUMB}"
	WORKFILE=${INPUTFILE}
	#quality="Very Fast 720p30"
else 
	searchtitle=$( echo $title |  sed -e "s/[,\/\"\'\.()]//g" )
echo $searchtitle
	if [ -d "/mnt/disk/share/sports/$searchtitle" ];
	then
		sportseason=$( cd "/mnt/disk/share/sports/$searchtitle"; ls --color=never -d -t */ | head -1)
echo $sportseason
		if [ -n "$sportseason" ];
		then
			FINALFILE="/mnt/disk/share/sports/${searchtitle}/${sportseason}${PREFIXTITLE}.${PREFIXDT}.${t}${finalext}"
			WORKFILE=${INPUTFILE}
		fi
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

	format=`mediainfo --Inform="Video;%Format%" ${INPUTFILE}`

	echo "Format = $format"
	#cutlist provides a list of frames in the format start-end,[start1-end1,....] to cut 
	# for FFMpeg, we swap this list so that it provides the ranges of video we want in the format
	#	start-end start1:end1 ....
	# For Mythtranscode, we use the Cutlist as it is.
	CUTLIST=`mythutil --chanid $chanid --starttime "$starttime" --getcutlist | grep Cutlist | sed 's/Cutlist: //' | sed 's/-/,/g' `
	echo "CUTLIST=${CUTLIST}"

	echo "Cutting and Transcoding $format Video"
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
		-map 0:0 -c:v  copy \
		-map 0:1 -c:a  copy \
		-avoid_negative_ts 1   ${workdir}/${chunkhead}_${chunk}.ts"
		echo ${CMD}
		$CMD
		echo "file ${workdir}/${chunkhead}_${chunk}.ts" >> ${workdir}/out.concat
		chunk=$(( $chunk + 1 ))
	done
	CMD="ffmpeg -fflags +genpts -flags +global_header -y -f concat -safe 0 -i ${workdir}/out.concat -c copy  ${WORKFILE}"
	echo ${CMD}
	$CMD
#
#	       CUTLIST=`T="";for i in $CUTLIST;do T=${T},$(($i-1));done; echo $T | sed 's/^,//'`
#	       echo $CUTLIST
#	       # Example
#	       # ffmpeg -f concat -i out.ffconcat -c copy /var/lib/mythtv/recordings/2225_20140907040000.mp4
#	       # ffmpeg -i 2225_20140907040000.mp4 -map 0 -c copy -f ssegment -segment_list out.ffconcat -segment_frames 281,44671,52797,82802,92730,116499,127329,146333,156290,180843,192567,213474,218498 out%03d.mp4
#	       echo "ffmpeg -i  ${INPUTFILE} -map 0 -c copy -f ssegment -segment_list ${workdir}/out.ffconcat -segment_frames $CUTLIST ${workdir}/out%03d.mp4"
#	       ffmpeg -i  ${INPUTFILE} -map 0 -c copy -f ssegment -segment_list ${workdir}/out.ffconcat -segment_frames $CUTLIST ${workdir}/out%03d.mp4
#	       cat ${workdir}/out.ffconcat | awk $AWKCMD > ${workdir}/in.ffconcat
#	       files=`grep file ${workdir}/in.ffconcat | sed -e 's/file //g'`
#	       for infile in $files
#	       do
#		       tsfile=`echo $infile | sed -e 's/mp4/ts/'`
#		       echo "ffmpeg -i ${workdir}/${infile} -c copy -bsf:v h264_mp4toannexb -f mpegts ${workdir}/${tsfile}"
#		       ffmpeg -i ${workdir}/${infile} -c copy -bsf:v h264_mp4toannexb -f mpegts ${workdir}/${tsfile}
#	       done
#	       cat ${workdir}/in.ffconcat | sed -e 's/mp4/ts/' > ${workdir}/ts.ffconcat
#	       echo "ffmpeg -y -f concat -safe 0 -i ${workdir}/ts.ffconcat -c copy ${WORKFILE}"
#	       ffmpeg -y -f concat -safe 0 -i ${workdir}/ts.ffconcat -c copy ${WORKFILE}
fi
umask 177
if [[ "${quality}" == "COPY" ]];
then
	echo "Copying ${WORKFILE} to ${FINALFILE} without transcoding"
	cp ${WORKFILE} "${FINALFILE}"
	echo ${FINALFILE} >> /home/mythtv/save/transcode.txt
#################
# For videos that aren't being archived, just being watched on my tablet, use a faster, smaller setup - 720x404 and AAC superfast
#
elif [[ "${quality}" == "Temp" ]];
then
	if [ $oldversion -eq 1 ];then
		echo "/usr/bin/HandBrakeCLI -i ${WORKFILE} -o \"${FINALFILE}\" -e x264 -w 720 --keep-display-aspect --modulus 16 -q 24.0 -r 29.97 -a 1 -E faac,copy -B 160 -6 dpl2 -R Auto -D 0.0 --audio-copy-mask aac,ac3,dtshd,dts,mp3 --audio-fallback ffac3 -f mkv -4 --loose-anamorphic --modulus 2 -m --x264-preset superfast --h264-profile baseline --h264-level 4.0 --x264-tune film -s 1 -F"
		/usr/bin/HandBrakeCLI -i ${WORKFILE} -o "${FINALFILE}" -e x264 -w 720 --keep-display-aspect --modulus 16 -q 24.0 -r 29.97 -a 1 -E faac,copy -B 160 -6 dpl2 -R Auto -D 0.0 --audio-copy-mask aac,ac3,dtshd,dts,mp3 --audio-fallback ffac3 -4 --loose-anamorphic --modulus 2 -m --x264-preset superfast --h264-profile baseline --h264-level 4.0 --x264-tune film -s 1 -F
	else
		echo "HandBrakeCLI -i ${WORKFILE} -o \"${FINALFILE}\" --preset \"Very Fast 480p30\""
		/usr/bin/HandBrakeCLI -i ${WORKFILE} -o "${FINALFILE}" --preset "Very Fast 480p30"
	fi
else
	echo "/usr/bin/HandBrakeCLI -i ${WORKFILE} -o \"${FINALFILE}\" --preset \"${quality}\""
	/usr/bin/HandBrakeCLI -i ${WORKFILE} -o "${FINALFILE}" --preset "${quality}"
	#echo "Copying ${WORKFILE} to ${FINALFILE} without transcoding AND NOT SETTING FOR AUTO TRANSCODE"
	#cp ${WORKFILE} "${FINALFILE}" 
fi

rc=$?

if [  $rc -eq 0 ];then
	rm -rf ${workdir}
	ls -l "${FINALFILE}" | mail -s "Finished cutting ${FINALFILE}" jbalcorn@gmail.com
else
	echo "" | mail -s "Encode failed in ${workdir}" mythtv
fi


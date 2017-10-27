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
quality="Universal"
# MySQL Config file with username and password (DON'T PASS THEM ON COMMAND LINE)
mysqlinfo="~/.mythtv/mysql.cnf"

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

if [ ! -f $INPUTFILE ]; then
    echo "file ${INPUTFILE} doesn't exist, aborting."
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
echo "CHANID $chanid STARTTIME $starttime"
title=`echo "select title from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
subtitle=`echo "select subtitle from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
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
echo "Bashename = $BASENAME"
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
echo "Checking for Directory ${tvlib}/${plextitle}"
if [ -d "${tvlib}/${plextitle}" ]
then
	FINALFILE="${tvlib}/${plextitle}/${plextitle}.${se}${t}${finalext}"
else
	PREFIXDT=`date -d "${starttime} UTC" "+%Y%m%d %H%M"`
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
	quality="Temp"
fi
echo "Final File will be ${FINALFILE}"

##########################
# BEGINNING OF PERSONALIZED PROCESSING. DELETE OR MODIFY THIS SECTION
#
# I want my soccer to be copied without trancoding or lowering quality, and I want Plex to use a logo rather than put
#   spoilers in the frame grabed picture for any of these games.
#
# Liverpool and Columbus Crew get their own logos, because they're my teams.
#   others get EPL and MLS logos.
#########################################
if [[ `echo $FINALFILE | tr '[:upper:]' '[:lower:]'` =~ 'liverpool' ]]; 
then
	###FINALFILETHUMB=`echo $(dirname "$FINALFILE")"/"$(basename "$FINALFILE" ${finalext})"jpg"`
	###FINALFILE=`echo $(dirname "$FINALFILE")"/"$(basename "$FINALFILE" ${finalext})"mpg"`
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/liverpool_logo.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/liverpool_logo.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
elif [[ `echo $FINALFILE | tr '[:upper:]' '[:lower:]'` =~ 'columbus_crew' ]]; 
then
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/ColumbusCrewSC1.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/ColumbusCrewSC1.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
elif [[ $FINALFILE  =~ 'EPL ' ]];
then
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/PremierLeague.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/PremierLeague.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
elif [[ $FINALFILE  =~ 'MLS ' ]];
then
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/mls.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/mls.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
elif [[ $FINALFILE  =~ 'FIFA World Cup ' ]];
then
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/fifa2018.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/fifa2018.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
elif [[ $FINALFILE  =~ 'MLB Baseball ' ]];
then
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp ${thumbdir}/mlblogo.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp ${thumbdir}/mlblogo.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
fi
#################
# End of PERSONALIZED PROCESSING
#################
if [[  "quality" != "NONE" ]];
then
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
fi   

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

if [[ $format == "MPEG Video" ]];then
	echo "Cutting and Transcoding $format Video"
	WORKFILE="${WORKFILEBASE}.mpg"
	if [ -z $CUTLIST ];then
		echo "No cutlist.  Just work on input file"
		WORKFILE=${INPUTFILE}
	else
		echo "mythtranscode --honorcutlist -m -i ${INPUTFILE} -o ${WORKFILE}"
		mythtranscode --honorcutlist -m -i ${INPUTFILE} -o ${WORKFILE}
		mv -f ${INPUTFILE}.old ${INPUTFILE}
	fi
elif [[ $format == "AVC" ]];then
	if [[ $CUTLIST =~ ^0, ]];then
		CUTLIST=`echo $CUTLIST | sed 's/^0,//'`
		AWKCMD='NR%2==1'
	else 
		AWKCMD='NR%2!=1'
	fi
	WORKFILE=${WORKFILEBASE}.mp4
	CUTLIST=`echo $CUTLIST | sed 's/,/ /g'`
	echo $CUTLIST
	
	CUTLIST=`T="";for i in $CUTLIST;do T=${T},$(($i-1));done; echo $T | sed 's/^,//'`
	echo $CUTLIST
	if [ -z "$CUTLIST" ];then
		echo "No cutlist.  Just work on input file"
		WORKFILE=${INPUTFILE}
	else
		# Example
		# ffmpeg -f concat -i out.ffconcat -c copy /var/lib/mythtv/recordings/2225_20140907040000.mp4
		# ffmpeg -i 2225_20140907040000.mp4 -map 0 -c copy -f ssegment -segment_list out.ffconcat -segment_frames 281,44671,52797,82802,92730,116499,127329,146333,156290,180843,192567,213474,218498 out%03d.mp4
		echo "ffmpeg -i  ${INPUTFILE} -map 0 -c copy -f ssegment -segment_list ${workdir}/out.ffconcat -segment_frames $CUTLIST ${workdir}/out%03d.mp4"
		ffmpeg -i  ${INPUTFILE} -map 0 -c copy -f ssegment -segment_list ${workdir}/out.ffconcat -segment_frames $CUTLIST ${workdir}/out%03d.mp4
		cat ${workdir}/out.ffconcat | awk $AWKCMD > ${workdir}/in.ffconcat
		files=`grep file ${workdir}/in.ffconcat | sed -e 's/file //g'`
		for infile in $files
		do
			tsfile=`echo $infile | sed -e 's/mp4/ts/'`
			echo "ffmpeg -i ${workdir}/${infile} -c copy -bsf:v h264_mp4toannexb -f mpegts ${workdir}/${tsfile}"
			ffmpeg -i ${workdir}/${infile} -c copy -bsf:v h264_mp4toannexb -f mpegts ${workdir}/${tsfile}
		done 
		cat ${workdir}/in.ffconcat | sed -e 's/mp4/ts/' > ${workdir}/ts.ffconcat
		echo "ffmpeg -y -f concat -safe 0 -i ${workdir}/ts.ffconcat -c copy ${WORKFILE}"
		ffmpeg -y -f concat -safe 0 -i ${workdir}/ts.ffconcat -c copy ${WORKFILE}
	fi
	
else 
	echo "Format ${format} for video not recognized"
	exit
fi # AVC
fi # Skip cutting

umask 177
if [[ "${quality}" == "NONE" ]];
then
	echo "cp ${INPUTFILE} ${FINALFILE}"
	cp ${INPUTFILE} "${FINALFILE}"
#################
# For videos that aren't being archived, just being watched on my tablet, use a faster, smaller setup - 720x404 and AAC superfast
#
elif [[ "${quality}" == "Temp" ]];
then
	echo "/usr/bin/HandBrakeCLI -i ${WORKFILE} -o \"${FINALFILE}\" -e x264 -w 720 --keep-display-aspect --modulus 16 -q 24.0 -r 29.97 -a 1 -E faac,copy -B 160 -6 dpl2 -R Auto -D 0.0 --audio-copy-mask aac,ac3,dtshd,dts,mp3 --audio-fallback ffac3 -f mkv -4 --loose-anamorphic --modulus 2 -m --x264-preset superfast --h264-profile baseline --h264-level 4.0 --x264-tune film -s 1 -F"
	/usr/bin/HandBrakeCLI -i ${WORKFILE} -o "${FINALFILE}" -e x264 -w 720 --keep-display-aspect --modulus 16 -q 24.0 -r 29.97 -a 1 -E faac,copy -B 160 -6 dpl2 -R Auto -D 0.0 --audio-copy-mask aac,ac3,dtshd,dts,mp3 --audio-fallback ffac3 -4 --loose-anamorphic --modulus 2 -m --x264-preset superfast --h264-profile baseline --h264-level 4.0 --x264-tune film -s 1 -F

else
	echo "/usr/bin/HandBrakeCLI -i ${WORKFILE} -o "${FINALFILE}" --preset ${quality}"
	/usr/bin/HandBrakeCLI -i ${WORKFILE} -o "${FINALFILE}" --preset ${quality}
fi

rc=$?

if [  $rc -eq 0 ];then
	echo rm -rf ${workdir}
else
	echo "" | mail -s "Encode failed in ${workdir}" mythtv
fi


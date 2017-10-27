#!/bin/bash
# Justin Alcorn justin@jalcorn.net
# Based on original script by:
# Ian Thiele
# icthiele@gmail.com
#Uses mythcommflag, ffmpeg, and mkvmerge to cut commercials out of h.264 encoded mpg files#

# Options: mp4,mkv
finalext="mp4"
# Options: any preset, common are Universal, Normal, High Profile
quality="Universal"
if [ ! -t 1 ];then

	logfile=/home/mythtv/save/$$.log
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

#see if we have the DB info
test -f /etc/mythtv/mysql.txt && . /etc/mythtv/mysql.txt
test -f ~/.mythtv/mysql.txt && . ~/.mythtv/mysql.txt

#let's make sure we have a sane environment
if [ -z "`which ffmpeg`" ]; then
    echo "FFMpeg not present in the path. Adjust environment or install ffmpeg"
    exit 1
fi

#connect to DB
#mysqlconnect="mysql -N -h$DBHostName -u$DBUserName -p$DBPassword $DBName"
mysqlconnect="mysql --defaults-extra-file=~/.mythtv/mysql.cnf -N $DBName"
export mysqlconnect

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
	plextitle=`echo $title |  sed -e 's/ /_/g' | sed -e "s/[,\/\"\'\.()]//g"`
fi
season=`echo "select season from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
episode=`echo "select episode from recorded where basename=\"$BASENAME\";" | $mysqlconnect`

info=`echo "select title, subtitle from recorded where basename=\"$BASENAME\";" | $mysqlconnect`
echo $info

if [ $episode -gt 0 ]
then
	s=`printf %02d $season`
	e=`printf %02d $episode`
	se="S${s}E${e}."
else
	se=""
fi

if [ -n "$subtitle" ];then
	t=`echo $subtitle |  sed -e 's/ /_/g' | sed -e "s/[,;\/\"\'\.()]//g"`
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
############################################3
echo "Checking for Directory /mnt/disk/share/tv/${plextitle}"
if [ -d "/mnt/disk/share/tv/${plextitle}" ]
then
	FINALFILE="/mnt/disk/share/tv/${plextitle}/${plextitle}.${se}${t}${finalext}"
else
	PREFIXDT=`date -d "${starttime} UTC" "+%Y%m%d %H%M"`
	PREFIXTITLE=`echo $plextitle | sed -e 's/_/ /g'`
	FINALFILE="/mnt/disk/share/recordings/${PREFIXTITLE} ${PREFIXDT}.${t}${finalext}"
echo "does /home/mythtv/${plextitle}.jpg exist?"
	if [ -e "/home/mythtv/${plextitle}.jpg" ];then
		FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
		echo "cp \"/home/mythtv/${plextitle}.jpg\" \"${FINALFILETHUMB}\""
		cp "/home/mythtv/${plextitle}.jpg" "${FINALFILETHUMB}"
		FINALFILETHUMB=`echo $FINALFILE | sed -e "s/\.${finalext}$/-fanart.jpg/"`
		echo "cp \"/home/mythtv/${plextitle}.jpg\" \"${FINALFILETHUMB}\""
		cp "/home/mythtv/${plextitle}.jpg" "${FINALFILETHUMB}"
	fi
	quality="Temp"
fi
echo "Final File will be ${FINALFILE}"

##########################
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
	cp /home/mythtv/liverpool_logo.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp /home/mythtv/liverpool_logo.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
elif [[ `echo $FINALFILE | tr '[:upper:]' '[:lower:]'` =~ 'columbus_crew' ]]; 
then
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp /home/mythtv/ColumbusCrewSC1.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp /home/mythtv/ColumbusCrewSC1.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
elif [[ $FINALFILE  =~ 'EPL ' ]];
then
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp /home/mythtv/PremierLeague.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp /home/mythtv/PremierLeague.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
elif [[ $FINALFILE  =~ 'MLS ' ]];
then
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp /home/mythtv/mls.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp /home/mythtv/mls.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
elif [[ $FINALFILE  =~ 'FIFA World Cup ' ]];
then
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp /home/mythtv/fifa2018.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp /home/mythtv/fifa2018.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
elif [[ $FINALFILE  =~ 'MLB Baseball ' ]];
then
	FINALFILETHUMB=`echo $FINALFILE | sed -e "s/${finalext}$/jpg/"`
	cp /home/mythtv/mlblogo.jpg "${FINALFILETHUMB}"
	FINALFILETHUMB=`echo $FINALFILETHUMB | sed -e "s/\.jpg/-fanart.jpg/"`
	cp /home/mythtv/mlblogo.jpg "${FINALFILETHUMB}"
	FINALFILEMPG=`echo $FINALFILE | sed -e "s/${finalext}$/mpg/"`
	WORKFILE=${INPUTFILE}
	cp "${WORKFILE}" "${FINALFILEMPG}"
	quality="NORMAL"
fi
#################
# End of very specific processing for sports
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


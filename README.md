# mythtv-plex

Scripts that cut commercials, transcode to h.264 and create Plex-friendly file naming.

Use plexnames.sql to add a table to mythconverg that will allow you to control how the Mythtv names
are translated into Plex-compliant names.  edit mysql.cnf and put it somewhere to be used by the script code.  Be sure to edit the 
variables in the script:


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

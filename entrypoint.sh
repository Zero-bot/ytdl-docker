#!/bin/sh
set -eu

if [ $# -eq 0 ]; then
    printf 'Usage: ytdl [--audio] [yt-dlp options] URL [URL...]\n\n'
    printf 'Default: highest-quality video (MKV container)\n'
    printf '  --audio  best audio only, original codec, no re-encode\n'
    exit 2
fi

audio=0
argc=$#
i=0
while [ "$i" -lt "$argc" ]; do
    case "$1" in
        --audio) audio=1 ;;
        *) set -- "$@" "$1" ;;
    esac
    shift
    i=$((i + 1))
done

if [ "$audio" -eq 1 ]; then
    exec yt-dlp \
        --ignore-config --no-exec --embed-metadata \
        -o '%(title).150B [%(id)s].%(ext)s' \
        -f 'ba/b' -S 'abr,asr' -x --embed-thumbnail \
        "$@"
else
    exec yt-dlp \
        --ignore-config --no-exec --embed-metadata \
        -o '%(title).150B [%(id)s].%(ext)s' \
        -f 'bv*+ba/b' -S 'res,fps,br' --merge-output-format mkv \
        "$@"
fi

#!/bin/sh
# Download one Retrosheet season (team list, event files, rosters, game log)
# from the chadwickbureau/retrosheet mirror at a pinned commit.
# usage: ingest/fetch.sh <sha> <year> <dir>
set -eu
if [ $# -ne 3 ]; then
  echo "usage: ingest/fetch.sh <sha> <year> <dir>" >&2
  exit 2
fi
sha=$1
year=$2
dir=$3
base=https://raw.githubusercontent.com/chadwickbureau/retrosheet/$sha/seasons/$year
mkdir -p "$dir"
cd "$dir"
# TEAM$year is written last, so its presence means the whole season arrived.
curl -fsSL --retry 3 -o "TEAM$year.part" "$base/TEAM$year"
tr -d '\r' < "TEAM$year.part" | while IFS=, read -r team league _; do
  case $team in
    ALS|NLS|'') continue ;;
  esac
  curl -fsSL --retry 3 -o "$year$team.EV$league" "$base/$year$team.EV$league"
  curl -fsSL --retry 3 -o "$team$year.ROS" "$base/$team$year.ROS"
done
# The mirror names the game log gl$year.txt or GL$year.TXT. Saved as gl$year.txt
# so ingest's -log path does not depend on that case.
if curl -fsSL --retry 3 -o "gl$year.txt.part" "$base/gl$year.txt" \
   || curl -fsSL --retry 3 -o "gl$year.txt.part" "$base/GL$year.TXT"; then
  mv "gl$year.txt.part" "gl$year.txt"
else
  rm -f "gl$year.txt.part"
  echo "fetch: no game log for $year" >&2
  exit 1
fi
mv "TEAM$year.part" "TEAM$year"

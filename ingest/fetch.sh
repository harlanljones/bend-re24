#!/bin/sh
# Download one Retrosheet season (team list, event files, rosters) from the
# chadwickbureau/retrosheet mirror at a pinned commit.
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
mv "TEAM$year.part" "TEAM$year"

#!/bin/sh
set -eu

source_store=$1
destination_store=$2
java_home=${JAVA_HOME:-$(java -XshowSettings:properties -version 2>&1 | awk '/^[[:space:]]*java\.home =/ { print $3; exit }')}
[ -n "$java_home" ] || { echo "could not locate the active Java home" >&2; exit 1; }
keytool="$java_home/bin/keytool"
store_password=changeit
emsign_g3=86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B
aaa_root=D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT HUP INT TERM
export LC_ALL=C

mkdir -p "$(dirname "$destination_store")"
cp -p "$source_store" "$destination_store"

list_matching_aliases() {
	"$keytool" -list -v -keystore "$1" -storepass "$store_password" \
		-J-Duser.language=en -J-Duser.country=US > "$workdir/keytool-list"
	awk -v emsign="$emsign_g3" -v aaa="$aaa_root" '
		/^Alias name: / { alias = substr($0, 13); next }
		/SHA256:/ {
			fingerprint = $2
			gsub(":", "", fingerprint)
			fingerprint = toupper(fingerprint)
			if (fingerprint == emsign || fingerprint == aaa) print alias
		}
	' "$workdir/keytool-list"
}

list_matching_aliases "$destination_store" > "$workdir/matching-aliases"
emsign_removed=0
aaa_removed=0

while IFS= read -r alias; do
	[ -n "$alias" ] || continue
	"$keytool" -list -v -keystore "$destination_store" -storepass "$store_password" \
		-J-Duser.language=en -J-Duser.country=US -alias "$alias" > "$workdir/alias-list"
	fingerprint=$(awk '
		/SHA256:/ {
			fingerprint = $2
			gsub(":", "", fingerprint)
			print toupper(fingerprint)
			exit
		}
	' "$workdir/alias-list")
	case "$fingerprint" in
		"$emsign_g3") emsign_removed=$((emsign_removed + 1)) ;;
		"$aaa_root") aaa_removed=$((aaa_removed + 1)) ;;
		*) echo "unexpected fingerprint for Java alias: $alias" >&2; exit 1 ;;
	esac
	"$keytool" -delete -keystore "$destination_store" -storepass "$store_password" \
		-J-Duser.language=en -J-Duser.country=US -alias "$alias"
done < "$workdir/matching-aliases"

list_matching_aliases "$destination_store" > "$workdir/remaining-aliases"
if [ -s "$workdir/remaining-aliases" ]; then
	echo "distrusted certificate remains in Java cacerts" >&2
	cat "$workdir/remaining-aliases" >&2
	exit 1
fi

printf '{"removed":{"emsign_g3":%s,"aaa_root":%s}}\n' \
	"$emsign_removed" "$aaa_removed"

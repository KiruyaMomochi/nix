# Turns Unicode's emoji-test.txt into hotaru's emoji list: one per line,
# the tab it goes under, a tab, the emoji. Fully qualified only, no skin
# tone variants, nothing newer than the colour emoji font on saren draws.
BEGIN {
    tab["Smileys & Emotion"] = "😀"
    tab["People & Body"] = "👋"
    tab["Animals & Nature"] = "🐱"
    tab["Food & Drink"] = "🍙"
    tab["Travel & Places"] = "🚗"
    tab["Activities"] = "⚽"
    tab["Objects"] = "💡"
    tab["Symbols"] = "❤️"
    tab["Flags"] = "🏳️"
}
/^# group: / { group = substr($0, 10); next }
/; fully-qualified/ {
    if (!(group in tab) || $0 ~ /skin tone/) next
    split($0, parts, "# ")
    split(parts[2], fields, " ")
    if (substr(fields[2], 2) + 0 > 15.1) next
    print tab[group] "\t" fields[1]
}

#!/bin/bash
# Semantic matching using keyword counting + gzip NCD
# Usage: semantic-match.sh "prompt" "description" "keywords"
# Returns: 0 if match, 1 if no match
# Output: match score details to stderr

PROMPT="$1"
DESC="$2"
KEYWORDS="$3"

# Stopwords to ignore
STOPWORDS="the a an is are was were be been being have has had do does did will would could should may might must shall can this that these those it its what how why when where who let lets just to for of in on at by"

# --- Keyword counting ---
kw_count=0
for word in $(echo "$PROMPT" | tr '[:upper:]' '[:lower:]'); do
  [[ ${#word} -lt 3 ]] && continue
  echo "$STOPWORDS" | grep -qw "$word" && continue
  echo "$KEYWORDS" | grep -qiw "$word" && ((kw_count++))
done

# --- Gzip NCD (Normalized Compression Distance) ---
csize() { printf '%s' "$1" | gzip -c | wc -c; }
ca=$(csize "$DESC")
cb=$(csize "$PROMPT")
cab=$(csize "${DESC}${PROMPT}")
min=$((ca < cb ? ca : cb))
max=$((ca > cb ? ca : cb))
ncd=$(echo "scale=4; ($cab - $min) / $max" | bc)

# --- Decision: keywords >= 2 OR ncd < 0.58 ---
if [[ $kw_count -ge 2 ]] || (( $(echo "$ncd < 0.58" | bc -l) )); then
  echo "match: kw=$kw_count ncd=$ncd" >&2
  exit 0
else
  echo "no match: kw=$kw_count ncd=$ncd" >&2
  exit 1
fi

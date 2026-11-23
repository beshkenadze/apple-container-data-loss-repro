#!/bin/bash
# Prints a Markdown table, defect by code under test, from results/*.tsv.
set -u
cat results/*.tsv | awk -F '\t' -v order="upstream-1.7.1 upstream-main fix-a fix-b pr-2127" '
    BEGIN { nc = split(order, codes, " "); for (c = 1; c <= nc; c++) seen_c[codes[c]] = 1 }
    {
        if (!($1 in seen_d)) { seen_d[$1] = 1; defects[++nd] = $1 }
        if (!($2 in seen_c)) { seen_c[$2] = 1; codes[++nc] = $2 }
        mark = ($3 == $4) ? "as expected" : "**NOT as expected: " $4 "**"
        cell[$1, $2] = $3 " (" mark ")"
    }
    END {
        line = "| Defect |"; sep = "|---|"
        for (c = 1; c <= nc; c++) { line = line " " codes[c] " |"; sep = sep "---|" }
        print line; print sep
        for (d = 1; d <= nd; d++) {
            line = "| " defects[d] " |"
            for (c = 1; c <= nc; c++) {
                v = ((defects[d], codes[c]) in cell) ? cell[defects[d], codes[c]] : "—"
                line = line " " v " |"
            }
            print line
        }
    }'

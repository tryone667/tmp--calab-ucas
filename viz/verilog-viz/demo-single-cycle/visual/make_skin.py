# -*- coding: utf-8 -*-
t = open('node_modules/netlistsvg/lib/default.svg', encoding='utf-8').read()
if '$sdff' not in t:
    t = t.replace('<s:alias val="$dff"/>', '<s:alias val="$dff"/>\n    <s:alias val="$sdff"/>', 1)
open('skin_custom.svg', 'w', encoding='utf-8').write(t)
print('skin ok, sdff alias added:', '<s:alias val="$sdff"/>' in open('skin_custom.svg', encoding='utf-8').read())

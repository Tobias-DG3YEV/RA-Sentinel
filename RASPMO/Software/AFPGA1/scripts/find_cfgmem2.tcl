puts "=== all cfgmem parts containing 128 ==="
foreach p [lsort -unique [get_cfgmem_parts *128*]] { puts "P128 $p" }
puts "=== containing fl-l or 128l or l-128 ==="
foreach p [lsort -unique [concat [get_cfgmem_parts *fl-l*] [get_cfgmem_parts *128l*] [get_cfgmem_parts *l128*]]] { puts "PL $p" }
puts "FIND2_DONE"

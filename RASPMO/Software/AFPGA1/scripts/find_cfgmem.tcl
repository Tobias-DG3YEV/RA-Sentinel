puts "=== cfgmem parts matching s25fl128 ==="
foreach p [get_cfgmem_parts *s25fl128*] { puts "PART $p" }
puts "=== also s25fl-l family ==="
foreach p [get_cfgmem_parts *s25fl-l*] { puts "PARTL $p" }
puts "FIND_DONE"

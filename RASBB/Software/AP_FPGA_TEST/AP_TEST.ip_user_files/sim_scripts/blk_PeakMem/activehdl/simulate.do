transcript off
onbreak {quit -force}
onerror {quit -force}
transcript on

asim +access +r +m+blk_PeakMem  -L xpm -L blk_mem_gen_v8_4_8 -L xil_defaultlib -L unisims_ver -L unimacro_ver -L secureip -O5 xil_defaultlib.blk_PeakMem xil_defaultlib.glbl

do {blk_PeakMem.udo}

run 1000ns

endsim

quit -force

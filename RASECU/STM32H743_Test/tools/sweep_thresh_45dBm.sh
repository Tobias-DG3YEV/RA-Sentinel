#!/bin/bash
P=/opt/st/stm32cubeide_2.2.0/plugins/com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.linux64_2.2.500.202603051304/tools/bin/STM32_Programmer_CLI
THR=0x24000D2C; MEAS=0x24000D34
wr(){ $P -c port=SWD mode=Hotplug -w32 $1 $(printf '0x%X' $2) >/dev/null 2>&1; }
rd(){ $P -c port=SWD mode=Hotplug -r32 $1 $2 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '^0x[0-9A-F]+ : .*'; }
echo "GENERATOR: 6M frame every 400ms at -45dBm  => target 2.500 /s"
echo "thresh   polls frames bad   rate/s   capture"
BEST=0; BESTR=0
for V in 8 15 25 35 50 70 100 150 200; do
  wr $THR $V; sleep 22
  L=$(rd $MEAS 12|head -1); Pp=$(echo "$L"|awk '{print $3}'); F=$(echo "$L"|awk '{print $4}'); B=$(echo "$L"|awk '{print $5}')
  python3 -c "
p=int('$Pp',16); f=int('$F',16); b=int('$B',16)
s=p/500.0; r=f/s if s>0 else 0
print('%6d  %6d %6d %3d  %6.3f  %6.1f%%' % ($V,p,f,b,r,100*r/2.5))"
done

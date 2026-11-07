#!/bin/bash
PROG=/opt/st/stm32cubeide_2.2.0/plugins/com.st.stm32cube.ide.mcu.externaltools.cubeprogrammer.linux64_2.2.500.202603051304/tools/bin/STM32_Programmer_CLI
CMD=0x24000D24; POLLS=0x24000D2C; RB=0x2400004C
rd() { $PROG -c port=SWD mode=Hotplug -r32 $1 $2 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -oE '^0x[0-9A-F]+ : .*' ; }
echo "thresh  readback   polls  frames  bad   rate/s  ratio_vs_5"
for T in 25 50 100 200 400 800 1600; do
  $PROG -c port=SWD mode=Hotplug -w32 $CMD $(printf '0x%X' $T) >/dev/null 2>&1
  sleep 25
  L=$(rd $POLLS 12 | head -1)
  P=$(echo "$L" | awk '{print $3}'); F=$(echo "$L" | awk '{print $4}'); B=$(echo "$L" | awk '{print $5}')
  R=$(rd $RB 4 | head -1 | awk '{print $3}')
  python3 -c "
p=int('$P',16); f=int('$F',16); b=int('$B',16); rb=int('$R',16)
s=p/500.0
r=f/s if s>0 else 0
print('%6d  %8d  %6d  %6d  %3d  %6.2f  %5.0f%%' % ($T, rb, p, f, b, r, 100*r/5.0))
"
done

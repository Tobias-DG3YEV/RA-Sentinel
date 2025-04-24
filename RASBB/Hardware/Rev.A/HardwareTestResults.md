
**These are the test results of the functional blocks of Rev. A that have been found by the board bring-up**

* The configuration flash memories of both FPGASs have been tested. Flash 1 worked successfully, while an error was found in Flash 2 and will be corrected in Rev B.

* The two FPGAs are accessible via JTAG. They have been programmed with a test software.

* FPGA 1 is capable receiving the LVDS data of the ADC. The sample stream has bee routed 
to the debug header and verified for validity. We found a termination issue on the 
LVDS line which will be fixed in Rev. B.

* The output for the alarm device has been succesfully tested.

* All voltages from the DC/DC power converters have been tested. They are stable and supply
enough energy for the prupose of the biard.

* The DDR RAM chips could not be tested sucessfully because of a mistake of one power supply pin. 
We expect them to be operational in the next board revision B.

* The STM32 microcontroller has been succesfully programmed. A test program has been
run to proove correct operation.

* The HDMI output port has been tested with a test pattern generator program. The 
produced image is clean and stable.

* USB-C functionality has been tested and proved to run successfully."

* Ethernet on uController STM32 works with 100 Mbps full duplex
  

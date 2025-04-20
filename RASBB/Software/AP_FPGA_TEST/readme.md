The project FPGA_TEST contains several blocks that can be used for testing the ADC data stream and HDMI port.
It puts the ADC samples decoded from the incoming LVDS signal into a parallel data word on Debug Pins D0 to D23
(Channel 1 and 2, reach 12 Bit of size)

Additionally, you can switch on the Spectrum display over HDMI and a waterfall view of the spectrum.

To activate thse additional steps, uncomment the following lines in rasm2400_pre_def.vh:

//`define USE_SPECTRUM //show a spectrum on the screen
//`define USE_WATERFALL //add a spectrogram (aka waterfall)

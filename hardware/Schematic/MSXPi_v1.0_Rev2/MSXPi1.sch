EESchema Schematic File Version 4
EELAYER 30 0
EELAYER END
$Descr A4 11693 8268
encoding utf-8
Sheet 1 1
Title ""
Date ""
Rev ""
Comp ""
Comment1 ""
Comment2 ""
Comment3 ""
Comment4 ""
$EndDescr
$Comp
L Connector:Raspberry_Pi_2_3 J1
U 1 1 5EDA5A35
P 1750 6300
F 0 "J1" H 1100 7550 50  0000 C CNN
F 1 "Raspberry_Pi_Zero_2_3" V 1750 6400 50  0000 C CNN
F 2 "Connector_PinHeader_2.54mm:PinHeader_2x20_P2.54mm_Vertical" H 1750 6300 50  0001 C CNN
F 3 "https://www.raspberrypi.org/documentation/hardware/raspberrypi/schematics/rpi_SCH_3bplus_1p0_reduced.pdf" H 1750 6300 50  0001 C CNN
	1    1750 6300
	1    0    0    -1  
$EndComp
$Comp
L Connector_Generic:Conn_02x05_Odd_Even J2
U 1 1 5EDB3FA0
P 4350 6950
F 0 "J2" H 4400 7367 50  0001 C CNN
F 1 "JTAG" H 4400 7276 50  0000 C CNN
F 2 "Connector_IDC:IDC-Header_2x05_P2.54mm_Horizontal" H 4350 6950 50  0001 C CNN
F 3 "~" H 4350 6950 50  0001 C CNN
	1    4350 6950
	1    0    0    -1  
$EndComp
$Comp
L Device:R_US R1
U 1 1 5EDB9788
P 3800 6750
F 0 "R1" V 3850 6900 50  0000 C CNN
F 1 "1k" V 3900 6750 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 3840 6740 50  0001 C CNN
F 3 "~" H 3800 6750 50  0001 C CNN
	1    3800 6750
	0    -1   -1   0   
$EndComp
$Comp
L Device:R_US R2
U 1 1 5EDBAC45
P 3800 6850
F 0 "R2" V 3750 6700 50  0000 C CNN
F 1 "1k" V 3750 7000 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 3840 6840 50  0001 C CNN
F 3 "~" H 3800 6850 50  0001 C CNN
	1    3800 6850
	0    1    1    0   
$EndComp
Wire Wire Line
	4150 7150 3950 7150
Wire Wire Line
	3950 6950 4000 6950
Wire Wire Line
	3650 6750 3400 6750
Wire Wire Line
	3550 6850 3650 6850
Wire Wire Line
	3650 6950 3550 6950
Connection ~ 3550 6950
Wire Wire Line
	3550 6950 3550 6850
Wire Wire Line
	3650 7150 3550 7150
Wire Wire Line
	3550 7150 3550 6950
$Comp
L Device:R_US R3
U 1 1 5EDBBCBA
P 3800 6950
F 0 "R3" V 3750 6800 50  0000 C CNN
F 1 "1k" V 3750 7100 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 3840 6940 50  0001 C CNN
F 3 "~" H 3800 6950 50  0001 C CNN
	1    3800 6950
	0    1    1    0   
$EndComp
Text GLabel 3950 6500 1    20   Input ~ 0
TDI
Text GLabel 4000 6500 1    20   Input ~ 0
TMS
Text GLabel 4050 6500 1    20   Input ~ 0
TDO
Text GLabel 4100 6500 1    20   Input ~ 0
TCK
Connection ~ 3950 7150
Wire Wire Line
	4150 6850 4050 6850
Wire Wire Line
	4000 6500 4000 6950
Connection ~ 4000 6950
Wire Wire Line
	3950 6750 4100 6750
Wire Wire Line
	4000 6950 4150 6950
Wire Wire Line
	4050 6500 4050 6850
Connection ~ 4050 6850
Wire Wire Line
	4050 6850 3950 6850
Wire Wire Line
	4100 6500 4100 6750
Connection ~ 4100 6750
Wire Wire Line
	4100 6750 4150 6750
Wire Wire Line
	4650 7150 4750 7150
Wire Wire Line
	4750 7150 4750 7300
Wire Wire Line
	4650 6750 4750 6750
Wire Wire Line
	4750 6750 4750 7150
Connection ~ 4750 7150
$Comp
L power:+5V #PWR04
U 1 1 5EDE086B
P 4900 6700
F 0 "#PWR04" H 4900 6550 50  0001 C CNN
F 1 "+5V" H 4915 6873 50  0001 C CNN
F 2 "" H 4900 6700 50  0001 C CNN
F 3 "" H 4900 6700 50  0001 C CNN
	1    4900 6700
	1    0    0    -1  
$EndComp
Wire Wire Line
	4900 6850 4650 6850
$Comp
L Device:R_US R4
U 1 1 5EDBC462
P 3800 7150
F 0 "R4" V 3750 7000 50  0000 C CNN
F 1 "1k" V 3700 7150 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 3840 7140 50  0001 C CNN
F 3 "~" H 3800 7150 50  0001 C CNN
	1    3800 7150
	0    1    1    0   
$EndComp
$Comp
L msx_slot:CONN_02X25 P1
U 1 1 5EDD120E
P 2400 2450
F 0 "P1" H 2400 3773 50  0001 C CNN
F 1 "MSX_CONNECTOR" H 2400 3773 50  0000 C CNN
F 2 "MyFootprints:card_edge_connector" H 2400 1700 50  0001 C CNN
F 3 "" H 2400 1700 50  0000 C CNN
	1    2400 2450
	1    0    0    -1  
$EndComp
Wire Wire Line
	2150 3250 2100 3250
Wire Wire Line
	2150 3350 2100 3350
Wire Wire Line
	2100 3350 2100 3250
Wire Wire Line
	2150 3550 2100 3550
Wire Wire Line
	2150 3450 2100 3450
Wire Wire Line
	2100 3450 2100 3550
Connection ~ 2100 3550
Text Label 1850 3550 0    50   ~ 0
+5V
Wire Wire Line
	2650 3350 2700 3350
Wire Wire Line
	2700 3350 2700 3450
Wire Wire Line
	2700 3450 2650 3450
$Comp
L Regulator_Linear:LD1117S33TR_SOT223 LD1117S33
U 1 1 5F009131
P 1450 3550
F 0 "LD1117S33" H 1450 3700 50  0000 C CNN
F 1 "LD1117S33TR_SOT223" H 1450 3790 50  0001 C CNN
F 2 "Package_TO_SOT_SMD:SOT-223-3_TabPin2" H 1450 3750 50  0001 C CNN
F 3 "http://www.st.com/st-web-ui/static/active/en/resource/technical/document/datasheet/CD00000544.pdf" H 1550 3300 50  0001 C CNN
	1    1450 3550
	-1   0    0    1   
$EndComp
$Comp
L Device:C_Small C2
U 1 1 5F0504D4
P 1250 3150
F 0 "C2" V 1150 3150 50  0000 C CNN
F 1 "100nF" V 1350 3050 50  0000 L CNN
F 2 "Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm" H 1250 3150 50  0001 C CNN
F 3 "~" H 1250 3150 50  0001 C CNN
	1    1250 3150
	0    1    1    0   
$EndComp
Wire Wire Line
	1150 3550 1100 3550
Wire Wire Line
	1150 3150 1100 3150
Wire Wire Line
	1100 3150 1100 3550
Connection ~ 1100 3550
Text Label 1900 3250 0    47   ~ 0
GND
$Comp
L Device:C_Small C1
U 1 1 5F04F395
P 1600 3150
F 0 "C1" V 1500 3150 50  0000 C CNN
F 1 "100nF" V 1550 3300 50  0000 C CNN
F 2 "Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm" H 1600 3150 50  0001 C CNN
F 3 "~" H 1600 3150 50  0001 C CNN
	1    1600 3150
	0    1    1    0   
$EndComp
Wire Wire Line
	1500 3150 1450 3150
Wire Wire Line
	1450 3150 1350 3150
Connection ~ 1450 3150
Wire Wire Line
	1450 3250 1450 3150
$Comp
L power:+3.3V #PWR0101
U 1 1 5F106193
P 650 3550
F 0 "#PWR0101" H 650 3400 50  0001 C CNN
F 1 "+3.3V" H 665 3723 50  0001 C CNN
F 2 "" H 650 3550 50  0001 C CNN
F 3 "" H 650 3550 50  0001 C CNN
	1    650  3550
	1    0    0    -1  
$EndComp
$Comp
L power:GNDREF #PWR0105
U 1 1 5F99611A
P 2150 7600
F 0 "#PWR0105" H 2150 7350 50  0001 C CNN
F 1 "GNDREF" H 2250 7500 28  0001 C CNN
F 2 "" H 2150 7600 50  0001 C CNN
F 3 "" H 2150 7600 50  0001 C CNN
	1    2150 7600
	1    0    0    -1  
$EndComp
$Comp
L power:GNDREF #PWR0108
U 1 1 5FB24D6F
P 3400 6750
F 0 "#PWR0108" H 3400 6500 50  0001 C CNN
F 1 "GNDREF" H 3405 6594 28  0001 C CNN
F 2 "" H 3400 6750 50  0001 C CNN
F 3 "" H 3400 6750 50  0001 C CNN
	1    3400 6750
	1    0    0    -1  
$EndComp
$Comp
L power:GNDREF #PWR0110
U 1 1 5FB666C3
P 4750 7300
F 0 "#PWR0110" H 4750 7050 50  0001 C CNN
F 1 "GNDREF" H 4700 7150 28  0001 C CNN
F 2 "" H 4750 7300 50  0001 C CNN
F 3 "" H 4750 7300 50  0001 C CNN
	1    4750 7300
	1    0    0    -1  
$EndComp
Text GLabel 2650 7000 2    28   Input ~ 0
SPI_MISO
Text GLabel 850  6300 0    28   Input ~ 0
SPI_CS
Text GLabel 850  6800 0    28   Input ~ 0
SPI_RDY
Wire Wire Line
	950  5700 850  5700
Wire Wire Line
	950  6200 850  6200
Wire Wire Line
	850  6300 950  6300
Wire Wire Line
	850  6800 950  6800
Wire Wire Line
	2550 7000 2650 7000
Wire Wire Line
	3950 6500 3950 7150
$Comp
L Device:R_US R5
U 1 1 60A35785
P 4300 4950
F 0 "R5" V 4400 4950 50  0000 C CNN
F 1 "270R" V 4200 4950 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 4340 4940 50  0001 C CNN
F 3 "~" H 4300 4950 50  0001 C CNN
	1    4300 4950
	0    -1   -1   0   
$EndComp
$Comp
L Device:LED D1
U 1 1 60A37B00
P 4000 4950
F 0 "D1" H 3900 5000 50  0000 C CNN
F 1 "LED" H 3993 5075 50  0000 C CNN
F 2 "LED_THT:LED_D3.0mm" H 4000 4950 50  0001 C CNN
F 3 "~" H 4000 4950 50  0001 C CNN
	1    4000 4950
	1    0    0    -1  
$EndComp
Text GLabel 4450 4950 2    28   Input ~ 0
SPI_CS
$Comp
L power:GNDREF #PWR01
U 1 1 60A3A8A6
P 3650 4950
F 0 "#PWR01" H 3650 4700 50  0001 C CNN
F 1 "GNDREF" H 3655 4777 50  0001 C CNN
F 2 "" H 3650 4950 50  0001 C CNN
F 3 "" H 3650 4950 50  0001 C CNN
	1    3650 4950
	1    0    0    -1  
$EndComp
Wire Wire Line
	3850 4950 3750 4950
NoConn ~ 2650 3250
NoConn ~ 2150 3650
NoConn ~ 2650 3550
NoConn ~ 2650 3650
NoConn ~ 2150 1450
NoConn ~ 2650 1950
NoConn ~ 2150 1950
NoConn ~ 2650 1450
NoConn ~ 2650 1550
$Comp
L power:+5V #PWR0115
U 1 1 616581A1
P 3250 7150
F 0 "#PWR0115" H 3250 7000 50  0001 C CNN
F 1 "+5V" H 3265 7323 50  0001 C CNN
F 2 "" H 3250 7150 50  0001 C CNN
F 3 "" H 3250 7150 50  0001 C CNN
	1    3250 7150
	1    0    0    -1  
$EndComp
NoConn ~ 4150 7050
NoConn ~ 4650 6950
NoConn ~ 4650 7050
$Comp
L power:GNDREF #PWR0107
U 1 1 61F2CAA8
P 650 2900
F 0 "#PWR0107" H 650 2650 50  0001 C CNN
F 1 "GNDREF" H 655 2727 50  0001 C CNN
F 2 "" H 650 2900 50  0001 C CNN
F 3 "" H 650 2900 50  0001 C CNN
	1    650  2900
	1    0    0    -1  
$EndComp
Wire Wire Line
	1450 3150 1450 2900
$Comp
L power:+5V #PWR0106
U 1 1 61F483D0
P 1550 4900
F 0 "#PWR0106" H 1550 4750 50  0001 C CNN
F 1 "+5V" H 1565 5073 50  0001 C CNN
F 2 "" H 1550 4900 50  0001 C CNN
F 3 "" H 1550 4900 50  0001 C CNN
	1    1550 4900
	1    0    0    -1  
$EndComp
NoConn ~ 1850 5000
NoConn ~ 1950 5000
Text Notes 7350 7500 0    59   ~ 12
MSXPi v1.0
Text Notes 8150 7650 0    59   ~ 12
July, 2020
Text Notes 10650 7650 0    59   ~ 12
2
Text Notes 7100 6700 0    59   ~ 12
Ronivon Costa
$Comp
L EPM3064ALC44-10:EPM3064ALC44-10 U1
U 1 1 5F21A6E6
P 6050 3500
F 0 "U1" H 6050 5265 50  0000 C CNN
F 1 "EPM3064ALC44-10" H 6050 5174 50  0000 C CNN
F 2 "MyFootprints:PLCC-44_THT-Socket" H 6050 3500 50  0001 L BNN
F 3 "Altera" H 6050 3500 50  0001 L BNN
F 4 "1549412" H 6050 3500 50  0001 L BNN "Field4"
F 5 "51R0503" H 6050 3500 50  0001 L BNN "Field5"
F 6 "EPM3064ALC44-10" H 6050 3500 50  0001 L BNN "Field6"
F 7 "44-PLCC" H 6050 3500 50  0001 L BNN "Field7"
	1    6050 3500
	1    0    0    -1  
$EndComp
Text GLabel 7100 3500 2    28   Input ~ 0
D3
Text GLabel 7100 3700 2    28   Input ~ 0
D7
Text GLabel 7100 3800 2    28   Input ~ 0
D1
Text GLabel 7100 4000 2    28   Input ~ 0
A2
Text GLabel 7100 4100 2    28   Input ~ 0
A4
Text GLabel 7100 4200 2    28   Input ~ 0
A3
Text GLabel 7100 4300 2    28   Input ~ 0
A5
Wire Wire Line
	7050 3500 7100 3500
Wire Wire Line
	7050 3700 7100 3700
Wire Wire Line
	7050 3800 7100 3800
Wire Wire Line
	7050 3900 7100 3900
Wire Wire Line
	7050 4000 7100 4000
Wire Wire Line
	7050 4100 7100 4100
Wire Wire Line
	7050 4200 7100 4200
Wire Wire Line
	7050 4300 7100 4300
Text GLabel 8300 3450 0    28   Input ~ 0
ROM_A14
Wire Wire Line
	7050 4500 7100 4500
Text GLabel 7100 2400 2    28   Input ~ 0
A6
Wire Wire Line
	7050 2400 7100 2400
Wire Wire Line
	7050 2500 7100 2500
Text GLabel 7100 2200 2    28   Input ~ 0
SPI_MOSI
Text GLabel 7100 2900 2    28   Input ~ 0
D2
Text GLabel 7100 3000 2    28   Input ~ 0
SPI_RDY
Text GLabel 7100 3100 2    28   Input ~ 0
D4
Text GLabel 7100 3300 2    28   Input ~ 0
D6
Wire Wire Line
	7050 3300 7100 3300
Wire Wire Line
	7050 3100 7100 3100
Wire Wire Line
	7050 3000 7100 3000
Wire Wire Line
	7050 2900 7100 2900
Wire Wire Line
	7050 2800 7100 2800
Text GLabel 7100 2300 2    28   Input ~ 0
BUSDIR
Wire Wire Line
	7050 2200 7100 2200
Text GLabel 7100 2100 2    28   Input ~ 0
A7
Wire Wire Line
	7050 2100 7100 2100
Text GLabel 7100 3200 2    28   Input ~ 0
WR
Wire Wire Line
	7050 3200 7100 3200
Text GLabel 7100 3400 2    28   Input ~ 0
IORQ
Text GLabel 7100 3600 2    28   Input ~ 0
SPI_MISO
Wire Wire Line
	7050 3400 7100 3400
Wire Wire Line
	7050 3600 7100 3600
Text GLabel 7100 4400 2    28   Input ~ 0
SPI_CS
Text GLabel 7100 4500 2    28   Input ~ 0
A1
Wire Wire Line
	7050 4400 7100 4400
Text GLabel 7100 4600 2    28   Input ~ 0
A0
Wire Wire Line
	7050 4600 7100 4600
NoConn ~ 2150 1650
Text GLabel 7100 3900 2    28   Input ~ 0
D5
Text GLabel 7100 2800 2    28   Input ~ 0
D0
Text GLabel 8300 1750 0    28   Input ~ 0
mem_ce
Text GLabel 6050 7300 2    28   Input ~ 0
ROM_A14
Text GLabel 5550 7300 0    28   Input ~ 0
A14
Text GLabel 5550 7400 0    28   Input ~ 0
A15
Text GLabel 5550 7000 0    28   Input ~ 0
CS1
Text GLabel 5550 7100 0    28   Input ~ 0
CS2
Text GLabel 5550 7200 0    28   Input ~ 0
CS12
Text GLabel 6050 7100 2    28   Input ~ 0
mem_oe
Text GLabel 8300 1850 0    28   Input ~ 0
mem_oe
Text GLabel 7100 2500 2    28   Input ~ 0
SPI_SCLK
Text GLabel 7100 4800 2    28   Input ~ 0
TDI
Text GLabel 7100 4900 2    28   Input ~ 0
TCK
Text GLabel 7100 5000 2    28   Input ~ 0
TDO
Text GLabel 7100 5100 2    28   Input ~ 0
TMS
Wire Wire Line
	7050 4800 7100 4800
Wire Wire Line
	7050 4900 7100 4900
Wire Wire Line
	7050 5000 7100 5000
Wire Wire Line
	7050 5100 7100 5100
$Comp
L power:+3.3V #PWR02
U 1 1 5F7E43E2
P 4950 2000
F 0 "#PWR02" H 4950 1850 50  0001 C CNN
F 1 "+3.3V" H 4950 2150 50  0001 C CNN
F 2 "" H 4950 2000 50  0001 C CNN
F 3 "" H 4950 2000 50  0001 C CNN
	1    4950 2000
	1    0    0    -1  
$EndComp
Wire Wire Line
	5050 2400 4950 2400
Wire Wire Line
	4950 2400 4950 2300
Wire Wire Line
	5050 2100 4950 2100
Connection ~ 4950 2100
Wire Wire Line
	4950 2100 4950 2000
Wire Wire Line
	5050 2200 4950 2200
Connection ~ 4950 2200
Wire Wire Line
	4950 2200 4950 2100
Wire Wire Line
	5050 2300 4950 2300
Connection ~ 4950 2300
Wire Wire Line
	4950 2300 4950 2200
$Comp
L power:GNDREF #PWR03
U 1 1 5F81EBBA
P 4950 3700
F 0 "#PWR03" H 4950 3450 50  0001 C CNN
F 1 "GNDREF" H 4955 3527 50  0001 C CNN
F 2 "" H 4950 3700 50  0001 C CNN
F 3 "" H 4950 3700 50  0001 C CNN
	1    4950 3700
	1    0    0    -1  
$EndComp
Wire Wire Line
	4950 3700 4950 3600
Wire Wire Line
	4950 3100 5050 3100
Wire Wire Line
	5050 3200 4950 3200
Connection ~ 4950 3200
Wire Wire Line
	4950 3200 4950 3100
Wire Wire Line
	5050 3300 4950 3300
Connection ~ 4950 3300
Wire Wire Line
	4950 3300 4950 3200
Wire Wire Line
	5050 3400 4950 3400
Connection ~ 4950 3400
Wire Wire Line
	4950 3400 4950 3300
Wire Wire Line
	5050 3500 4950 3500
Connection ~ 4950 3500
Wire Wire Line
	4950 3500 4950 3400
Connection ~ 4950 3600
Wire Wire Line
	4950 3600 4950 3500
$Comp
L power:+5V #PWR05
U 1 1 5F87C19A
P 8300 1400
F 0 "#PWR05" H 8300 1250 50  0001 C CNN
F 1 "+5V" H 8315 1573 50  0001 C CNN
F 2 "" H 8300 1400 50  0001 C CNN
F 3 "" H 8300 1400 50  0001 C CNN
	1    8300 1400
	1    0    0    -1  
$EndComp
$Comp
L power:GNDREF #PWR06
U 1 1 5F88F1DA
P 8300 3650
F 0 "#PWR06" H 8300 3400 50  0001 C CNN
F 1 "GNDREF" H 8250 3500 28  0001 C CNN
F 2 "" H 8300 3650 50  0001 C CNN
F 3 "" H 8300 3650 50  0001 C CNN
	1    8300 3650
	1    0    0    -1  
$EndComp
Text GLabel 850  6200 0    28   Input ~ 0
SPI_SCLK
$Comp
L Device:C_Small C3
U 1 1 5F98D5A8
P 3950 2100
F 0 "C3" V 3950 1900 50  0000 C CNN
F 1 "100nF" V 3950 2200 50  0000 L CNN
F 2 "Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm" H 3950 2100 50  0001 C CNN
F 3 "~" H 3950 2100 50  0001 C CNN
	1    3950 2100
	0    1    1    0   
$EndComp
$Comp
L Device:C_Small C4
U 1 1 5F98E818
P 3950 2350
F 0 "C4" V 3950 2150 50  0000 C CNN
F 1 "100nF" V 3900 2450 50  0000 L CNN
F 2 "Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm" H 3950 2350 50  0001 C CNN
F 3 "~" H 3950 2350 50  0001 C CNN
	1    3950 2350
	0    1    1    0   
$EndComp
$Comp
L Device:C_Small C5
U 1 1 5F98ED33
P 3950 2550
F 0 "C5" V 3950 2350 50  0000 C CNN
F 1 "100nF" V 3900 2650 50  0000 L CNN
F 2 "Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm" H 3950 2550 50  0001 C CNN
F 3 "~" H 3950 2550 50  0001 C CNN
	1    3950 2550
	0    1    1    0   
$EndComp
$Comp
L Device:C_Small C6
U 1 1 5F98EEC7
P 3950 2750
F 0 "C6" V 3950 2550 50  0000 C CNN
F 1 "100nF" V 3900 2850 50  0000 L CNN
F 2 "Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm" H 3950 2750 50  0001 C CNN
F 3 "~" H 3950 2750 50  0001 C CNN
	1    3950 2750
	0    1    1    0   
$EndComp
$Comp
L power:+3.3V #PWR07
U 1 1 5F98F8FA
P 3850 1950
F 0 "#PWR07" H 3850 1800 50  0001 C CNN
F 1 "+3.3V" H 3850 2100 50  0001 C CNN
F 2 "" H 3850 1950 50  0001 C CNN
F 3 "" H 3850 1950 50  0001 C CNN
	1    3850 1950
	1    0    0    -1  
$EndComp
Wire Wire Line
	4050 2100 4050 2350
Wire Wire Line
	4050 2350 4050 2550
Connection ~ 4050 2350
Wire Wire Line
	4050 2550 4050 2750
Connection ~ 4050 2550
Wire Wire Line
	3850 2750 3850 2550
Wire Wire Line
	3850 2350 3850 2100
Wire Wire Line
	3850 2550 3850 2350
Connection ~ 3850 2550
Connection ~ 3850 2350
Wire Wire Line
	3850 2100 3850 1950
Connection ~ 3850 2100
$Comp
L Device:CP1_Small C8
U 1 1 5FA39561
P 900 3150
F 0 "C8" H 800 3050 50  0000 L CNN
F 1 "100uF" H 900 3250 50  0000 L CNN
F 2 "Capacitor_THT:CP_Radial_D5.0mm_P2.50mm" H 900 3150 50  0001 C CNN
F 3 "~" H 900 3150 50  0001 C CNN
	1    900  3150
	-1   0    0    1   
$EndComp
Wire Wire Line
	650  2900 900  2900
Wire Wire Line
	900  3050 900  2900
Connection ~ 900  2900
Wire Wire Line
	900  2900 1450 2900
Wire Wire Line
	650  3550 900  3550
Wire Wire Line
	900  3250 900  3550
Connection ~ 900  3550
Wire Wire Line
	900  3550 1100 3550
Wire Wire Line
	3850 3600 3850 3650
Wire Wire Line
	4050 3650 4050 3700
$Comp
L power:GNDREF #PWR010
U 1 1 5FA16143
P 4050 3700
F 0 "#PWR010" H 4050 3450 50  0001 C CNN
F 1 "GNDREF" H 4000 3550 28  0001 C CNN
F 2 "" H 4050 3700 50  0001 C CNN
F 3 "" H 4050 3700 50  0001 C CNN
	1    4050 3700
	1    0    0    -1  
$EndComp
$Comp
L power:+5V #PWR09
U 1 1 5FA151FF
P 3850 3600
F 0 "#PWR09" H 3850 3450 50  0001 C CNN
F 1 "+5V" H 3865 3773 50  0001 C CNN
F 2 "" H 3850 3600 50  0001 C CNN
F 3 "" H 3850 3600 50  0001 C CNN
	1    3850 3600
	1    0    0    -1  
$EndComp
$Comp
L Device:C_Small C7
U 1 1 5FA1424E
P 3950 3650
F 0 "C7" V 3813 3650 50  0000 C CNN
F 1 "100nF" V 3900 3750 50  0000 L CNN
F 2 "Capacitor_THT:C_Disc_D3.0mm_W1.6mm_P2.50mm" H 3950 3650 50  0001 C CNN
F 3 "~" H 3950 3650 50  0001 C CNN
	1    3950 3650
	0    1    1    0   
$EndComp
Wire Wire Line
	3950 4300 3950 4350
Wire Wire Line
	4150 4350 4150 4400
$Comp
L power:GNDREF #PWR012
U 1 1 5FAD23D2
P 4150 4400
F 0 "#PWR012" H 4150 4150 50  0001 C CNN
F 1 "GNDREF" H 4100 4250 28  0001 C CNN
F 2 "" H 4150 4400 50  0001 C CNN
F 3 "" H 4150 4400 50  0001 C CNN
	1    4150 4400
	1    0    0    -1  
$EndComp
$Comp
L power:+5V #PWR011
U 1 1 5FAD23D8
P 3950 4300
F 0 "#PWR011" H 3950 4150 50  0001 C CNN
F 1 "+5V" H 3965 4473 50  0001 C CNN
F 2 "" H 3950 4300 50  0001 C CNN
F 3 "" H 3950 4300 50  0001 C CNN
	1    3950 4300
	1    0    0    -1  
$EndComp
$Comp
L Device:CP1_Small C9
U 1 1 5FAE3DF7
P 4050 4350
F 0 "C9" V 4050 4500 50  0000 L CNN
F 1 "100uF" V 4100 4050 50  0000 L CNN
F 2 "Capacitor_THT:CP_Radial_D5.0mm_P2.50mm" H 4050 4350 50  0001 C CNN
F 3 "~" H 4050 4350 50  0001 C CNN
	1    4050 4350
	0    -1   -1   0   
$EndComp
Text GLabel 5500 5700 0    28   Input ~ 0
SPI_CS
Text GLabel 5500 5800 0    28   Input ~ 0
SPI_MOSI
Text GLabel 5500 5900 0    28   Input ~ 0
SPI_MISO
Text GLabel 5500 6000 0    28   Input ~ 0
SPI_SCLK
Text GLabel 5500 6100 0    28   Input ~ 0
SPI_RDY
$Comp
L Device:R_US R6
U 1 1 5FAE81C3
P 5750 5700
F 0 "R6" V 5800 5850 50  0000 C CNN
F 1 "10K" V 5800 5550 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 5790 5690 50  0001 C CNN
F 3 "~" H 5750 5700 50  0001 C CNN
	1    5750 5700
	0    -1   -1   0   
$EndComp
$Comp
L Device:R_US R7
U 1 1 5FAE8BDE
P 5750 5800
F 0 "R7" V 5800 5950 50  0000 C CNN
F 1 "10K" V 5800 5650 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 5790 5790 50  0001 C CNN
F 3 "~" H 5750 5800 50  0001 C CNN
	1    5750 5800
	0    -1   -1   0   
$EndComp
$Comp
L Device:R_US R8
U 1 1 5FAE8E45
P 5750 5900
F 0 "R8" V 5800 6050 50  0000 C CNN
F 1 "10k" V 5800 5750 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 5790 5890 50  0001 C CNN
F 3 "~" H 5750 5900 50  0001 C CNN
	1    5750 5900
	0    -1   -1   0   
$EndComp
$Comp
L Device:R_US R9
U 1 1 5FAE9095
P 5750 6000
F 0 "R9" V 5800 6150 50  0000 C CNN
F 1 "10k" V 5800 5850 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 5790 5990 50  0001 C CNN
F 3 "~" H 5750 6000 50  0001 C CNN
	1    5750 6000
	0    -1   -1   0   
$EndComp
$Comp
L Device:R_US R10
U 1 1 5FAE934B
P 5750 6100
F 0 "R10" V 5800 6250 50  0000 C CNN
F 1 "10k" V 5800 5950 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 5790 6090 50  0001 C CNN
F 3 "~" H 5750 6100 50  0001 C CNN
	1    5750 6100
	0    -1   -1   0   
$EndComp
$Comp
L power:+3.3V #PWR013
U 1 1 5FAE953F
P 6050 5700
F 0 "#PWR013" H 6050 5550 50  0001 C CNN
F 1 "+3.3V" H 6050 5850 50  0001 C CNN
F 2 "" H 6050 5700 50  0001 C CNN
F 3 "" H 6050 5700 50  0001 C CNN
	1    6050 5700
	1    0    0    -1  
$EndComp
Wire Wire Line
	5900 5700 6050 5700
Wire Wire Line
	5900 6100 6050 6100
Wire Wire Line
	6050 6100 6050 6000
Connection ~ 6050 5700
Wire Wire Line
	5900 5800 6050 5800
Connection ~ 6050 5800
Wire Wire Line
	6050 5800 6050 5700
Wire Wire Line
	5900 5900 6050 5900
Connection ~ 6050 5900
Wire Wire Line
	6050 5900 6050 5800
Wire Wire Line
	5900 6000 6050 6000
Connection ~ 6050 6000
Wire Wire Line
	6050 6000 6050 5900
Wire Wire Line
	5600 5700 5500 5700
Wire Wire Line
	5600 5800 5500 5800
Wire Wire Line
	5600 5900 5500 5900
Wire Wire Line
	5600 6000 5500 6000
Wire Wire Line
	5600 6100 5500 6100
Wire Wire Line
	5050 2700 4950 2700
Wire Wire Line
	5050 2800 4950 2800
Wire Wire Line
	5050 2900 4950 2900
Connection ~ 4950 3100
Wire Wire Line
	4950 2700 4950 2800
Connection ~ 4950 2800
Wire Wire Line
	4950 2800 4950 2900
Connection ~ 4950 2900
Wire Wire Line
	4950 2900 4950 3100
Wire Wire Line
	4950 3600 5050 3600
NoConn ~ 5050 2600
Wire Wire Line
	7050 2300 7100 2300
Text GLabel 7100 2700 2    28   Input ~ 0
RD
Text GLabel 7100 2600 2    28   Input ~ 0
WAIT
Wire Wire Line
	7050 2600 7100 2600
Text GLabel 2100 1550 0    28   Input ~ 0
WAIT
Wire Wire Line
	2150 1550 2100 1550
Text GLabel 2100 3150 0    28   Input ~ 0
D7
Wire Wire Line
	2150 3150 2100 3150
Text GLabel 2100 3050 0    28   Input ~ 0
D5
Text GLabel 2100 2950 0    28   Input ~ 0
D3
Text GLabel 2100 2850 0    28   Input ~ 0
D1
Text GLabel 2100 2750 0    28   Input ~ 0
A5
Text GLabel 2100 2650 0    28   Input ~ 0
A3
Text GLabel 2100 2550 0    28   Input ~ 0
A1
Text GLabel 2100 2450 0    28   Input ~ 0
A14
Text GLabel 2100 2350 0    28   Input ~ 0
A12
Text GLabel 2100 2250 0    28   Input ~ 0
A7
Text GLabel 2100 2150 0    28   Input ~ 0
A11
Text GLabel 2100 2050 0    28   Input ~ 0
A9
Text GLabel 2100 1850 0    28   Input ~ 0
WR
Text GLabel 2100 1750 0    28   Input ~ 0
IORQ
Text GLabel 2700 1350 2    28   Input ~ 0
SLTSL
Text GLabel 2700 3150 2    28   Input ~ 0
D6
Text GLabel 2700 3050 2    28   Input ~ 0
D4
Text GLabel 2700 2950 2    28   Input ~ 0
D2
Text GLabel 2700 2850 2    28   Input ~ 0
D0
Text GLabel 2700 2750 2    28   Input ~ 0
A4
Text GLabel 2700 2650 2    28   Input ~ 0
A2
Text GLabel 2700 2550 2    28   Input ~ 0
A0
Text GLabel 2700 2450 2    28   Input ~ 0
A13
Text GLabel 2700 2350 2    28   Input ~ 0
A8
Text GLabel 2700 2250 2    28   Input ~ 0
A6
Text GLabel 2700 2150 2    28   Input ~ 0
A10
Text GLabel 2700 2050 2    28   Input ~ 0
A15
Text GLabel 2700 1850 2    28   Input ~ 0
RD
Text GLabel 2700 1650 2    28   Input ~ 0
BUSDIR
Wire Wire Line
	2650 1650 2700 1650
Wire Wire Line
	2650 1850 2700 1850
Wire Wire Line
	2650 2050 2700 2050
Wire Wire Line
	2650 2150 2700 2150
Wire Wire Line
	2650 2250 2700 2250
Wire Wire Line
	2150 2050 2100 2050
Wire Wire Line
	2150 2150 2100 2150
Wire Wire Line
	2150 2250 2100 2250
Wire Wire Line
	2150 2350 2100 2350
Wire Wire Line
	2150 2450 2100 2450
Wire Wire Line
	2150 2550 2100 2550
Wire Wire Line
	2150 2650 2100 2650
Wire Wire Line
	2150 2750 2100 2750
Wire Wire Line
	2150 2850 2100 2850
Wire Wire Line
	2150 2950 2100 2950
Wire Wire Line
	2150 3050 2100 3050
Wire Wire Line
	2650 3150 2700 3150
Wire Wire Line
	2650 3050 2700 3050
Wire Wire Line
	2650 2950 2700 2950
Wire Wire Line
	2650 2850 2700 2850
Wire Wire Line
	2650 2750 2700 2750
Wire Wire Line
	2650 2650 2700 2650
Wire Wire Line
	2650 2550 2700 2550
Wire Wire Line
	2650 2450 2700 2450
Wire Wire Line
	2650 2350 2700 2350
Wire Wire Line
	2150 1750 2100 1750
Wire Wire Line
	2150 1850 2100 1850
Text GLabel 9700 1450 2    28   Input ~ 0
D0
Text GLabel 9700 1550 2    28   Input ~ 0
D1
Text GLabel 9700 1650 2    28   Input ~ 0
D2
Text GLabel 9700 1750 2    28   Input ~ 0
D3
Text GLabel 9700 1850 2    28   Input ~ 0
D4
Text GLabel 9700 1950 2    28   Input ~ 0
D5
Text GLabel 9700 2050 2    28   Input ~ 0
D6
Text GLabel 9700 2150 2    28   Input ~ 0
D7
Text GLabel 8300 2050 0    28   Input ~ 0
A0
Text GLabel 8300 2150 0    28   Input ~ 0
A1
Text GLabel 8300 2250 0    28   Input ~ 0
A2
Text GLabel 8300 2350 0    28   Input ~ 0
A3
Text GLabel 8300 2450 0    28   Input ~ 0
A4
Text GLabel 8300 2550 0    28   Input ~ 0
A5
Text GLabel 8300 2650 0    28   Input ~ 0
A6
Text GLabel 8300 2750 0    28   Input ~ 0
A7
Text GLabel 8300 2850 0    28   Input ~ 0
A8
Text GLabel 8300 2950 0    28   Input ~ 0
A9
Text GLabel 8300 3050 0    28   Input ~ 0
A10
Text GLabel 8300 3150 0    28   Input ~ 0
A11
Text GLabel 8300 3250 0    28   Input ~ 0
A12
Text GLabel 8300 3350 0    28   Input ~ 0
A13
Wire Wire Line
	2650 1350 2700 1350
Wire Wire Line
	7050 2700 7100 2700
NoConn ~ 2650 1750
Text GLabel 2700 1250 2    28   Input ~ 0
CS2
Text GLabel 2100 1250 0    28   Input ~ 0
CS1
Text GLabel 2100 1350 0    28   Input ~ 0
CS12
Wire Wire Line
	2100 1250 2150 1250
Wire Wire Line
	2100 1350 2150 1350
Wire Wire Line
	2650 1250 2700 1250
Text GLabel 850  5700 0    28   Input ~ 0
SPI_MOSI
NoConn ~ 950  5400
NoConn ~ 950  5500
NoConn ~ 950  5800
NoConn ~ 950  5900
NoConn ~ 950  6500
NoConn ~ 950  6600
NoConn ~ 950  6700
NoConn ~ 950  7000
NoConn ~ 2550 7100
NoConn ~ 2550 6800
NoConn ~ 2550 6700
NoConn ~ 2550 6600
NoConn ~ 2550 6500
NoConn ~ 2550 6200
NoConn ~ 2550 6100
NoConn ~ 2550 6000
NoConn ~ 2550 5800
NoConn ~ 2550 5700
NoConn ~ 2550 5500
NoConn ~ 2550 5400
NoConn ~ 2550 6400
Text Label 8200 1300 0    50   ~ 0
+5V
Text Label 600  3100 0    50   ~ 0
GND
Text Label 3550 5150 0    50   ~ 0
GND
Text Label 1500 4750 0    50   ~ 0
+5V
Text Label 4900 3900 0    50   ~ 0
GND
Text Label 4000 3050 0    50   ~ 0
GND
Text Label 3750 1850 0    50   ~ 0
+3.3V
Text Label 4850 1900 0    50   ~ 0
+3.3V
Text Label 500  3450 0    50   ~ 0
+3.3V
Text Label 3150 7050 0    50   ~ 0
+5V
Text Label 4900 6600 0    50   ~ 0
+5V
Text Label 4700 7500 0    50   ~ 0
GND
Text Label 3350 6950 0    50   ~ 0
GND
Text Label 5950 5600 0    50   ~ 0
+3.3V
Text Label 4000 3900 0    50   ~ 0
GND
Text Label 3750 3500 0    50   ~ 0
+5V
Text Label 3850 4200 0    50   ~ 0
+5V
Text Label 4100 4600 0    50   ~ 0
GND
Text Label 2150 7750 0    50   ~ 0
GND
Wire Wire Line
	2100 3250 1450 3250
Connection ~ 2100 3250
Connection ~ 1450 3250
Text Label 8250 3850 0    50   ~ 0
GND
$Comp
L AT28C256:AT28C256-15PU U2
U 1 1 5F2D70DA
P 9000 2450
F 0 "U2" H 9000 3820 50  0000 C CNN
F 1 "AT28C256-15PU" H 9000 3729 50  0000 C CNN
F 2 "MyFootprints:DIP254P1524X482-28" H 9000 2450 50  0001 L BNN
F 3 "Paged Parallel EEPROM" H 9000 2450 50  0001 L BNN
F 4 "PDIP-28" H 9000 2450 50  0001 L BNN "Field4"
F 5 "AT28C256-15PU" H 9000 2450 50  0001 L BNN "Field5"
F 6 "1095782" H 9000 2450 50  0001 L BNN "Field6"
F 7 "ATMEL" H 9000 2450 50  0001 L BNN "Field7"
F 8 "96K6555" H 9000 2450 50  0001 L BNN "Field8"
	1    9000 2450
	1    0    0    -1  
$EndComp
$Comp
L Device:R_US R11
U 1 1 5F38A5D7
P 6750 5900
F 0 "R11" V 6800 6050 50  0000 C CNN
F 1 "10k" V 6800 5750 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 6790 5890 50  0001 C CNN
F 3 "~" H 6750 5900 50  0001 C CNN
	1    6750 5900
	0    -1   -1   0   
$EndComp
$Comp
L Device:R_US R12
U 1 1 5F38AA90
P 6750 6000
F 0 "R12" V 6800 6150 50  0000 C CNN
F 1 "10k" V 6800 5850 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 6790 5990 50  0001 C CNN
F 3 "~" H 6750 6000 50  0001 C CNN
	1    6750 6000
	0    -1   -1   0   
$EndComp
$Comp
L Device:R_US R13
U 1 1 5F38ACDC
P 6750 6100
F 0 "R13" V 6800 6250 50  0000 C CNN
F 1 "10k" V 6800 5950 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 6790 6090 50  0001 C CNN
F 3 "~" H 6750 6100 50  0001 C CNN
	1    6750 6100
	0    -1   -1   0   
$EndComp
Text GLabel 6500 5900 0    28   Input ~ 0
mem_we
Text GLabel 6500 6000 0    28   Input ~ 0
mem_ce
Text GLabel 6500 6100 0    28   Input ~ 0
mem_oe
Wire Wire Line
	6900 6100 7050 6100
Wire Wire Line
	6900 6000 7050 6000
Connection ~ 7050 6000
Wire Wire Line
	7050 6000 7050 6100
Wire Wire Line
	6900 5900 7050 5900
Wire Wire Line
	7050 5900 7050 6000
Wire Wire Line
	6600 5900 6500 5900
Wire Wire Line
	6600 6000 6500 6000
Wire Wire Line
	6600 6100 6500 6100
$Comp
L power:+5V #PWR014
U 1 1 5F3FDB48
P 7050 5900
F 0 "#PWR014" H 7050 5750 50  0001 C CNN
F 1 "+5V" H 7065 6073 50  0001 C CNN
F 2 "" H 7050 5900 50  0001 C CNN
F 3 "" H 7050 5900 50  0001 C CNN
	1    7050 5900
	1    0    0    -1  
$EndComp
Text Label 7000 5800 0    50   ~ 0
+5V
Text GLabel 5550 6900 0    28   Input ~ 0
WR
Text GLabel 5550 6800 0    28   Input ~ 0
SLTSL
Text GLabel 6050 6900 2    28   Input ~ 0
mem_we
Text GLabel 6050 6800 2    28   Input ~ 0
mem_ce
$Comp
L Connector_Generic:Conn_02x07_Odd_Even J3
U 1 1 5F45765B
P 5750 7100
F 0 "J3" H 5800 7617 50  0000 C CNN
F 1 "Conn_02x07_Odd_Even" H 5800 7526 50  0000 C CNN
F 2 "Connector_PinHeader_2.54mm:PinHeader_2x07_P2.54mm_Horizontal" H 5750 7100 50  0001 C CNN
F 3 "~" H 5750 7100 50  0001 C CNN
	1    5750 7100
	1    0    0    -1  
$EndComp
Text GLabel 8300 1650 0    28   Input ~ 0
mem_we
Wire Wire Line
	6050 7400 6050 7300
Wire Wire Line
	6050 7000 6050 7100
Wire Wire Line
	6050 7200 6050 7100
Connection ~ 6050 7100
Wire Wire Line
	8300 1450 8300 1400
Wire Wire Line
	1350 7600 1450 7600
Connection ~ 1450 7600
Wire Wire Line
	1450 7600 1550 7600
Connection ~ 1550 7600
Wire Wire Line
	1550 7600 1650 7600
Connection ~ 1650 7600
Wire Wire Line
	1650 7600 1750 7600
Connection ~ 1750 7600
Wire Wire Line
	1750 7600 1850 7600
Connection ~ 1850 7600
Wire Wire Line
	1850 7600 1950 7600
Connection ~ 1950 7600
Wire Wire Line
	1950 7600 2050 7600
Wire Wire Line
	2150 7600 2050 7600
Connection ~ 2050 7600
Connection ~ 7050 5900
Wire Wire Line
	3250 7150 3550 7150
Connection ~ 3550 7150
$Comp
L power:GNDREF #PWR08
U 1 1 5F98F041
P 4050 2850
F 0 "#PWR08" H 4050 2600 50  0001 C CNN
F 1 "GNDREF" H 4055 2677 50  0001 C CNN
F 2 "" H 4050 2850 50  0001 C CNN
F 3 "" H 4050 2850 50  0001 C CNN
	1    4050 2850
	1    0    0    -1  
$EndComp
Wire Wire Line
	4050 2850 4050 2750
Connection ~ 4050 2750
Wire Wire Line
	4900 6700 4900 6850
Wire Wire Line
	1750 3550 2100 3550
Wire Wire Line
	1750 3550 1750 3150
Wire Wire Line
	1750 3150 1700 3150
Connection ~ 1750 3550
Wire Wire Line
	1550 4900 1550 5000
Wire Wire Line
	1650 5000 1550 5000
Connection ~ 1550 5000
Text GLabel 850  6900 0    28   Input ~ 0
RPI_ON
Wire Wire Line
	950  6900 850  6900
$Comp
L Device:R_US R14
U 1 1 5F2F2379
P 4300 5300
F 0 "R14" V 4400 5300 50  0000 C CNN
F 1 "270R" V 4200 5300 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 4340 5290 50  0001 C CNN
F 3 "~" H 4300 5300 50  0001 C CNN
	1    4300 5300
	0    -1   -1   0   
$EndComp
Text GLabel 4450 5300 2    28   Input ~ 0
RPI_ON
$Comp
L Device:LED D2
U 1 1 5F2F2A5D
P 4000 5300
F 0 "D2" H 3900 5350 50  0000 C CNN
F 1 "LED" H 3993 5425 50  0000 C CNN
F 2 "LED_THT:LED_D3.0mm" H 4000 5300 50  0001 C CNN
F 3 "~" H 4000 5300 50  0001 C CNN
	1    4000 5300
	1    0    0    -1  
$EndComp
Wire Wire Line
	3850 5300 3750 5300
Wire Wire Line
	3750 5300 3750 4950
Connection ~ 3750 4950
Wire Wire Line
	3750 4950 3650 4950
$Comp
L Device:R_US R15
U 1 1 5F30064F
P 4300 5600
F 0 "R15" V 4400 5600 50  0000 C CNN
F 1 "270R" V 4200 5600 50  0000 C CNN
F 2 "Resistor_THT:R_Axial_DIN0204_L3.6mm_D1.6mm_P5.08mm_Horizontal" V 4340 5590 50  0001 C CNN
F 3 "~" H 4300 5600 50  0001 C CNN
	1    4300 5600
	0    -1   -1   0   
$EndComp
Text GLabel 4450 5600 2    28   Input ~ 0
RPI_BUSY
$Comp
L Device:LED D3
U 1 1 5F300C85
P 4000 5600
F 0 "D3" H 3900 5650 50  0000 C CNN
F 1 "LED" H 3993 5725 50  0000 C CNN
F 2 "LED_THT:LED_D3.0mm" H 4000 5600 50  0001 C CNN
F 3 "~" H 4000 5600 50  0001 C CNN
	1    4000 5600
	1    0    0    -1  
$EndComp
Wire Wire Line
	3850 5600 3750 5600
Wire Wire Line
	3750 5600 3750 5300
Connection ~ 3750 5300
Text GLabel 850  6100 0    28   Input ~ 0
RPI_BUSY
Wire Wire Line
	950  6100 850  6100
$EndSCHEMATC

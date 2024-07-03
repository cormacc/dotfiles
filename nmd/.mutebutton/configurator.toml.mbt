#This is a TOML document.
#Place this file in a subdirectory called ".mutebutton" in your home directory
#Uncomment and edit any of the lines below to replace the default parameters
#Where default values are listed below, the token "<CWD>" denotes the current working directory

#Path to search for CD firmware image
#Default :: string :: "<CWD>/cd"
ImagePath = "~/nmd/products/mbt/cd/firmware/dist/bootloadable/production"

#Path to search for IOD firmware image (string)
#Default :: string :: "<CWD>/iod"
#IodImagePath = "~/nmd/products/mbt/iod/firmware/dist/bootloadable/production"
IodImagePath = "~/Downloads/iod_firmware"

#GUI scale factor as float32
#Default :: float :: 1.0
Scale = 2.0

#Font Size (points)
#Default :: int :: 12
#FontSize = 14

#Number of balance steps
#Default :: int :: 6
#BalanceSteps = 12

#Set this to true to enable debug level logging
#Default :: bool :: false
#Debug = true

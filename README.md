# FHEM-Roomba980
FHEM-Module for robotic hoover Roomba980

## Installation and update in FHEM
Add the Roomba980 package in FHEM by putting the following into the FHEM command field:

```update add https://raw.githubusercontent.com/ThorstenPferdekaemper/FHEM-Roomba980/master/controls_roomba980.txt```

Then, your next ```update``` will install/update the Roomba980 module automatically. If you only want to install/update Roomba980 without updating the rest of your FHEM you can use

```update all roomba980``` 

or

```update force roomba980``` 

## Configuration in FHEM
Define a Roomba980 device:

```define myRoomba Roomba980```

Then press the "home" button on your Roomba until the WiFi symbol blinks. Then...

```set myRoomba discoverNewRoomba```

...and wait a minute. Don't forget "Save config".
Your Roomba should now be connected to FHEM and you can e.g. start it with

```set myRoomba start```

## Further information
Check this thread in the FHEM Forum: 
https://forum.fhem.de/index.php/topic,67632.0.html

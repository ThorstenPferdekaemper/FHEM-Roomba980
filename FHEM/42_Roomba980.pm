##############################################
#
# FHEM module for iRobot Roomba Series 600 .. 900
#
# 2018 Thorsten Pferdekaemper
# 2019 modified by Sebastian Liebert
#
#     This file is part of fhem.
#
#     Fhem is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published by
#     the Free Software Foundation, either version 2 of the License, or
#     (at your option) any later version.
#
#     Fhem is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#     along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# $Id: 42_Roomba980.pm 0010 2018-03-26 17:00:00Z ThorstenPferdekaemper $	
#
##############################################

my %sets = (
	"connect:noArg" => "","disconnect:noArg" => "",
	"start:noArg" => "" ,"stop:noArg" => "","pause:noArg" => "","resume:noArg" => "","dock:noArg" => "","off:noArg" => "",
	"cleanSchedule"=>"","discoverNewRoomba:noArg"=>"","getpass"=>"",
	"Schedule-on-Sun:none,start"=>"","Schedule-on-Mon:none,start"=>"","Schedule-on-Tue:none,start"=>"",
	"Schedule-on-Wed:none,start"=>"","Schedule-on-Thu:none,start"=>"","Schedule-on-Fri:none,start"=>"",
	"Schedule-on-Sat:none,start"=>"","Schedule-Time-Sun:time"=>"","Schedule-Time-Mon:time"=>"","Schedule-Time-Tue:time"=>"",
	"Schedule-Time-Wed:time"=>"","Schedule-Time-Thu:time"=>"","Schedule-Time-Fri:time"=>"","Schedule-Time-Sat:time"=>""
);

my %sets9xx = (
	"connect:noArg" => "","disconnect:noArg" => "","train:noArg" => "","evac:noArg" => "",
	"start:noArg" => "" ,"stop:noArg" => "","pause:noArg" => "","resume:noArg" => "","dock:noArg" => "","off:noArg" => "",  
	"carpetBoost:false,true" => "","vacHigh:false,true" => "","openOnly:false,true" => "","noAutoPasses:false,true" => "",  
	"twoPass:false,true" => "","binPause:false,true" => "","cleanSchedule"=>"","discoverNewRoomba:noArg"=>"","getpass"=>"",
	"Schedule-on-Sun:none,start"=>"","Schedule-on-Mon:none,start"=>"","Schedule-on-Tue:none,start"=>"",
	"Schedule-on-Wed:none,start"=>"","Schedule-on-Thu:none,start"=>"","Schedule-on-Fri:none,start"=>"",
	"Schedule-on-Sat:none,start"=>"","Schedule-Time-Sun:time"=>"","Schedule-Time-Mon:time"=>"","Schedule-Time-Tue:time"=>"",
	"Schedule-Time-Wed:time"=>"","Schedule-Time-Thu:time"=>"","Schedule-Time-Fri:time"=>"","Schedule-Time-Sat:time"=>""
);

my $setR = "default";

my $GetPwPacket = "f005efcc3b2900";

my $widgetOverrideDefault = "Schedule-on-Sun:iconRadio,808080,none,general_aus,start,general_an Schedule-on-Mon:iconRadio,808080,none,general_aus,start,general_an Schedule-on-Tue:iconRadio,808080,none,general_aus,start,general_an Schedule-on-Wed:iconRadio,808080,none,general_aus,start,general_an Schedule-on-Thu:iconRadio,808080,none,general_aus,start,general_an Schedule-on-Fri:iconRadio,808080,none,general_aus,start,general_an Schedule-on-Sat:iconRadio,808080,none,general_aus,start,general_an";

sub Roomba980_Initialize($) {

	my $hash = shift @_;

	require "$main::attr{global}{modpath}/FHEM/DevIo.pm";

	$hash->{ReadyFn} = "Roomba980::Ready";
	$hash->{ReadFn}  = "Roomba980::Read";
	$hash->{DefFn}    = "Roomba980::Define";
	$hash->{UndefFn}  = "Roomba980::Undef";
	$hash->{DeleteFn}  = "Roomba980::Delete";
	$hash->{SetFn}    = "Roomba980::Set";
	$hash->{AttrFn}   = "Roomba980::Attr";
	# $hash->{NotifyFn} = "Roomba980::Notify";
	$hash->{AttrList} = "timeout reconnecttime checkInterval alwaysconnected:0,1 disabled:0,1 ".$main::readingFnAttributes;
}

package Roomba980;

use strict;
use warnings;

use GPUtils qw(:all);

use Net::MQTT::Constants;
use Net::MQTT::Message;
use IO::Socket::INET;
use IO::Socket::SSL;
use JSON;

our %qos = map {qos_string($_) => $_} (MQTT_QOS_AT_MOST_ONCE,MQTT_QOS_AT_LEAST_ONCE,MQTT_QOS_EXACTLY_ONCE);

 BEGIN { 
 GP_Import(qw(
   CommandAttr
   CommandDeleteAttr
   CommandDeleteReading
   gettimeofday
   readingsSingleUpdate
   DevIo_SimpleWrite
   DevIo_SimpleRead
   DevIo_CloseDev
   DevIo_setStates
   RemoveInternalTimer
   InternalTimer
   AttrVal
   fhem
   Log3
   AssignIoPort
   getKeyValue
   setKeyValue
   DoTrigger
   readingsBeginUpdate
   readingsBulkUpdate
   readingsEndUpdate
   ReadingsVal
   ))
};

# Declare functions

sub Define($$);
sub Undef($);
sub Attr($$$$);
sub Delete($);
sub Set($@);
sub OpenDev($$$);
sub Start($);
sub Stop($);
sub Ready($);
sub Rename();
sub Init($);
sub Timer($);
sub prettyPrintReading($$);
sub messageToReadings($$;$);
sub processMessage($$);
sub Read;
sub send_connect($);
sub send_publish($@);
sub send_subscribe($@);
sub send_unsubscribe($@);
sub send_ping($);
sub send_disconnect($);
sub send_message($$$@);
sub apiCall ($$$);
sub topic_to_regexp($);
sub discovery($);
sub getpass($;$);

# functions

sub Define($$) {
	my ( $hash, $def ) = @_;
	$hash->{SSL} = 1;
	$hash->{timeout} = 60;
	$hash->{checkInterval} = 120;
	$hash->{reconnect_timer} = 0;
	my @devvek;
	if($hash->{DEF}){
		@devvek = split("[ \t]+", $hash->{DEF});
	}
	my $host;
	my $username = "";
	my $password = "";
	if(defined($devvek[0])){ $host 		= $devvek[0]; }
	if(defined($devvek[1])){ $username 	= $devvek[1]; }
	if(defined($devvek[2])){ $password 	= $devvek[2]; }	
	if($host){
		my $ip 		= $host;
		my $port 	= "8883";
		if($host =~ ":"){
			($ip, $port) = split(":",$host);
			$port 	=~ tr/0-9/./cd;
		}
		$ip 	=~ tr/0-9|\././cd;
		my $host = $ip . ":" . $port;
		$hash->{DeviceName} = $host;
	}else{
		readingsSingleUpdate($hash,"RoombaPW","For using discoverNewRoomba with automatic password-setup make sure, sync mode is enabled (WIFI-LED is green blinking). 
		\nFor enabling sync mode press home-button for about 2 seconds.",1);
	}
	my $name = $hash->{NAME};	
	if(AttrVal($hash->{NAME}, "widgetOverride", "na") eq "na"){
		eval { CommandAttr(undef,"$name widgetOverride $widgetOverrideDefault"); };
	}	
	if($host and $username and $password) {
		setKeyValue($name."_user",$username);
		setKeyValue($name."_pass",$password);
		$hash->{DEF} = $host;
	};	
	if ($main::init_done and $host) {
		# Create timer to connect the Roomba after 20 seconds
		InternalTimer(gettimeofday()+20, "Roomba980::Start", $hash);
	} else {
		return undef;
	}
}


sub Undef($) {
	my $hash = shift;
	Stop($hash);
	return undef;
}


sub Attr($$$$) {
	my ($command,$name,$attribute,$value) = @_;
  
	if(!defined($value)){
		$value = "";
	}

	Log3 ($name, 5, $name . "::Attr: Attr $attribute; Value $value");

	if ($command eq "set") {

		if ($attribute eq "checkInterval") {
			if (($value !~ /^\d*$/) || ($value < 10) || ($value > 3600)) {
				return "checkInterval is required in s (default: 60, min: 10, max: 3600)";
			}
		} elsif ($attribute eq "timeout") {
			if (($value !~ /^\d*$/) || ($value < 10) || ($value > 120)) {
				return "timeout is required in s (default: 60, min: 10, max: 120)";
			}
		}
		elsif ($attribute eq "reconnecttime") {
			if (($value !~ /^\d*$/) || ($value < 1) || ($value > 3600)) {
				return "reconnecttime is required in s (default: 60, min: 1, max: 3600)";
			}
		} elsif ($attribute eq "alwaysconnected") {
			# alwaysconnected on 1, enable on 0.
			if ($value ne "1" && $value ne "0") {
				return "alwaysconnected is required as 0|1";
			}      
		} elsif ($attribute eq "disable") {
			# Disable on 1, enable on 0.
			if ($value ne "1" && $value ne "0")
			{
				return "disable is required as 0|1";
			}      
		}
	}

	return undef;
}

sub Delete($) {
  my $hash = shift;
  my $name = $hash->{NAME};
  setKeyValue($name."_user",undef);
  setKeyValue($name."_pass",undef);
  return undef;
}


sub Set($@) {
	my ($hash, @a) = @_;
	return "Need at least one parameters" if(@a < 2);
	my $rseries = "na";
	if(defined($hash->{robotseries})){ 
		$rseries = $hash->{robotseries}; 
	}  
	my $sku = ReadingsVal($hash->{NAME}, "sku", 'undef');
	if($rseries ne $sku){
		$hash->{robotseries} = $sku;
	}
	if($sku =~ "R9" and $setR ne $sku){
		%sets = %sets9xx;
		$setR = $sku;
	}

	my @setlist = keys %sets;  
	my $cmd_available = 0;  
	for (my $i = 0; $i < @setlist; $i++) {
		$setlist[$i] = (split(/:/,$setlist[$i]))[0];	 
		if($setlist[$i] eq $a[1]){$cmd_available = 1;}
	}

	return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets) if($cmd_available == 0);
	#  if(!defined($sets{$a[1]}));
	my $command = $a[1];
	my $value = $a[2];

	COMMAND_HANDLER: {
		$command eq "connect" and do {
			Start($hash);
			last;
		};
		$command eq "disconnect" and do {
			Stop($hash);
			last;
		};
		# virtual off command
		$command eq "off" and do {			
			$hash->{reconnect_timer} = 60; # sobald der User aktiv ist, wird der reconnect auf 60s verlängert.
			apiCall($hash,"cmd","stop");
			select(undef,undef,undef,2);
			apiCall($hash,"cmd","dock");
			last;
		};
		$command eq "discoverNewRoomba" and do {			
			discovery($hash);			
			last;			
		};
		$command eq "getpass" and do {
			if($value){
				getpass($hash,$value);
			}else{
				return "IP und Port vergessen! (Bsp.: 192.168.178.2:8883)";
			}
			last;
		};
		(grep { $command eq $_ } ("start","stop","pause","resume","dock","train","evac")) and do {
			$hash->{reconnect_timer} = 60; # sobald der User aktiv ist, wird der reconnect auf 60s verlängert.
			apiCall($hash,"cmd",$command);
			last;
		};
		(grep { $command eq $_ } ("carpetBoost","vacHigh","openOnly","noAutoPasses","twoPass","binPause","cleanSchedule",
		"Schedule-Time-Sun","Schedule-Time-Mon","Schedule-Time-Tue","Schedule-Time-Wed","Schedule-Time-Thu","Schedule-Time-Fri",
		"Schedule-Time-Sat","Schedule-on-Sun","Schedule-on-Mon","Schedule-on-Tue","Schedule-on-Wed","Schedule-on-Thu",
		"Schedule-on-Fri","Schedule-on-Sat")) and do {
			$hash->{reconnect_timer} = 60; # sobald der User aktiv ist, wird der reconnect auf 60s verlängert.
			$command = $command . " " . $value;		
			apiCall($hash,"delta",$command);		
			last;
		};
	};
}


sub OpenDev($$$){
	my ($hash, $reopen, $initfn) = @_;
	my $dev = $hash->{DeviceName};
	my $name = $hash->{NAME};
	my $po;
	my $nextOpenDelay = ($hash->{nextOpenDelay} ? $hash->{nextOpenDelay} : 60);

	my $doTailWork = sub {
		DevIo_setStates($hash, "opened");
		my $ret;
		if($initfn) {
			my $hadFD = defined($hash->{FD});
			no strict "refs";
			$ret = &$initfn($hash);
			use strict "refs";
		if($ret) {
			if($hadFD && !defined($hash->{FD})) { # Forum #54732 / ser2net
				DevIo_Disconnected($hash);
				$hash->{NEXT_OPEN} = time() + $nextOpenDelay;
			} else {
			DevIo_CloseDev($hash);
			Log3 $name, 1, "Cannot init $dev, ignoring it ($name)";
			}
		}
	}
	if(!$ret) {
		my $l = $hash->{devioLoglevel}; # Forum #61970
		if($reopen) {
			Log3 $name, ($l ? $l:3), "$dev reappeared ($name)";
		} else {
			Log3 $name, ($l ? $l:3), "$name device opened" if(!$hash->{DevioText});
		}
	}
	DoTrigger($name, "CONNECTED") if($reopen && !$ret);
	return undef;
	};  #doTailWork  
	if($hash->{DevIoJustClosed}) {
		delete $hash->{DevIoJustClosed};
		return undef;
	}
	$hash->{PARTIAL} = "";
	Log3 $name, 3, ($hash->{DevioText} ? $hash->{DevioText} : "Opening"). " $name device $dev" if(!$reopen);

  # This part is called every time the timeout (5sec) is expired _OR_
  # somebody is communicating over another TCP connection. As the connect
    # for non-existent devices has a delay of 3 sec, we are sitting all the
    # time in this connect. NEXT_OPEN tries to avoid this problem.
	if($hash->{NEXT_OPEN} && time() < $hash->{NEXT_OPEN}) {
		return undef; 
	}
	delete($main::readyfnlist{"$name.$dev"});
	my $timeout = $hash->{TIMEOUT} ? $hash->{TIMEOUT} : 3;
	my $doTcpTail = sub($) {
		my ($conn) = @_;
		if($conn) {
			delete($hash->{NEXT_OPEN});
			$conn->setsockopt("SOL_SOCKET", "SO_KEEPALIVE", 1) if(defined($conn));
		} else {
			Log3 $name, 3, "Can't connect to $dev: $!" if(!$reopen && $!);
			$main::readyfnlist{"$name.$dev"} = $hash;
			DevIo_setStates($hash, "disconnected");
			$hash->{NEXT_OPEN} = time() + $nextOpenDelay;
			return 0;
		}
		$hash->{TCPDev} = $conn;
		$hash->{FD} = $conn->fileno();
		$main::selectlist{"$name.$dev"} = $hash;
		return 1;
	};
	my $conn = 	IO::Socket::SSL->new(PeerAddr => $dev, # '192.168.178.40:8883',
				Timeout => $timeout,
				SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
				SSL_cipher_list => 'DEFAULT:!DH');
	if($conn){ # Cleanup RoombaPW after successfull connect
		if(exists $hash->{READINGS}{RoombaPW}){
			eval {
				delete $hash->{READINGS}{RoombaPW};
			};
		}
	}
    return "" if(!&$doTcpTail($conn)); # no callback: no doCb
	
	return &$doTailWork();
}

sub Start($) {
  my $hash = shift;
  DevIo_CloseDev($hash);
  return OpenDev($hash, 0, "Roomba980::Init");
}

sub Stop($) {
	my $hash = shift;
	my $alwaysconnected = AttrVal($hash->{NAME}, "alwaysconnected", "1");
	my $disabled = AttrVal($hash->{NAME}, "disabled", "0");
	if($alwaysconnected eq "0" && $disabled eq "0" && $hash->{reconnect_timer} > $hash->{timeout}){
		InternalTimer(gettimeofday()+1, "Roomba980::Timer", $hash, 0);
		return;
	}
	send_disconnect($hash);
	DevIo_CloseDev($hash);
	RemoveInternalTimer($hash);
	readingsSingleUpdate($hash,"connection","disconnected",1);
	if($hash->{timeout} > $hash->{checkInterval}){
		$hash->{reconnect_timer} = $hash->{timeout};
	}else{
		$hash->{reconnect_timer} = $hash->{checkInterval};
	}
	if($alwaysconnected eq "0" && $disabled eq "0"){
		my $reconnecttime = AttrVal($hash->{NAME}, "reconnecttime", "60");
		InternalTimer(gettimeofday()+$reconnecttime, "Roomba980::Start", $hash, 0);
		Log3($hash->{NAME},3,"Roomba980: auto-reconnect in ".$reconnecttime." seconds.");
	}
}

sub Ready($) {
	my $hash = shift;
	return OpenDev($hash, 1, "Roomba980::Init") if($hash->{STATE} eq "disconnected");
}

# TODO: is this registered?
sub Rename() {
	my ($new,$old) = @_;
	setKeyValue($new."_user",getKeyValue($old."_user"));
	setKeyValue($new."_pass",getKeyValue($old."_pass"));
	
	setKeyValue($old."_user",undef);
	setKeyValue($old."_pass",undef);
	return undef;
}

sub Init($) {
	my $hash = shift;
	send_connect($hash);
	readingsSingleUpdate($hash,"connection","connecting",1);
	$hash->{ping_received}=1;
	Timer($hash);
	return undef;
}

sub Timer($) {
	my $hash = shift;
	my $name = $hash->{NAME};
	$hash->{timeout} = AttrVal ($name, 'timeout', 60);
	$hash->{checkInterval} = AttrVal ($name, 'checkInterval', 60);
	RemoveInternalTimer($hash);
	readingsSingleUpdate($hash,"connection","timed-out",1) unless $hash->{ping_received};
	$hash->{ping_received} = 0;
	my $alwaysconnected = AttrVal($hash->{NAME}, "alwaysconnected", "1");
	my $disabled = AttrVal($hash->{NAME}, "disabled", "0");
	my $stopin = $hash->{reconnect_timer};
	$hash->{reconnect_timer} = $hash->{reconnect_timer} - $hash->{timeout};	
	if($hash->{reconnect_timer} < 0){$hash->{reconnect_timer} = 0;}
	if($alwaysconnected eq "0" && $disabled eq "0" && $hash->{reconnect_timer} <= $hash->{timeout}){
		InternalTimer(gettimeofday()+$stopin, "Roomba980::Stop", $hash, 0);
	}else{
		InternalTimer(gettimeofday()+$hash->{timeout}, "Roomba980::Timer", $hash, 0);
	}
	send_ping($hash);
}

# prettyPrintReading
# converts time, hex strings and ip addresses
sub prettyPrintReading($$){
    my ($reading,$value) = @_;
	# ip addresses
	my @ipfields = ("netinfo-addr", "netinfo-dns1", "netinfo-dns2", "netinfo-gw", "netinfo-mask","wlcfg-addr","wlcfg-dns1","wlcfg-dns2","wlcfg-gw","wlcfg-mask");
    if (grep { $reading eq $_ } @ipfields) {
        return ($value >> 24).".".(($value >> 16) & 255).".".(($value >> 8) & 255).".".($value & 255);
    };	
	# times
	my @timefields = ("lastCommand-time","utctime");
    if (grep { $reading eq $_ } @timefields) {
        return main::FmtDateTime($value);
    };	
	# hex string 
	if($reading eq "wlcfg-ssid"){
	    return pack("H*",$value);
	};
	# no change
	return $value;
}

sub messageToReadings($$;$){
    my ($hash,$msgpart,$prefix) = @_;
	my $type = ref($msgpart);
    if($type eq "HASH") {
	    foreach my $key (keys %{$msgpart}) {
		    messageToReadings($hash,$msgpart->{$key},$prefix ? $prefix."-".$key : $key);
		};
		return;
	};
	if($type eq "ARRAY") {
	    # TODO: error handling... my $rv = readings...
		readingsBulkUpdate($hash,$prefix,JSON::encode_json($msgpart));
		
		#cleanSchedule-cycle 
		if($prefix eq "cleanSchedule-cycle"){
			if(defined($$msgpart[0])){readingsBulkUpdate($hash,"Schedule-on-Sun",$$msgpart[0]);}
			if(defined($$msgpart[1])){readingsBulkUpdate($hash,"Schedule-on-Mon",$$msgpart[1]);}
			if(defined($$msgpart[2])){readingsBulkUpdate($hash,"Schedule-on-Tue",$$msgpart[2]);}
			if(defined($$msgpart[3])){readingsBulkUpdate($hash,"Schedule-on-Wed",$$msgpart[3]);}
			if(defined($$msgpart[4])){readingsBulkUpdate($hash,"Schedule-on-Thu",$$msgpart[4]);}
			if(defined($$msgpart[5])){readingsBulkUpdate($hash,"Schedule-on-Fri",$$msgpart[5]);}
			if(defined($$msgpart[6])){readingsBulkUpdate($hash,"Schedule-on-Sat",$$msgpart[6]);}
		}
		if($prefix eq "cleanSchedule-h"){
			$hash->{cleanScheduleh} = $msgpart;
		}
		if($prefix eq "cleanSchedule-m"){
			$hash->{cleanSchedulem} = $msgpart;
		}
		if($hash->{cleanSchedulem} and $hash->{cleanScheduleh}){
			my $msgparth = $hash->{cleanScheduleh};
			my $msgpart = $hash->{cleanSchedulem};
			if(defined($$msgpart[0]) and defined($$msgparth[0])){
				if($$msgpart[0]<10){readingsBulkUpdate($hash,"Schedule-Time-Sun",$$msgparth[0] . ":0" . $$msgpart[0]);
				}else{readingsBulkUpdate($hash,"Schedule-Time-Sun",$$msgparth[0] . ":" . $$msgpart[0]);}}
			if(defined($$msgpart[1]) and defined($$msgparth[1])){
				if($$msgpart[1]<10){readingsBulkUpdate($hash,"Schedule-Time-Mon",$$msgparth[1] . ":0" . $$msgpart[1]);
				}else{readingsBulkUpdate($hash,"Schedule-Time-Mon",$$msgparth[1] . ":" . $$msgpart[1]);}}
			if(defined($$msgpart[2]) and defined($$msgparth[2])){
				if($$msgpart[2]<10){readingsBulkUpdate($hash,"Schedule-Time-Tue",$$msgparth[2] . ":0" . $$msgpart[2]);
				}else{readingsBulkUpdate($hash,"Schedule-Time-Tue",$$msgparth[2] . ":" . $$msgpart[2]);}}
			if(defined($$msgpart[3]) and defined($$msgparth[3])){
				if($$msgpart[3]<10){readingsBulkUpdate($hash,"Schedule-Time-Wed",$$msgparth[3] . ":0" . $$msgpart[3]);
				}else{readingsBulkUpdate($hash,"Schedule-Time-Wed",$$msgparth[3] . ":" . $$msgpart[3]);}}
			if(defined($$msgpart[4]) and defined($$msgparth[4])){
				if($$msgpart[4]<10){readingsBulkUpdate($hash,"Schedule-Time-Thu",$$msgparth[4] . ":0" . $$msgpart[4]);
				}else{readingsBulkUpdate($hash,"Schedule-Time-Thu",$$msgparth[4] . ":" . $$msgpart[4]);}}
			if(defined($$msgpart[5]) and defined($$msgparth[5])){
				if($$msgpart[5]<10){readingsBulkUpdate($hash,"Schedule-Time-Fri",$$msgparth[5] . ":0" . $$msgpart[5]);
				}else{readingsBulkUpdate($hash,"Schedule-Time-Fri",$$msgparth[5] . ":" . $$msgpart[5]);}}
			if(defined($$msgpart[6]) and defined($$msgparth[6])){
				if($$msgpart[6]<10){readingsBulkUpdate($hash,"Schedule-Time-Sat",$$msgparth[6] . ":0" . $$msgpart[6]);
				}else{readingsBulkUpdate($hash,"Schedule-Time-Sat",$$msgparth[6] . ":" . $$msgpart[6]);}}			
		}		
		
		return;
	};
    # now it should be a normal "field"
	# my $rv = TODO: error handling
	readingsBulkUpdate($hash,$prefix,prettyPrintReading($prefix,$msgpart));
};

sub processMessage($$){
    my ($hash, $msgtext) = @_;
	# message empty?
	if(!$msgtext){
	    Log3($hash->{NAME},3, "Received empty message");
		return;
	};
	# decode to Perl
	my $msg = 0;
	eval {
		$msg = JSON::decode_json($msgtext);
	} or do {	
	    Log3($hash->{NAME},3, "Could not decode message: $@ --> $msgtext"); 
		return;
	};
	if(!$msg){
	    Log3($hash->{NAME},3, "Could not decode ".$msgtext);
	    return;
	};
	# all known events start with "state->reported"
	if(!defined($msg->{state}{reported})){
		Log3($hash->{NAME},3, "state:reported missing ".$msgtext);
		return;
	};
	if(ref($msg->{state}{reported}) ne "HASH"){
		Log3($hash->{NAME},3, "No hash in ".$msgtext);
		return;
	};
	# now we should be able to find readings
	readingsBeginUpdate($hash);
    messageToReadings($hash,$msg->{state}{reported});
    # TODO: really trigger for all readings?
    readingsEndUpdate($hash,1);
	eval {	delete($hash->{cleanScheduleh});	};
	eval {	delete($hash->{cleanSchedulem}); 	};
};

sub Read {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $buf = DevIo_SimpleRead($hash);
	return undef unless $buf;
	$hash->{buf} .= $buf;
	
	# every new message starts with zero and needs exact one char(0) leading the message content: 	
	# data in front of the zero followed by the last chr(0) in the string $hash->{buf} has to be deleted for preventing fhem from unintended shutdown!
				
	my $position  = index($hash->{buf}, "0");
	my $position_neu = $position;
	my $nul = chr(0);
	my $posnul_neu = index($hash->{buf}, $nul);
	my $posnul	 = $posnul_neu;

	while ( $posnul_neu >= 0 ){
		$posnul	 = $posnul_neu;
		$posnul_neu = index($hash->{buf}, $nul,$posnul+1);
	}    
	while ( $position_neu >= 0 && $position_neu < $posnul){
		$position 		= $position_neu;
		$position_neu 	= index($hash->{buf}, "0", $position+1);
	}
	if($position > 0 && $position < $posnul){
		Log3($name,3,"MQTT $name insufficient message with more than one char(0): ".$hash->{buf} );
		$hash->{buf}    = substr $hash->{buf}, $position;
		Log3($name,3,"MQTT $name found new message starting at char-position ".$position." : ".$hash->{buf} );
	}

	while (my $mqtt = eval { Net::MQTT::Message->new_from_bytes($hash->{buf},1) } ) {
		my $message_type = "ERROR";	
		if($@) {
			$mqtt->string() = "ERROR";
			Log3 ($name, 3, "Received rubbish: $@" );
			# this means it has crashed, i.e. most likely there is
			# nothing taken from buf. I.e. we need to clear it to avoid
			# endless loop.
			$hash->{buf} = "";
			last;
		}else{
			eval {
				$message_type = $mqtt->message_type();
			} or do {
				Log3 ($name, 3, "Reveiced rubbish (message type): $@" );
				# maybe there is another message which works
				next;
			};
		};
		# an empty message won't produce an error, it just means that we are ready for now
		last unless $mqtt;
		# get message type  
#		my $message_type;
		Log3($name,5,"MQTT $name message received: [$message_type] ".$mqtt->string());

		if($message_type == MQTT_CONNACK) {
			readingsSingleUpdate($hash,"connection","connected",1);
			# TODO: Error messages? Seems that CONNACK also comes when no authorization or so
			# TODO: send message queue?
			# foreach my $message_id (keys %{$hash->{messages}}) {
			  # my $msg = $hash->{messages}->{$message_id}->{message};
			  # $msg->{dup} = 1;
			  # DevIo_SimpleWrite($hash,$msg->bytes,undef);
			# }
			# TODO: why last?
			last;
		};

		if($message_type == MQTT_PUBLISH) {
			my $topic = $mqtt->topic();
			# GP_ForallClients($hash,sub {
			  # my $client = shift;
			  # Log3($client->{NAME},5,"publish received for $topic, ".$mqtt->message());
			  # if (grep { $topic =~ $_ } @{$client->{subscribeExpr}}) {
				# readingsSingleUpdate($client,"transmission-state","incoming publish received",1);
				# if ($client->{TYPE} eq "MQTT_DEVICE") {
				  # MQTT::DEVICE::onmessage($client,$topic,$mqtt->message());
				# } else {
				  # MQTT::BRIDGE::onmessage($client,$topic,$mqtt->message());
				# }
			  # };
			# },undef);
			if (my $qos = $mqtt->qos() > MQTT_QOS_AT_MOST_ONCE) {
			  my $message_id = $mqtt->message_id();
			  if ($qos == MQTT_QOS_AT_LEAST_ONCE) {
				send_message($hash, message_type => MQTT_PUBACK, message_id => $message_id);
			  } else {
				send_message($hash, message_type => MQTT_PUBREC, message_id => $message_id);
			  }
			}
			processMessage($hash,$mqtt->message());
			#readingsSingleUpdate($hash,"lastTopic",$topic,1);
			#readingsSingleUpdate($hash,"lastContent",$mqtt->message(),1);
			# TODO: Why last?
			last;
		};

		  # $message_type == MQTT_PUBACK and do {
			# my $message_id = $mqtt->message_id();
			# GP_ForallClients($hash,sub {
			  # my $client = shift;
			  # if ($client->{message_ids}->{$message_id}) {
				# readingsSingleUpdate($client,"transmission-state","outgoing publish acknowledged",1);
				# delete $client->{message_ids}->{$message_id};
			  # };
			# },undef);
			# delete $hash->{messages}->{$message_id}; #QoS Level 1: at_least_once handling
			# last;
		  # };

		if($message_type == MQTT_PUBREC) {
			my $message_id = $mqtt->message_id();
			# GP_ForallClients($hash,sub {
			  # my $client = shift;
			  # if ($client->{message_ids}->{$message_id}) {
				# readingsSingleUpdate($client,"transmission-state","outgoing publish received",1);
			  # };
			# },undef);
			send_message($hash, message_type => MQTT_PUBREL, message_id => $message_id); #QoS Level 2: exactly_once handling
			# TODO: Why last?
			last;
		};

		if($message_type == MQTT_PUBREL) {
			my $message_id = $mqtt->message_id();
			# GP_ForallClients($hash,sub {
			  # my $client = shift;
			  # if ($client->{message_ids}->{$message_id}) {
				# readingsSingleUpdate($client,"transmission-state","incoming publish released",1);
				# delete $client->{message_ids}->{$message_id};
			  # };
			# },undef);
			send_message($hash, message_type => MQTT_PUBCOMP, message_id => $message_id); #QoS Level 2: exactly_once handling
			# delete $hash->{messages}->{$message_id};
			# TODO: Why last?
			last;
		};

		  # $message_type == MQTT_PUBCOMP and do {
			# my $message_id = $mqtt->message_id();
			# GP_ForallClients($hash,sub {
			  # my $client = shift;
			  # if ($client->{message_ids}->{$message_id}) {
				# readingsSingleUpdate($client,"transmission-state","outgoing publish completed",1);
				# delete $client->{message_ids}->{$message_id};
			  # };
			# },undef);
			# delete $hash->{messages}->{$message_id}; #QoS Level 2: exactly_once handling
			# last;
		  # };

		  # $message_type == MQTT_SUBACK and do {
			# my $message_id = $mqtt->message_id();
			# GP_ForallClients($hash,sub {
			  # my $client = shift;
			  # if ($client->{message_ids}->{$message_id}) {
				# readingsSingleUpdate($client,"transmission-state","subscription acknowledged",1);
				# delete $client->{message_ids}->{$message_id};
			  # };
			# },undef);
			# delete $hash->{messages}->{$message_id}; #QoS Level 1: at_least_once handling
			# last;
		  # };

		  # $message_type == MQTT_UNSUBACK and do {
			# my $message_id = $mqtt->message_id();
			# GP_ForallClients($hash,sub {
			  # my $client = shift;
			  # if ($client->{message_ids}->{$message_id}) {
				# readingsSingleUpdate($client,"transmission-state","unsubscription acknowledged",1);
				# delete $client->{message_ids}->{$message_id};
			  # };
			# },undef);
			# delete $hash->{messages}->{$message_id}; #QoS Level 1: at_least_once handling
			# last;
		  # };

		if($message_type == MQTT_PINGRESP){
			$hash->{ping_received} = 1;
			readingsSingleUpdate($hash,"connection","active",1);
			# TODO: Why last?
			last;
		};

#      Log3($hash->{NAME},4,"Roomba980::Read '$hash->{NAME}' unexpected message type '".message_type_string($message_type)."'");
		if($message_type eq "ERROR"){
			Log3($hash->{NAME},4,"Roomba980::Read '$hash->{NAME}' ERROR: unknown message type");
			last;
		}else{
			Log3($hash->{NAME},4,"Roomba980::Read '$hash->{NAME}' unexpected message type '".message_type_string($message_type)."'");
			last;
		}
    }
  return undef;
};

sub send_connect($) {
	my $hash = shift;
	my $name = $hash->{NAME};
	my $user = getKeyValue($name."_user");
	my $pass = getKeyValue($name."_pass");
	return send_message($hash, message_type => MQTT_CONNECT, keep_alive_timer => $hash->{timeout}, 
                             user_name => $user, password => $pass, client_id => $user, 
							 protocol_name => "MQTT", protocol_version => 4);
};

sub send_publish($@) {
	my ($hash,%msg) = @_;
	if ($msg{qos} == MQTT_QOS_AT_MOST_ONCE) {
		send_message(shift, message_type => MQTT_PUBLISH, %msg);
		return undef;
	} else {
		my $msgid = $hash->{msgid}++;
		send_message(shift, message_type => MQTT_PUBLISH, message_id => $msgid, %msg);
		return $msgid;
	}
};

sub send_subscribe($@) {
	my $hash = shift;
	my $msgid = $hash->{msgid}++;
	send_message($hash, message_type => MQTT_SUBSCRIBE, message_id => $msgid, qos => MQTT_QOS_AT_LEAST_ONCE, @_);
	return $msgid;
};

sub send_unsubscribe($@) {
	my $hash = shift;
	my $msgid = $hash->{msgid}++;
	send_message($hash, message_type => MQTT_UNSUBSCRIBE, message_id => $msgid, qos => MQTT_QOS_AT_LEAST_ONCE, @_);
	return $msgid;
};

sub send_ping($) {
	return send_message(shift, message_type => MQTT_PINGREQ);
};

sub send_disconnect($) {
	return send_message(shift, message_type => MQTT_DISCONNECT);
};

sub send_message($$$@) {
	my ($hash,%msg) = @_;
	my $name = $hash->{NAME};
	my $message = undef;
	eval {
		$message = Net::MQTT::Message->new(%msg);
	} or do {
		Log3 ($name, 1, "Error creating message to send: $@" );
		return;
	};
	Log3($name,5,"MQTT $name message sent: ".$message->string());
	if (defined $msg{message_id}) {
		$hash->{messages}->{$msg{message_id}} = {
			message => $message,
			timeout => gettimeofday()+$hash->{timeout},
		};
	};
	eval {
		DevIo_SimpleWrite($hash,$message->bytes,undef);
	};
	if($@) {
		Log3 ($name, 1, "Error sending message: $@" );		
	};
};

sub apiCall ($$$) {
    my ($hash, $topic, $command) = @_;
	my $message = "na";
	if($topic eq "delta"){	
		my ($cmd,$val) = split(/ /,$command);	
		if(defined($val)){
			my @cvec;
			my @hvec;
			my @mvec;
			my %weekdays = ("Sun"=>"0", "Mon"=>"1", "Tue"=>"2", "Wed"=>"3", "Thu"=>"4", "Fri"=>"5", "Sat"=>"6");
			if($cmd =~ "Schedule"){
				# "cleanSchedule":{"cycle":["none","start","start","start","start","start","none"],"h":[9,15,16,16,16,14,9],"m":[0,0,30,30,30,30,0]}
				# none,none,start,start,start,start,none;9,15,16,16,16,14,9;0,0,30,30,30,30,0
				my $defcycle = ReadingsVal($hash->{NAME}, "cleanSchedule-cycle", '["none","none","none","none","none","none","none"]');
				my $defh 	 = ReadingsVal($hash->{NAME}, "cleanSchedule-h", '[9,9,9,9,9,9,9]');
				my $defm 	 = ReadingsVal($hash->{NAME}, "cleanSchedule-m", '[0,0,0,0,0,0,0]');
				$defcycle =~ tr/\"|\[|\]//d;
				$defh =~ tr/\"|\[|\]//d;
				$defm =~ tr/\"|\[|\]//d;
				@cvec 	= split(/,/,$defcycle);
				@hvec 	= split(/,/,$defh);
				@mvec 	= split(/,/,$defm);			
				for (my $i = 0; $i < 7; $i++) {
					$hvec[$i] += 0;
					$mvec[$i] += 0;
				}			
			}
			if($cmd eq "cleanSchedule"){
				my @valgroup 	= split(/;/,$val);
				if(!defined($valgroup[0])){$valgroup[0] = "empty";}
				if(!defined($valgroup[1])){$valgroup[1] = "empty";}
				if(!defined($valgroup[2])){$valgroup[2] = "empty";}
				my @newcvec 		= split(/,/,$valgroup[0]);
				my @newhvec 		= split(/,/,$valgroup[1]);
				my @newmvec 		= split(/,/,$valgroup[2]);			
				for (my $i = 0; $i < 7; $i++) {
					if(defined($newcvec[$i]) and $valgroup[0] ne "empty"){	$cvec[$i] 	= $newcvec[$i];}
					if(defined($newhvec[$i]) and $valgroup[1] ne "empty"){	$hvec[$i] 	= $newhvec[$i];}
					if(defined($newmvec[$i]) and $valgroup[2] ne "empty"){	$mvec[$i] 	= $newmvec[$i];}
					$hvec[$i] += 0;
					$mvec[$i] += 0;
				}
			}elsif($cmd =~ "Schedule"){
				my @cmdvec 	= split(/-/,$cmd);
				my $day = "na";
				if(defined($cmdvec[2])){ $day = $cmdvec[2]; }		
				if( $cmd =~ "Time" and exists $weekdays{$day}){
					$val 	=~ tr/0-9|:/./cd;		
					my @valgroup 	= split(/:/,$val);
					if(defined($valgroup[0])){ $hvec[$weekdays{$day}] = $valgroup[0] + 0; }
					if(defined($valgroup[1])){ $mvec[$weekdays{$day}] = $valgroup[1] + 0; }
				}elsif($cmd =~ "on" and exists $weekdays{$day} and ( $val eq "none" or $val eq "start" ) ){
					$cvec[$weekdays{$day}] = $val;
				}else{
					return "Wrong set Schedule command! Use set Schedule-on-<weekday> [none|start] or Schedule-Time-<weekday> <hh:min> .";
				}		
				$cmd = "cleanSchedule";
			}
			if($cmd eq "cleanSchedule"){
				$message = JSON::encode_json({state => {$cmd => {cycle => [$cvec[0],$cvec[1],$cvec[2],$cvec[3],$cvec[4],$cvec[5],$cvec[6]], h => [$hvec[0],$hvec[1],$hvec[2],$hvec[3],$hvec[4],$hvec[5],$hvec[6]], m => [$mvec[0],$mvec[1],$mvec[2],$mvec[3],$mvec[4],$mvec[5],$mvec[6]]}}, time => time(), initiator => "localApp" });
			}else{
				$message = JSON::encode_json({state => {$cmd => $val}, time => time(), initiator => "localApp" });
				$message =~ s/"true"/true/gm;
				$message =~ s/"false"/false/gm;	
			}
		} 
	}else{
		$message = JSON::encode_json({command => $command, time => time(), initiator => "localApp"});
	}
	if($message ne "na"){
		my %msg = (topic => $topic, message => $message, 
				   qos => MQTT_QOS_AT_MOST_ONCE);
		send_publish($hash,%msg);
	}
};

sub topic_to_regexp($) {
	my $t = shift;
	$t =~ s|#$|.\*|;
	$t =~ s|\/\.\*$|.\*|;
	$t =~ s|\/|\\\/|g;
	$t =~ s|(\+)([^+]*$)|(+)$2|;
	$t =~ s|\+|[^\/]+|g;
	return "^$t\$";
};

sub discovery($){
    my ($hash) = @_;
    $DB::single = 1;

	use Socket qw(:all);
	my $name = $hash->{NAME};	
	my $sock = $hash->{DiscSock};	
	
	if(!$sock){
		$sock = eval { new IO::Socket::INET(
					Proto => 'udp', 
					Type => SOCK_DGRAM,
					Timeout => 60,
					Broadcast => 1,
					Blocking => 0) };
		if ($@) { 
			Log3($name,2,"DISCOVERY $name : No Roomba found! ");
		}else{
			$sock->sockopt(SO_BROADCAST, 1);
			$sock->sockopt(SO_REUSEADDR, 1);	
			my $localport = $sock->sockport();	
			my $data = "irobotmcs";
			my $broadcastAddr = sockaddr_in( 5678, INADDR_BROADCAST );
			send( $sock, $data, 0,  $broadcastAddr );
			$hash->{DiscSock} = $sock;
			RemoveInternalTimer($hash);			
			InternalTimer(gettimeofday()+3, "Roomba980::discovery", $hash, 0);			
		}
	}else{
		my $datagram = "";
		my $i = 999;
		my $answerlength = 0;		
		my $discovered = "";
		my $robots = "";
		my $countrobots = 0;
		while ($i > 0 && $answerlength < 10) {
			sysread($sock,$datagram,999);
			$answerlength = length($datagram) ;		
			if($datagram =~ "Roomba"){
				my $hostname = "Roomba";				
				my $host;				
				my $blid;
				my $robotname;
				my $data = JSON::decode_json($datagram);
				if(!$data){
					Log3($hash->{NAME},3, "Could not decode ".$datagram);
					return;
				}					
				if($data->{"robotname"} and $data->{"ip"} and $data->{"hostname"}){
					if(length($discovered) > 0){$discovered = $discovered . "\n";}
					$hostname 	=  $data->{"hostname"};
					$host 		=  $data->{"ip"};
					if(!($host =~ ":")){$host = $host . ":8883";}
					$robotname 	= $data->{"robotname"};
					$blid 		= (split(/-/,$hostname))[1];
					$discovered = $discovered . $robotname . " " . $host . " " . $blid;
					if(length($robots) > 0){$robots = $robots . ",";}
					$robots = $robots . $robotname;
					$hash->{DiscRoombas}{$robotname}{host} = $host;
					$hash->{DiscRoombas}{$robotname}{blid} = $blid;
					$countrobots = $countrobots + 1;
				}
				readingsSingleUpdate($hash,"discoveredRoomba",$discovered,1);
			}
			$i = $i - 1;
		}
		$sock->close();
		delete($hash->{DiscSock}); 
		my @list_keys = keys %sets;
		for (@list_keys) {
			if($_ =~ "getpass"){ 
				delete($sets{$_}); 
			}
		}		
		if(!$hash->{DeviceName} and $countrobots == 1){
			$hash->{Robotname} = $robots;
			InternalTimer(gettimeofday()+3, "Roomba980::getpass", $hash);
		}
		$robots = "getpass:" . $robots;
		$sets{$robots} = "";		
	}
};

sub getpass($;$){
    my ($hash,$host) = @_;	
	my $robotname;
	my $name = $hash->{NAME};
	if(!$host and $hash->{Robotname}){ 
		$host = $hash->{Robotname}; 
	}	
	if($host and !$hash->{GetPassConn}){		
		if($hash->{DiscRoombas}{$host}){
			$robotname = $host;
			$host = $hash->{DiscRoombas}{$robotname}{host};
			$hash->{Robotname} = $robotname;
		}elsif(length($host)>8){
			my $ip 		= $host;
			my $port 	= "8883";
			if($host =~ ":"){
				($ip, $port) = split(":",$host);
				$port 	=~ tr/0-9/./cd;
			}
			$ip 	=~ tr/0-9|\././cd;
			$host = $ip . ":" . $port;
		}
		Log3($hash->{NAME},2, "GetPass: connecting to $host ");
		my $conn = IO::Socket::SSL->new(PeerAddr => $host, 
				   Timeout => 3,
				   SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
				   SSL_cipher_list => 'DEFAULT:!DH');
		if($conn) {		
			$conn->blocking(0);			
			my $data = pack('H*', $GetPwPacket);			
			print $conn $data;
			$hash->{GetPassConn} = $conn;				
			RemoveInternalTimer($hash);			
			InternalTimer(gettimeofday()+3, "Roomba980::getpass", $hash, 0);
		}else{		
			Log3($hash->{NAME},3, "GetPass connection error");
			if($!) {
				Log3($hash->{NAME},3, "GetPass ".$!);
			};
			if($SSL_ERROR) {
				Log3($hash->{NAME},3, "GetPass ".$SSL_ERROR);
			};
			readingsSingleUpdate($hash,"RoombaPW","connection refused. Make sure, sync mode is enabled (WIFI-LED is green blinking). For enabling press home-button for about 2 seconds.",1);				
		}	
	}elsif($hash->{GetPassConn}){	
		my $data = pack('H*', $GetPwPacket);			
		my $j = length($data);		
		my $conn = $hash->{GetPassConn};			
		$hash->{GetPassConn} = 0;			
		my $i = 99;
		my $out = "";		
		while ($i > 0){		
			$i = $i - 1;		
			my $n = sysread( $conn,my $buf,1);			
			if(!$n){ 				
				$i = 0; 				
			}else{
				if($i < (99 - $j) ){
					$out = $out . $buf;			
				}
			}			
		}		
		if( length($out) > 1 ){
			readingsSingleUpdate($hash,"RoombaPW",$out,1);	
			if(!$hash->{DeviceName} and $hash->{Robotname}){
				my $robotname = $hash->{Robotname};
				# Create timer to connect the Roomba after 20 seconds
				$hash->{DEF} = $hash->{DiscRoombas}{$robotname}{host};			
				$hash->{DeviceName} = $hash->{DiscRoombas}{$robotname}{host};				
				setKeyValue($name."_user",$hash->{DiscRoombas}{$robotname}{blid});
				setKeyValue($name."_pass",$out);
				InternalTimer(gettimeofday()+20, "Roomba980::Start", $hash);
				delete($hash->{Robotname}); 
			}
		}else{
			readingsSingleUpdate($hash,"RoombaPW","no data, please try again! Make sure, sync mode is enabled (WIFI-LED is green blinking). For enabling press home-button for about 2 seconds.",1);		
		}		
		close($conn);	
		delete($hash->{GetPassConn}); 		
	}else{
		return "IP und Port vergessen! (Bsp.: 192.168.178.2:8883)";
	}	
}

1;

=pod
=item summary    roomba device to control and manage Roomba 600..900 series
=item summary_DE modul zur Integration von Roomba 600 bis 900 
=begin html

<a name="Roomba980"></a>
<h3>Roomba980</h3>
<ul>
	<br>

	<a name"Roomba980define"></a>
	<strong>Define</strong>
	<ul>
		<code>define &lt;name&gt; Roomba980 &lt;ip[:8883]&gt; &lt;blid&frasl;username&gt; &lt;passwort&gt; </code>
		<br>
		<br>
		Defines a roomba980 device to control and manage roomba-cleaners.
		<br>
		<br>
		Example:
		<BLOCKQUOTE> define Roomba Roomba980 192.168.1.54:8883 3132B21051915310 :1:1234394129:jmaBV1QzGNv8PM7f </BLOCKQUOTE>

	</ul>
  <br>	
	<a name"Roomba980sets"></a>
	<strong>Settings</strong>
	<ul>
		<li>connect 		<BLOCKQUOTE>- connects module to roomba, and will try to kepp connection alive. </BLOCKQUOTE>
		</li>
		<li>disconnect 		<BLOCKQUOTE>- disconnect module from roomba, only automatic reconnecting if alwaysconnected is set to "0". </BLOCKQUOTE>
		</li>
		<li>start, stop, pause, resume, dock, off <BLOCKQUOTE>- control commands for roomba</BLOCKQUOTE>
		</li>
		<li>carpetBoost 	<BLOCKQUOTE>- [false,true]  <br>(for setCarpetBoostAuto: true, for setCarpetBoostPerformance: false, for setCarpetBoostEco: false)</BLOCKQUOTE>
		</li>
		<li>vacHigh			<BLOCKQUOTE>- [false,true]  <br>(for setCarpetBoostAuto: false, for setCarpetBoostPerformance: true, for setCarpetBoostEco: false)</BLOCKQUOTE>
		</li>
		<li>openOnly		<BLOCKQUOTE>- [false,true]  <br>(true for EdgeClean only)</BLOCKQUOTE>
		</li>
		<li>noAutoPasses	<BLOCKQUOTE>- [false,true]  <br>(for setCleaningPassesAuto: false, for setCleaningPassesOne: true, for setCleaningPassesTwo: true)</BLOCKQUOTE>
		</li>
		<li>twoPass			<BLOCKQUOTE>- [false,true]  <br>(for setCleaningPassesAuto: false, for setCleaningPassesOne: false, for setCleaningPassesTwo: true)</BLOCKQUOTE>
		</li>
		<li>binPause		<BLOCKQUOTE>- [false,true]  <br>(true for AlwaysFinish Off)</BLOCKQUOTE>
		</li>
		<li>cleanSchedule	<BLOCKQUOTE>- chages setup for cleanSchedule in following order: [sun, mon, tue, wed, thu, fri, sat] for enabling [none|start], hour and minute. 
			<br> e.g.: none,none,start,start,start,start,none;9,15,16,16,16,14,9;0,0,30,30,30,30,0 </BLOCKQUOTE>
		</li>
		<li>discoverNewRoomba<BLOCKQUOTE>- searches for Roombas in your LAN and will list them under reading discoveredRoomba. <br> It's helpfull in finding out roombas ip:port and blid. </BLOCKQUOTE>
		</li>
		<li>getpass			<BLOCKQUOTE>- [ip:port] discoveres roombas password. <br>Make sure, sync mode is enabled (WIFI-LED is green blinking). <br>For enabling press home-button for about 2 seconds. </BLOCKQUOTE>
		</li>
		
	</ul>
  <br>
	<a name"Roomba980attributes"></a>
	<strong>Attributes</strong>
	<ul>
		<li>checkInterval <BLOCKQUOTE>- changes default setting for checkInterval (default is 60 seconds). 
			<br>The module checks every checkInterval seconds, if connection is alive and starts reconnect, if not.</BLOCKQUOTE>
		</li>
		<li>timeout <BLOCKQUOTE>- changes default setting for timeout (default is 60 seconds)</BLOCKQUOTE>
		</li>
		<li>alwaysconnected	<BLOCKQUOTE>- [0,1] it allows to connect only for getting new robotstate, if it does no cyclic broadcast. <br>(default is "1")</BLOCKQUOTE>
		</li>
		<li>reconnecttime	<BLOCKQUOTE>- time in seconds for automatic reconnect if alwaysconnected is set to "0" and disabled is set to "0". <br>(default is 60 seconds)</BLOCKQUOTE>
		</li>
		<li>disabled	<BLOCKQUOTE>- [0,1] it allows to stop automatic reconnecting if alwaysconnected is set to "0". <br>(default is "1")</BLOCKQUOTE>
		</li>
		
	</ul>
</ul>
<br>

=end html
=begin html_DE

<a name="Roomba980"></a>
<h3>Roomba980</h3>
<ul>
	<br>

	<a name"Roomba980define"></a>
	<strong>Define</strong>
	<ul>
		<code>define &lt;name&gt; Roomba980 &lt;ip[:8883]&gt; &lt;blid&frasl;username&gt; &lt;passwort&gt; </code>
		<br>
		<br>
		Erstellt ein roomba980 device zum steuern und konfigurieren eines Roomba-Staubsaugers.
		<br>
		<br>
		Besipiel:
		<BLOCKQUOTE> define Roomba Roomba980 192.168.1.54:8883 3132B21051915310 :1:1234394129:jmaBV1QzGNv8PM7f </BLOCKQUOTE>

	</ul>
  <br>	
	<a name"Roomba980sets"></a>
	<strong>Settings</strong>
	<ul>
		<li>connect 		<BLOCKQUOTE>- Verbindet das Modul mit Roomba, und wird versuchen die Verbindung offen zu halten. </BLOCKQUOTE>
		</li>
		<li>disconnect 		<BLOCKQUOTE>- Trennt die Verbindung mit Roomba und verbindet nur automatisch wieder neu, wenn alwaysconnected auf "0" steht.</BLOCKQUOTE>
		</li>
		<li>start, stop, pause, resume, dock, off <BLOCKQUOTE>- Steuerbefehle des Roomba.</BLOCKQUOTE>
		</li>
		<li>carpetBoost 	<BLOCKQUOTE>- [false,true]  <br>(f&uuml;r setCarpetBoostAuto: true, f&uuml;r setCarpetBoostPerformance: false, f&uuml;r setCarpetBoostEco: false)</BLOCKQUOTE>
		</li>
		<li>vacHigh			<BLOCKQUOTE>- [false,true]  <br>(f&uuml;r setCarpetBoostAuto: false, f&uuml;r setCarpetBoostPerformance: true, f&uuml;r setCarpetBoostEco: false)</BLOCKQUOTE>
		</li>
		<li>openOnly		<BLOCKQUOTE>- [false,true]  <br>(true f&uuml;r EdgeClean only)</BLOCKQUOTE>
		</li>
		<li>noAutoPasses	<BLOCKQUOTE>- [false,true]  <br>(f&uuml;r setCleaningPassesAuto: false, f&uuml;r setCleaningPassesOne: true, f&uuml;r setCleaningPassesTwo: true)</BLOCKQUOTE>
		</li>
		<li>twoPass			<BLOCKQUOTE>- [false,true]  <br>(f&uuml;r setCleaningPassesAuto: false, f&uuml;r setCleaningPassesOne: false, f&uuml;r setCleaningPassesTwo: true)</BLOCKQUOTE>
		</li>
		<li>binPause		<BLOCKQUOTE>- [false,true]  <br>(true f&uuml;r AlwaysFinish Off)</BLOCKQUOTE>
		</li>
		<li>cleanSchedule	<BLOCKQUOTE>- &Auml;ndert Einstellungen f&uuml;r cleanSchedule in folgender Reihenfolge der Wochentage: [sun, mon, tue, wed, thu, fri, sat] zum Aktivieren/Deaktivieren [none|start], danach die Stunden-Werte, zum Schluss die Minutenwerte. 
			<br> z.B.: none,none,start,start,start,start,none;9,15,16,16,16,14,9;0,0,30,30,30,30,0 </BLOCKQUOTE>
		</li>
		<li>discoverNewRoomba<BLOCKQUOTE>- Sucht nach Roombas im LAN und will legt diese im reading discoveredRoomba ab. <br> Es liefert sowohl IP und Port als auch die Blid vom Roomba. </BLOCKQUOTE>
		</li>
		<li>getpass			<BLOCKQUOTE>- [ip:port] Ermittelt das aktuelle Passwort vom Roomba. <br>Dazu muss der Sync-Mode aktiv sein (WIFI-LED blinkt gr&uuml;n). <br>Zum Aktivieren bitte den Home-Button f&uuml;r ca. 2 Sekunden dr&uuml;cken. </BLOCKQUOTE>
		</li>
		
	</ul>
  <br>
	<a name"Roomba980attributes"></a>
	<strong>Attribute</strong>
	<ul>
		<li>checkInterval <BLOCKQUOTE>- &Auml;ndert die Einstellungen f&uuml;r checkInterval. Das ist nur f&uuml;r Roombas erforderlich, die kein zyklisches Update aller Statuswerte versenden oder, um den Roomba bewusst zu trennen und damit Strom zu sparen. (default ist 60 Sekunden). 
			<br>Das Modul f&uuml;hrt im Abstand von checkInterval Sekunden einen reconnect durch.</BLOCKQUOTE>
		</li>
		<li>timeout <BLOCKQUOTE>- Einstellung f&uuml;r timeout (default ist 60 Sekunden)</BLOCKQUOTE>
		</li>
		<li>alwaysconnected	<BLOCKQUOTE>- [0,1] "0" ist nur f&uuml;r Roombas erforderlich, die kein zyklisches Update aller Statuswerte versenden oder, um den Roomba bewusst zu trennen und damit Strom zu sparen. <br>(default is "1")</BLOCKQUOTE>
		</li>
		<li>reconnecttime	<BLOCKQUOTE>- Zeit in Sekunden für automatischen reconnect. Nur wirksam, falls alwaysconnected "0" gesetzt wurde. <br>(default ist 60 Sekunden)</BLOCKQUOTE>
		</li>
		<li>disabled	<BLOCKQUOTE>- [0,1] "1" um automatischen reconnect zu verhinden, falls alwaysconnected "0" gesetzt wurde. <br>(default is "1")</BLOCKQUOTE>
		</li>
		
	</ul>
</ul>
<br>

=end html_DE
=cut
##############################################
#
# FHEM module for iRobot Roomba 980
#
# 2017 Thorsten Pferdekaemper
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
# $Id: $
#
##############################################

my %sets = (
  "connect" => "",
  "disconnect" => "",
  "start" => "" ,"stop" => "","pause" => "","resume" => "","dock" => ""
);


sub Roomba980_Initialize($) {

  my $hash = shift @_;

  require "$main::attr{global}{modpath}/FHEM/DevIo.pm";

  $hash->{ReadyFn} = "Roomba980::Ready";
  $hash->{ReadFn}  = "Roomba980::Read";
  $hash->{DefFn}    = "Roomba980::Define";
  $hash->{UndefFn}  = "Roomba980::Undef";
  $hash->{SetFn}    = "Roomba980::Set";
#  $hash->{NotifyFn} = "MQTT::Notify";
#  $hash->{AttrList} = "keep-alive ".$main::readingFnAttributes;
}

package Roomba980;

# use Exporter ('import');
# @EXPORT = ();
# @EXPORT_OK = qw(send_publish send_subscribe send_unsubscribe client_attr client_subscribe_topic client_unsubscribe_topic topic_to_regexp);
# %EXPORT_TAGS = (all => [@EXPORT_OK]);

use strict;
use warnings;

use GPUtils qw(:all);

use Net::MQTT::Constants;
use Net::MQTT::Message;
use IO::Socket::INET;
use IO::Socket::SSL;
use JSON::XS;

our %qos = map {qos_string($_) => $_} (MQTT_QOS_AT_MOST_ONCE,MQTT_QOS_AT_LEAST_ONCE,MQTT_QOS_EXACTLY_ONCE);

 BEGIN {GP_Import(qw(
   gettimeofday
   readingsSingleUpdate
   DevIo_SimpleWrite
   DevIo_SimpleRead
   DevIo_CloseDev
   DevIo_setStates
   RemoveInternalTimer
   InternalTimer
   AttrVal
   Log3
   AssignIoPort
   getKeyValue
   setKeyValue
   DoTrigger
   readingsBeginUpdate
   readingsBulkUpdate
   readingsEndUpdate
   ))};

sub Define($$) {
  my ( $hash, $def ) = @_;

#  $hash->{NOTIFYDEV} = "global";
#  $hash->{msgid} = 1;
  $hash->{timeout} = 60;
#  $hash->{messages} = {};

  my ($host,$username,$password) = split("[ \t]+", $hash->{DEF});
  $hash->{DeviceName} = $host;
  
  my $name = $hash->{NAME};
  my $user = getKeyValue($name."_user");
  my $pass = getKeyValue($name."_pass");

  setKeyValue($name."_user",$username) unless(defined($user));
  setKeyValue($name."_pass",$password) unless(defined($pass));

  $hash->{DEF} = $host;
  $hash->{SSL} = 1;

# TODO: The following should maybe wait  
  if ($main::init_done) {
    return Start($hash);
  } else {
    return undef;
  }
}


sub Undef($) {
  my $hash = shift;
  Stop($hash);
  my $name = $hash->{NAME};
  setKeyValue($name."_user",undef);
  setKeyValue($name."_pass",undef);
  return undef;
}

sub Set($@) {
  my ($hash, @a) = @_;
  return "Need at least one parameters" if(@a < 2);
  return "Unknown argument $a[1], choose one of " . join(" ", sort keys %sets)
    if(!defined($sets{$a[1]}));
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
	(grep { $command eq $_ } ("start","stop","pause","resume","dock")) and do {
	    apiCall($hash,"cmd",$command);
		last;
	}	
  };
}

# TODO
# sub Notify($$) {
  # my ($hash,$dev) = @_;
  # if( grep(m/^(INITIALIZED|REREADCFG)$/, @{$dev->{CHANGED}}) ) {
    # Start($hash);
  # } elsif( grep(m/^SAVE$/, @{$dev->{CHANGED}}) ) {
  # }
# }

# sub Attr($$$$) {
  # my ($command,$name,$attribute,$value) = @_;

  # my $hash = $main::defs{$name};
  # ATTRIBUTE_HANDLER: {
    # $attribute eq "keep-alive" and do {
      # if ($command eq "set") {
        # $hash->{timeout} = $value;
      # } else {
        # $hash->{timeout} = 60;
      # }
      # if ($main::init_done) {
        # $hash->{ping_received}=1;
        # Timer($hash);
      # };
      # last;
    # };
  # };
# }



sub OpenDev($$$)
{
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
        Log3 $name, ($l ? $l:1), "$dev reappeared ($name)";
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
  Log3 $name, 3, ($hash->{DevioText} ? $hash->{DevioText} : "Opening").
       " $name device $dev" if(!$reopen);

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

	my $conn = IO::Socket::SSL->new(PeerAddr => $dev, # '192.168.178.40:8883',
	           Timeout => $timeout,
               SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE);

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
  send_disconnect($hash);
  DevIo_CloseDev($hash);
  RemoveInternalTimer($hash);
  readingsSingleUpdate($hash,"connection","disconnected",1);
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
  RemoveInternalTimer($hash);
  readingsSingleUpdate($hash,"connection","timed-out",1) unless $hash->{ping_received};
  $hash->{ping_received} = 0;
  InternalTimer(gettimeofday()+$hash->{timeout}, "Roomba980::Timer", $hash, 0);
  send_ping($hash);
}


# prettyPrintReading
# converts time, hex strings and ip addresses
sub prettyPrintReading($$){
    my ($reading,$value) = @_;
	# ip addresses
	my @ipfields = ("netinfo-addr", "netinfo-dns1", "netinfo-dns2", "netinfo-gw", "netinfo-mask");
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
		readingsBulkUpdate($hash,$prefix,JSON::XS::encode_json($msgpart));
		return;
	};
    # now it should be a normal "field"
	# my $rv = TODO: error handling
	readingsBulkUpdate($hash,$prefix,prettyPrintReading($prefix,$msgpart));
};


# processMessage
# Processes one received message
# and converts it to readings
sub processMessage($$){
    my ($hash, $msgtext) = @_;
	# message empty?
	if(!$msgtext){
	    Log3($hash->{NAME},3, "Received empty message");
		return;
	};
	# decode to Perl
	my $msg = JSON::XS::decode_json($msgtext);
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
	
};



sub Read {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $buf = DevIo_SimpleRead($hash);
  return undef unless $buf;
  $hash->{buf} .= $buf;
  while (my $mqtt = Net::MQTT::Message->new_from_bytes($hash->{buf},1)) {

    my $message_type = $mqtt->message_type();

    Log3($name,5,"MQTT $name message received: ".$mqtt->string());

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

      Log3($hash->{NAME},4,"Roomba980::Read '$hash->{NAME}' unexpected message type '".message_type_string($message_type)."'");
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
  my $message = Net::MQTT::Message->new(%msg);
  Log3($name,5,"MQTT $name message sent: ".$message->string());
  if (defined $msg{message_id}) {
    $hash->{messages}->{$msg{message_id}} = {
      message => $message,
      timeout => gettimeofday()+$hash->{timeout},
    };
  }
  DevIo_SimpleWrite($hash,$message->bytes,undef);
};


sub apiCall ($$$) {
    my ($hash, $topic, $command) = @_;
	my $message = JSON::XS::encode_json({command => $command, time => time(), initiator => "localApp"});
    my %msg = (topic => $topic, message => $message, 
	           qos => MQTT_QOS_AT_MOST_ONCE);
	send_publish($hash,%msg);
};



sub topic_to_regexp($) {
  my $t = shift;
  $t =~ s|#$|.\*|;
  $t =~ s|\/\.\*$|.\*|;
  $t =~ s|\/|\\\/|g;
  $t =~ s|(\+)([^+]*$)|(+)$2|;
  $t =~ s|\+|[^\/]+|g;
  return "^$t\$";
}


sub discovery($){

    $DB::single = 1;

	use Socket qw(:all);
	
    my $sock = new IO::Socket::INET(
                Proto => 'udp', 
				Type => SOCK_DGRAM,
				Timeout => 60,
				Broadcast => 1,
				Blocking => 0);   # TODO: error handling or die('Error opening socket.');
	$sock->sockopt(SO_BROADCAST, 1);
    $sock->sockopt(SO_REUSEADDR, 1);	
	my $localport = $sock->sockport();	
    my $data = "irobotmcs";
	my $broadcastAddr = sockaddr_in( 5678, INADDR_BROADCAST );
    send( $sock, $data, 0,  $broadcastAddr );
	
	my $datagram;
    while (1) {
		sysread($sock,$datagram,200);
        print "Received datagram from ", $sock->peerhost, ": $datagram";
    }
    $sock->close();


  # server.on('message', (msg) => {
    # try {
      # let parsedMsg = JSON.parse(msg);
      # if (parsedMsg.hostname && parsedMsg.ip && parsedMsg.hostname.split('-')[0] === 'Roomba') {
        # server.close();
        # console.log('Robot found! with blid/username: ' + parsedMsg.hostname.split('-')[1]);
        # console.log(parsedMsg);
        # cb(null, full ? parsedMsg : parsedMsg.ip);
      # }
    # } catch (e) {}
  # });


};



1;
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
use strict;

package Plugins::XSqueezeDisplay::Plugin;

use base qw(Slim::Plugin::Base);
use vars qw($VERSION);
use Plugins::XSqueezeDisplay::Settings;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;
use LWP::UserAgent;
use POSIX qw(strftime);
use JSON::XS;

use constant CONNECTION_ATTEMPTS_BEFORE_SLEEP => 2;
use constant SLEEP_PERIOD => 10;
use constant NOT_PLAYING => 0;
use constant PLAYING => 1;

my $ua = LWP::UserAgent->new;

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.xsqueezedisplay',
	'defaultLevel' => 'INFO',
	'description'  => getDisplayName(),
});

my $prefs = preferences('plugin.xsqueezedisplay');

my ($delay, $lines, $line1, $line2, $server_endpoint, $state, $failed_connects, $retry_timer);

# Playing properties
my %tokens  = 	(   "[current_date]", "",   #the date now (Monday, January 20, 2015)
					"[current_time]", "",   #the time now (6:16 PM)
					"[duration]", "",		#presented in [HH:]MM:SS
					"[totaltime]", "",		#same as duration
					"[time]", "",			#playback time presented in [HH:]MM:SS
					"[time_remaining]", "",	#playback time remaining presented in [HH:]MM:SS
					"[percentage]", "",		#playback percentage
					"[title]", "",	
					"[album]", "",
					"[artist]", "",
					"[season]", "", 
					"[episode]", "",
					"[showtitle]", "",
					"[tvshowid]", "",
					"[thumbnail]", "",
					"[file]", "",
					"[fanart]", "",
					"[streamdetails_audio_channels]", "",
					"[streamdetails_audio_codec]", "",
					"[streamdetails_audio_language]", "",
					"[streamdetails_subtile]", "",
					"[streamdetails_video_aspect]", "",
					"[streamdetails_video_codec]", "",
					"[streamdetails_video_height]", "",
					"[streamdetails_video_width]", "",
					"[streamdetails_video_stereomode]", "",
					"[type]", "",
					"[resume]", ""
				);

# Audio properties
# Pictures properties

sub getDisplayName { return 'PLUGIN_XSQUEEZEDISPLAY'; }

sub myDebug {
	my $msg = shift;
	my $lvl = shift;	
	if ($lvl eq "")
	{
		$lvl = "debug";
	}
	$log->$lvl("*** XSqueezeDisplay *** $msg");
}

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(shift);

	$VERSION = $class->_pluginDataFor('version');

	Plugins::XSqueezeDisplay::Settings->new;

	Slim::Buttons::Common::addSaver( 'SCREENSAVER.xsqueezedisplay',
		getFunctions(), \&setScreenSaverMode,
		undef, getDisplayName() );

	# $delay = $prefs->get('plugin_fileviewer_updateinterval') + 1;
	$delay = 1;
	if ($prefs->get('plugin_xsqueezedisplay_kodijsonuser') eq ""){
		$server_endpoint = join('', 'http://', $prefs->get('plugin_xsqueezedisplay_kodiip'),':',$prefs->get('plugin_xsqueezedisplay_kodijsonport'), '/jsonrpc');
	}
	else{
		$server_endpoint = 'http://' . $prefs->get('plugin_xsqueezedisplay_kodijsonuser') . ':' . $prefs->get('plugin_xsqueezedisplay_kodijsonpassword') . '@' . $prefs->get('plugin_xsqueezedisplay_kodiip') . ':' . $prefs->get('plugin_xsqueezedisplay_kodijsonport') . '/jsonrpc';
	}
	myDebug(join("","Kodi endpoint is ", $server_endpoint),"info");
	$state = NOT_PLAYING;
	$failed_connects = 0;
	$retry_timer = SLEEP_PERIOD;
}

sub setMode {
	my $class  = shift;
	my $client = shift;
	my $method = shift;

	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my %params = (
		stringHeader => 1,
		header => 'PLUGIN_XSQUEEZEDISPLAY',
		headerAddCount => 1,
		listRef => $lines,
		parentMode => Slim::Buttons::Common::mode($client),		  
	);

	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

my %xSqueezeDisplayFunctions = (
	'done' => sub {
		my ( $client, $funct, $functarg ) = @_;
		Slim::Buttons::Common::popMode($client);
		$client->update();

		# pass along ir code to new mode if requested
		if ( defined $functarg && $functarg eq 'passback' ) {
			Slim::Hardware::IR::resendButton($client);
		}
	}
);

sub getFunctions {
	return \%xSqueezeDisplayFunctions;
}

sub setScreenSaverMode {
	my $client = shift;
	$client->modeParam('modeUpdateInterval', 1);
	$client->lines(\&screensaverXSqueezeDisplayLines);
}

sub defaultDisplay {
	$line1 = $tokens{'[current_date]'};
	$line2 = $tokens{'[current_time]'};
}

sub kodiJSON {
		my $post_data = shift;

		#set a very short timeout
		$ua->timeout(0.5);

		#assemble the JSON POST request
		my $req = HTTP::Request->new(POST => $server_endpoint);
		$req->header('content-type' => 'application/json');
		$req->content($post_data);

		#myDebug(join("", "JSON Request to: 	",$server_endpoint));
		#myDebug(join("", "JSON Request is: 	", $post_data));

		# submit the request
		my $resp = $ua->request($req);

		#  YAY! 
		if ($resp->is_success) {		    
	   	 	#myDebug("JSON Request Success: " . $resp->decoded_content ."\n");
		    return $resp;
		}
		#oh dear....
		else {
			#only log errors other than can't connect...
			if ($resp->code != 500){
			    myDebug(join("JSON Request error code: 		", $resp->code, "\n"),"info");
			    myDebug(join("JSON Request error message: 	", $resp->message, "\n"),"info");
			}
			return $resp;
		}	
	    
	    
}

#Takes seconds and returns a formatted string of HH:MM:SS or MM:SS if the hours is 0.
sub format_time{
	my $seconds = shift;

	my $hours = ($seconds/(60*60))%24;
	my $minutes = ($seconds/60)%60;
	my $seconds = $seconds%60;

	if ($hours != 0){
		return sprintf("%02d:%02d:%02d", $hours, $minutes, $seconds);
	}
	else {
		return sprintf("%02d:%02d", $minutes, $seconds);
	}
}

sub getPlayingProgress {

	my $playerid = shift;

	# Always get the play progress time 
	my $post_data = '{
	    "jsonrpc": "2.0",
	    "method": "Player.GetProperties",
	    "params": {
	        "properties": [
	            "percentage",
	            "time",
	            "totaltime"
	        ],
	        "playerid": '.$playerid.'
	    },
	    "id": 1
	}';

	my $resp = kodiJSON($post_data);						
	
	if ($resp->is_success) {
		my $message = decode_json $resp->decoded_content;

		my $duration_in_seconds = ($message->{'result'}{'totaltime'}{'hours'} * 60 * 60) + ($message->{'result'}{'totaltime'}{'minutes'} * 60) + $message->{'result'}{'totaltime'}{'seconds'};
		$tokens{'[duration]'} = format_time($duration_in_seconds);
		$tokens{'[totaltime]'} = $tokens{'[duration]'};

		my $elapsed_in_seconds = ($message->{'result'}{'time'}{'hours'} * 60 * 60) + ($message->{'result'}{'time'}{'minutes'} * 60) + $message->{'result'}{'time'}{'seconds'};
		$tokens{'[time]'} = format_time($elapsed_in_seconds);

		my $difference_in_seconds = $duration_in_seconds - $elapsed_in_seconds;
		$tokens{'[time_remaining]'} = format_time($difference_in_seconds);

		$tokens{'[percentage]'} = $message->{'result'}{'percentage'};

		myDebug ("\n"											.
				 "\n|duration_in_seconds " 						.$duration_in_seconds.
				 "\n|duration "									.$tokens{'[duration]'}.
				 "\n|elapsed_in_seconds " 						.$elapsed_in_seconds.
				 "\n|time " 									.$tokens{'[time]'}.
				 "\n|time_remaining " 							.$tokens{'[time_remaining]'}.
				 "\n|percentage " 								.$tokens{'[percentage]'}.
				 "\n");

	}

}

sub getExtendedNowPlaying {

	my $playerid = shift;

	my $post_data = '{
		    "jsonrpc": "2.0",
		    "method": "Player.GetItem",
		    "params": {
		        "properties":   [
		        				"title", 
		        				"album", 
		        				"artist", 
		        				"season", 
		        				"episode", 
		        				"duration", 
		        				"showtitle", 
		        				"tvshowid", 
		        				"thumbnail", 
		        				"file", 
		        				"fanart", 
		        				"streamdetails"
		        				],
		        "playerid": '.$playerid.'
		    },
		    "id": "VideoGetItem"
		}';

		# {
		#     "id": "VideoGetItem",
		#     "jsonrpc": "2.0",
		#     "result": {
		#         "item": {
		#             "album": "",
		#             "artist": [],
		#             "episode": 14,
		#             "fanart": "image://http%3a%2f%2fthetvdb.com%2fbanners%2ffanart%2foriginal%2f94551-11.jpg/",
		#             "file": "Z:\\IT Documents\\Video Files\\TV\\Parenthood (2010)\\Season 03\\Parenthood S03E14.avi",
		#             "id": 4,
		#             "label": "It Is What It Is",
		#             "season": 3,
		#             "showtitle": "Parenthood (2010)",
		#             "streamdetails": {
		#                 "audio": [{
		#                     "channels": 2,
		#                     "codec": "mp3",
		#                     "language": ""
		#                 }],
		#                 "subtitle": [],
		#                 "video": [{
		#                     "aspect": 1.7727270126342773,
		#                     "codec": "xvid",
		#                     "duration": 2562,
		#                     "height": 352,
		#                     "stereomode": "",
		#                     "width": 624
		#                 }]
		#             },
		#             "thumbnail": "image://http%3a%2f%2fthetvdb.com%2fbanners%2fepisodes%2f94551%2f4231536.jpg/",
		#             "title": "It Is What It Is",
		#             "tvshowid": 1,
		#             "type": "episode"
		#         }
		#     }
		# }


	my $resp = kodiJSON($post_data);						
	
	if ($resp->is_success) {
		#myDebug($resp->decoded_content);
		my $message = decode_json $resp->decoded_content;

		$tokens{'[title]'} 					= $message->{'result'}{'item'}{'title'};
		$tokens{'[album]'}					= $message->{'result'}{'item'}{'album'};
		$tokens{'[artist]'} 				= $message->{'result'}{'item'}{'artist'}->[0]; #array of artists it seems
		$tokens{'[showtitle]'} 				= $message->{'result'}{'item'}{'showtitle'};
		$tokens{'[season]'} 				= $message->{'result'}{'item'}{'season'};
		$tokens{'[episode]'} 				= $message->{'result'}{'item'}{'episode'};
		$tokens{'[tvshowid]'} 				= $message->{'result'}{'item'}{'tvshowid'};
		$tokens{'[thumbnail]'} 				= $message->{'result'}{'item'}{'thumbnail'};
		$tokens{'[file]'} 					= $message->{'result'}{'item'}{'file'};
		$tokens{'[fanart]'} 				= $message->{'result'}{'item'}{'fanart'};
		$tokens{'[type]'}               	= $message->{'result'}{'item'}{'type'};
		#audio details
		$tokens{'[streamdetails_audio_channels]'} 				= $message->{'result'}{'item'}{'streamdetails'}{'audio'}->[0]->{'channels'};
		$tokens{'[streamdetails_audio_codec]'} 					= $message->{'result'}{'item'}{'streamdetails'}{'audio'}->[0]->{'codec'};
		$tokens{'[streamdetails_audio_language]'} 				= $message->{'result'}{'item'}{'streamdetails'}{'audio'}->[0]->{'language'};
		#array of subtitles
		$tokens{'[streamdetails_subtile]'} 						= $message->{'result'}{'item'}{'streamdetails'}{'subtitle'}->[0];
		#video details
		$tokens{'[streamdetails_video_aspect]'} 				= $message->{'result'}{'item'}{'streamdetails'}{'video'}->[0]->{'aspect'};
		$tokens{'[streamdetails_video_codec]'} 					= $message->{'result'}{'item'}{'streamdetails'}{'video'}->[0]->{'codec'};
		$tokens{'[streamdetails_video_height]'} 				= $message->{'result'}{'item'}{'streamdetails'}{'video'}->[0]->{'height'};
		$tokens{'[streamdetails_video_width]'} 					= $message->{'result'}{'item'}{'streamdetails'}{'video'}->[0]->{'width'};
		$tokens{'[streamdetails_video_stereomode]'} 			= $message->{'result'}{'item'}{'streamdetails'}{'video'}->[0]->{'stereomode'};

		myDebug ("\n"											.
				 "\n|title " 									.$tokens{'[title]'}.
				 "\n|album "									.$tokens{'[album]'}.
				 "\n|artist " 									.$tokens{'[artist]'}.
				 "\n|showtitle " 								.$tokens{'[showtitle]'}.
				 "\n|season "  									.$tokens{'[season]'}.  
				 "\n|episode " 									.$tokens{'[episode]'}.
				 "\n|tvshowid "									.$tokens{'[tvshowid]'}.
				 "\n|thumbnail "								.$tokens{'[thumbnail]'}.
				 "\n|file " 									.$tokens{'[file]'}.
				 "\n|file_basename " 							.$tokens{'[file_basename]'}.
				 "\n|fanart "									.$tokens{'[fanart]'}. 
				 "\n|type "										.$tokens{'[type]'}. 
				 "\n|streamdetails_audio_channels "				.$tokens{'[streamdetails_audio_channels]'}. 
				 "\n|streamdetails_audio_codec "				.$tokens{'[streamdetails_audio_codec]'}. 
				 "\n|streamdetails_audio_language "				.$tokens{'[streamdetails_audio_language]'}. 
				 "\n|streamdetails_subtile "					.$tokens{'[streamdetails_subtile]'}. 
				 "\n|streamdetails_video_aspect "				.$tokens{'[streamdetails_video_aspect]'}. 
				 "\n|streamdetails_video_codec "				.$tokens{'[streamdetails_video_codec]'}. 
				 "\n|streamdetails_video_height "				.$tokens{'[streamdetails_video_height]'}. 
				 "\n|streamdetails_video_width "				.$tokens{'[streamdetails_video_width]'}. 
				 "\n|streamdetails_video_stereomode "			.$tokens{'[streamdetails_video_stereomode]'}. 
				 "\n");

	}


}

sub token_swap{
	my $template = shift;

	while ((my $find, my $replace) = each(%tokens)){
		#myDebug("\n Template [".$template."] find [".$find."] replace [".$replace."]");
		$template =~ s/\Q$find\E/$replace/g;
	}
	#myDebug("\n Template [".$template."]");
	return $template;

}


sub screensaverXSqueezeDisplayLines {

	#don't acutally use this
	my $client = shift;

	#Blank out and only lines
	$line1 = "";
	$line2 = "";

	#OK NOW GATHER ALL THE POSSIBLE DATA TO RETURN

	#NON KODI DATA
	$tokens{'[current_date]'} = Slim::Utils::DateTime::longDateF(time);
	$tokens{'[current_time]'} = Slim::Utils::DateTime::timeF(time);

	#KODI DATA

	#if we have more than 3 failed connections...
	if ($failed_connects > CONNECTION_ATTEMPTS_BEFORE_SLEEP){
		#if our retry timer is still above 0...
		if ($retry_timer > 0) {
			#myDebug("Sleeping for " . $retry_timer);
			$retry_timer--;
		}
		#retry timer has reached zero - reset the timer & connects counter
		else{
			#myDebug("Ok, trying to connect again");
			$failed_connects = 0;
			$retry_timer = SLEEP_PERIOD;
		}
	}
	#failed_connects is <3, so try and do stuff
	else {

		#debug - introspect test the kodi json API here
		#my $post_data = '{ "jsonrpc": "2.0", "method": "JSONRPC.Introspect", "params": { "filter": { "id": "Player.GetItem", "type": "method" } }, "id": 1 }';
		# Get the active players
		my $post_data = '{
			"jsonrpc": "2.0", 
			"method": "Player.GetActivePlayers", 
			"id": 1
			}';

		my $resp = kodiJSON($post_data);
		
		if ($resp->is_success) {
			my $message = decode_json $resp->decoded_content;
			
			#A PLAYER IS ACTIVE
			if  (exists $message->{result}){

		    	#myDebug("Detected player activity - " . $resp->decoded_content);

		    	foreach my $player (@{$message->{result}}){
		    		myDebug("Player ". $player->{'playerid'} . " is type " . $player->{'type'});

					#state change - let's get the extended info this once only and store it
			    	if (($player->{'type'} eq "video" or $player->{'type'} eq "audio") and $state == NOT_PLAYING){				    		
			    		$state = PLAYING;
						getExtendedNowPlaying($player->{'playerid'});				    		
			    	}

	    			if ($player->{'type'} eq "video" or $player->{'type'} eq "audio"){
			    	#always get the current timers
			    		getPlayingProgress($player->{'playerid'});
			    	}

			    	#now pre the lines by swapping all tokens for values
					if ($player->{'type'} eq "video"){
						$line1 = token_swap($prefs->get('plugin_xsqueezedisplay_line1_video'));
						$line2 = token_swap($prefs->get('plugin_xsqueezedisplay_line2_video'));
					}
					elsif ($player->{'type'} eq "picture"){
						$line1 = token_swap($prefs->get('plugin_xsqueezedisplay_line1_picture'));
						$line2 = token_swap($prefs->get('plugin_xsqueezedisplay_line2_picture'));
					}
					elsif ($player->{'type'} eq "audio"){
						$line1 = token_swap($prefs->get('plugin_xsqueezedisplay_line1_audio'));
						$line2 = token_swap($prefs->get('plugin_xsqueezedisplay_line2_audio'));
					}				
				} # foreach $player
			} #there was a result in the json
		} #there was a resp->success

		#no response from Kodi
		else {
			#count failed connections.  If we get to 3, stop hammering the server for a while...(See top)
			if ($resp->code == 500){
				#myDebug("Failed to connect for " . $failed_connects);
				$failed_connects++;
			}
		}	

	} #failed_connects wwas less than 3

	#if no data at this point, default display the date on line 1, time on line 2
	if ($line1 eq "" and $line2 eq ""){
		$state = NOT_PLAYING;
		defaultDisplay();
	}

	#Package up the lines and return them
	my $hash = {
	   'center' => [ $line1,
	                 $line2 ],
	};

	return $hash;

}


1;


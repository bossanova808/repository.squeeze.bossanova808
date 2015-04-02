package Plugins::XSqueezeDisplay::Settings;

# Settings.pm
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.xsqueezedisplay');

$prefs->setValidate({ 'validator' => 'int' }, 'xbmcport');

sub new {
	my $class = shift;

	if (!defined $prefs->get('plugin_xsqueezedisplay_kodiip')) {
		$prefs->set('plugin_xsqueezedisplay_kodiip', '127.0.0.1');
	}
	if (!defined $prefs->get('plugin_xsqueezedisplay_kodijsonport')) {
		$prefs->set('plugin_xsqueezedisplay_kodijsonport', 80);
	}
	if (!defined $prefs->get('plugin_xsqueezedisplay_kodijsonuser')) {
		$prefs->set('plugin_xsqueezedisplay_kodijsonuser', '');
	}
	if (!defined $prefs->get('plugin_xsqueezedisplay_kodijsonpassword')) {
		$prefs->set('plugin_xsqueezedisplay_kodijsonpassword', '');
	}
	if (!defined $prefs->get('plugin_xsqueezedisplay_line1_video')) {
		$prefs->set('plugin_xsqueezedisplay_line1_video', '');
	}
	if (!defined $prefs->get('plugin_xsqueezedisplay_line2_video')) {
		$prefs->set('plugin_xsqueezedisplay_line2_video', '');
	}
	if (!defined $prefs->get('plugin_xsqueezedisplay_line1_picture')) {
		$prefs->set('plugin_xsqueezedisplay_line1_picture', '');
	}
	if (!defined $prefs->get('plugin_xsqueezedisplay_line2_picture')) {
		$prefs->set('plugin_xsqueezedisplay_line2_picture', '');
	}
	if (!defined $prefs->get('plugin_xsqueezedisplay_line1_audio')) {
		$prefs->set('plugin_xsqueezedisplay_line1_audio', '');
	}
	if (!defined $prefs->get('plugin_xsqueezedisplay_line2_audio')) {
		$prefs->set('plugin_xsqueezedisplay_line2_audio', '');
	}

	return $class->SUPER::new();
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_XSQUEEZEDISPLAY');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/XSqueezeDisplay/settings.html');
}

sub prefs {
	return ($prefs, qw(plugin_xsqueezedisplay_kodiip plugin_xsqueezedisplay_kodijsonport plugin_xsqueezedisplay_kodijsonuser plugin_xsqueezedisplay_kodijsonpassword plugin_xsqueezedisplay_line1_video plugin_xsqueezedisplay_line2_video plugin_xsqueezedisplay_line1_picture plugin_xsqueezedisplay_line2_picture plugin_xsqueezedisplay_line1_audio plugin_xsqueezedisplay_line2_audio));
}

1;

__END__

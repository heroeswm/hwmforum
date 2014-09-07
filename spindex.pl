#!/usr/bin/speedy

use strict;
use utf8;
use CGI qw/-utf8 :standard/;
use Forum::Func;

binmode(STDOUT,':utf8');

my $module = url_param('mod') || 'forum';
if ($module =~ /[^A-Za-z_]/ || $module =~ /index$/) {
	$module = 'forum';
}

if (-f 'Forum/'.$module.'.pm') {
	no strict 'refs';
	eval "use Forum::".$module;
	warn $@ if ($@);
	&{ "Forum::".$module."::main" }();
}


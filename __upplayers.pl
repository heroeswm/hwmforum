#!/usr/bin/perl

use strict;
use utf8;
use DBI;
use CGI qw/-utf8 :standard/;
use POSIX;
use Forum::Func;
use LWP::UserAgent;
use Data::Dumper;

sub get_pers_hwm_add
{
	my $nick = shift;
	my $chk = shift;
	my %result = ();
	my $converter = Text::Iconv->new("UTF-8", "CP1251");
	my $urinick = $converter->convert($nick);
	$urinick =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	my $ua = LWP::UserAgent->new();
	$ua->proxy('http', 'http://localhost:3199/');
	$ua->timeout(60);
	my $req = HTTP::Request->new(GET => "http://www.heroeswm.ru/pl_info.php?nick=".$urinick);
	my $res = $ua->request($req);
	my $cont = $res->content;
	if ($cont =~ m#&nbsp;<b>(<a[^>]+><img src='[^']*i_clans/l_(\d+)\.gif\?v=(\d+)'[^>]+ title='([^'>]+)' [^>]+></a><img[^>]+>)?([^&<]+)&nbsp;&nbsp;\[(\d+)\]#) {
		my $newnick = $5;
#		my $newclan = $4;
		$result{clanid} = $2;
		$result{clanver} = $3;
		$result{lvl} = $6;
		my $invconverter = Text::Iconv->new("CP1251", "UTF-8");
		$result{nick} = $invconverter->convert($newnick);
#		$result{clan} = $invconverter->convert($newclan);
	}
	my $maxp = 0;
	my $maxf = 0;
	my @m = $cont =~ m#&nbsp;&nbsp;(<b>)?(\xd0\xfb\xf6\xe0\xf0\xfc|\xcd\xe5\xea\xf0\xee\xec\xe0\xed\xf2|\xcc\xe0\xe3|\xdd\xeb\xfc\xf4|\xc2\xe0\xf0\xe2\xe0\xf0|\xd2\xe5\xec\xed\xfb\xe9\x20\xfd\xeb\xfc\xf4|\xc4\xe5\xec\xee\xed|\xc3\xed\xee\xec): \d+(</b>)? \(([^\)]+)\) <font style='font-size:8px;color:\#696156'>#g;
	for (my $i=3; $i<@m; $i+=4) {
		if ($maxp < $m[$i]) {
			$maxp = $m[$i];
			$maxf = ($i-3)/4+1;
		}
	}
	if ($cont =~ m#<img width=150 height=150 border=0 align=right src="([^"]+/avatars/[^"]+)">#) {
		$result{avatar} = $1;
	}
	$result{fact} = $maxf;
	if ($cont =~ /<a href='pl_cardlog\.php\?id=(\d+)'>/) {
		$result{id} = $1;
	} else {
		return;
	}
	return \%result;
}

binmode(STDOUT,':utf8');

our $dbh = connect_db();

foreach my $arr (@{$dbh->selectall_arrayref('SELECT id,nick FROM users LEFT JOIN plinfo ON plinfo.uid=users.id WHERE plinfo.update IS NULL OR plinfo.update<DATE_SUB(NOW(), INTERVAL 7 DAY)')}) {
	my ($id, $nick) = @$arr;
#	my $oldinfo = $dbh->selectrow_hashref('SELECT * FROM plinfo WHERE uid=?', undef, $id);
	print Dumper $nick;
	my $newinfo = get_pers_hwm_add($nick);
	print Dumper $newinfo;
	if (ref $newinfo) {
		$dbh->do('INSERT INTO plinfo (uid,plid,clan,lvl,fact,avatar) VALUES(?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE `update`=NOW(), clan=?, lvl=?, fact=?, avatar=?', undef, $id, int $newinfo->{id}, int $newinfo->{clanid}, int $newinfo->{lvl}, int $newinfo->{fact}, $newinfo->{avatar}, int $newinfo->{clanid}, int $newinfo->{lvl}, int $newinfo->{fact}, $newinfo->{avatar});
	}
}


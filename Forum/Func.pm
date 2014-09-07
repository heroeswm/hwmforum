package Forum::Func;
use lib "/home/u220975/perl/lib/perl5/site_perl/5.10.1/mach/";
use strict;
use utf8;
use DBI;
use CGI qw/-utf8 :standard/;
use CGI::Cookie;
use Digest::CRC qw(crc32);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use HTML::Entities qw(decode_entities);
use Crypt::PasswdMD5;
use Text::Iconv;
use LWP::UserAgent;
use POSIX;
use Encode qw(encode_utf8);
use Forum::Adds qw(cSPACE cHWM cPROJID get_mysql_pass allowed_change_group);
use base 'Exporter';

our @EXPORT = qw(settings settings_def print_start_html get_pers_hwm get_bans encode_text encode_entities allowed_to make_login crypt_password gen_code connect_db get_remote_hash crypt_idnick_hash check_idnick_hash get_idnick_hash gen_crc check_code link_to_pers get_login parse_acl check_limits wipe_limits make_pages_div make_pages_line pages_getrange get_page check_doublepost return_smth);

our $SETTINGS = {};

our @seeds = (
	'Aiji5eer',
	'zooThoh9',
	'saeXe8ze',
	'eeGha3ee',
	'Chiix1ow',
	'soh0Iewi',
	'OoPoh0oz',
);

our %settings_def = (
	'pn_clan' => 'yes',
	'pn_lvl' => 'no',
	'pn_fact' => 'no',
	'pn_avatar' => 'no',
	'hwm_url' => 'www.heroeswm.ru',
	'bbpanel' => 'off',
	'show_author' => 'first',
);

sub settings
{
	my $key = shift;
	my $default = shift;
	return $SETTINGS->{$key}->{value} if (defined $SETTINGS->{$key});
	if (defined $default) {
		return $default;
	}
	return $settings_def{$key};
}

sub settings_def
{
	return $settings_def{$_[0]};
}

sub print_start_html
{
	my $title = shift;
	$title .= ' - ' if ($title);
	$title .= (cSPACE() ? 'o_O' : 'HWM AltForums');
	my $path = (cSPACE() ? '/static/' : (cPROJID() eq 'mh' ? '': 'static/'));
	my $style = $path . (cSPACE() ? 'forum.css' : 'style.css');
	my $hash = {
		-title => $title,
		-style => {-src => $style},
		-script => [
			{-type => 'javascript', -src => $path.'jquery-1.7.1.min.js'},
			{-type => 'javascript', -src => $path.'forum.js'},
		]
	};
	if (cHWM()) {
		$hash->{'-head'} = Link({-rel => 'icon', -type => 'image/x-icon', -href => $path.'favicon.ico'}),
	}
	print start_html($hash);
}

sub get_pers_hwm
{
	my $nick = shift;
	my $chk = shift;
	my $converter = Text::Iconv->new("UTF-8", "CP1251");
	my $urinick = $converter->convert($nick);
	$urinick =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
	my $ua = LWP::UserAgent->new();
	$ua->timeout(60);
	my $req = HTTP::Request->new(GET => "http://www.heroeswm.ru/pl_info.php?nick=".$urinick);
	my $res = $ua->request($req);
	my $cont = $res->content;
	if ($cont =~ m#&nbsp;<b>(<a[^>]+><img src='[^']*i_clans/l_(\d+)\.gif\?v=(\d+)'[^>]+ title='([^'>]+)' [^>]+></a><img[^>]+>)?([^&<]+)&nbsp;&nbsp;\[\d+\]#) {
		my $newnick = $5;
		my $invconverter = Text::Iconv->new("CP1251", "UTF-8");
		$nick = $invconverter->convert($newnick);
	}
	if ($cont =~ /<a href='pl_cardlog\.php\?id=(\d+)'>/) {
		my $id = $1;
		return ($nick, $id, index($cont, check_code($chk)) != -1);
	}
	return;
}

sub get_bans
{
	my $dbh = shift;
	my ($uid, $cat, $fid, $tid) = @_;
	my @result = @{$dbh->selectall_arrayref(
		"(SELECT reason,nick,bantill FROM ::bans as b LEFT JOIN ::users as u ON b.uid=u.id WHERE who=? AND type='global' AND bantill > NOW())".
			" UNION ".
		"(SELECT reason,nick,bantill FROM ::bans as b LEFT JOIN ::users as u ON b.uid=u.id WHERE who=? AND type='category' AND bantill > NOW() AND onid=?)".
			" UNION ".
		"(SELECT reason,nick,bantill FROM ::bans as b LEFT JOIN ::users as u ON b.uid=u.id WHERE who=? AND type='forum' AND bantill > NOW() AND onid=?)".
			" UNION ".
		"(SELECT reason,nick,bantill FROM ::bans as b LEFT JOIN ::users as u ON b.uid=u.id WHERE who=? AND type='thread' AND bantill > NOW() AND onid=?)",
	undef, $uid, $uid, $cat, $uid, $fid, $uid, $tid)};
	return @result;
}

sub insert_wbr
{
    $_ = $_[0];
    s/([^<>\/\[\] \t\-\n]{50})/$1<wbr\/>/gs;
    return $_;
}

sub encode_text
{
	my $text = shift;
	my $service = shift;
	my $login = shift;
	$login = {acl=>{}} if (!ref $login);
	if (!$service) {
		$text = encode_entities($text);
		$text =~ s#\[q(uote)?\](.*?)\[/q(uote)?\]#<span class="quote">$2</span>#sg;
		$text =~ s#\[b(old)?\](.*?)\[/b(old)?\]#<span class="bold">$2</span>#sg;
		$text =~ s#\[s(trike)?\](.*?)\[/s(trike)?\]#<span class="strike">$2</span>#sg;
		$text =~ s#\[i(talic)?\](.*?)\[/i(talic)?\]#<span class="italic">$2</span>#sg;
		$text =~ s#\[n(ormal)?\](.*?)\[/n(ormal)?\]#<span class="normal">$2</span>#sg;
		$text =~ s#\[c(ode)?\](.*?)\[/c(ode)?\]#<span class="code">$2</span>#sg;
		$text =~ s#(http://[^\s()<]+)#<a href="$1">$1</a>#sg;
		$text =~ s/\n/<br>/sg;
		$text =~ s{(>|^)([^<>]*)(<|$)}{
			my $res = insert_wbr($2);
			$1.$res.$3;
		}gse;
		return $text;
	} elsif ($text =~ /^close/) {
		return '<span class="sysmsg">-- Тема закрыта --</span>';
	} elsif ($text =~ /^open/) {
		return '<span class="sysmsg">-- Тема открыта --</span>';
	} elsif ($text =~ /^depublish/) {
		return '<span class="sysmsg">-- Тема была снята с публикации на сайте --</span>';
	} elsif ($text =~ /^publish (.*)$/) {
		return '<span class="sysmsg">-- Тема была опубликована на сайте в разделе "'.encode_entities($1).'" --</span>';
	} elsif ($text =~ /^changetopic\n(.*?)\n(.*?)$/s) {
		return '<span class="sysmsg">-- Изменена тема с &quot;<b>'.encode_entities($1).'</b>&quot; на &quot;<b>'.encode_entities($2).'</b>&quot; --</span>';
	} elsif ($text =~ /^move\n(\d+)\|(.*)\n(\d+)\|(.*)$/s) {
		my $msg = '<span class="sysmsg">-- Тема перенесена';
		if (allowed_to('view', $1, $login->{acl})) {
			$msg .= ' из &quot;<b><a href="forum_thread.pl?id='.$1.'">'.encode_entities($2).'</a></b>&quot;';
		}
		if (allowed_to('view', $3, $login->{acl})) {
			$msg .= ' в &quot;<b><a href="forum_thread.pl?id='.$3.'">'.encode_entities($4).'</a></b>&quot; --</span>';
		}
		return $msg;
	} elsif ($text =~ /^changeattrs\n(.*)$/s) {
		my @m = $1 =~ /[^\n]+/sg;
		return '<span class="sysmsg">-- Изменены аттрибуты темы: '.join(', ', map {
			/(\w+) (\d)/;
			my $res = $2 ? 'установлен флаг ' : 'снят флаг ';
			if ($1 eq 'attached') {
				$res .= '"Прикреплено"';
			} elsif ($1 eq 'important') {
				$res .= '"Важно"';
			} elsif ($1 eq 'premium') {
				$res .= '"П/а"';
			} elsif ($1 eq 'readonly') {
				$res .= '"Только чтение"';
			}
			$res;
		} @m).' --</span>';
	}
	return "<i>Системное сообщение неизвестного типа, вероятно, баг</i>";
}


sub encode_entities
{
	return HTML::Entities::encode_entities($_[0], "<>&\"'");
}

sub allowed_to
{
	my ($action, $fid, $acl) = @_;
	return 0 if (!ref($acl->{$fid}));
	return 1 if ($acl->{$fid}->{$action} eq 'allow');
	return 0 if ($acl->{$fid}->{$action} eq 'deny');
}

sub make_login
{
	my $dbh = shift;
	my $uid = shift;
	my $sid = gen_code(16);
	my $cookie = new CGI::Cookie(-name=>'sid', -value=>$sid, -expires=>'+1y');
	print header(-status=>'302 Found', -location=>'forum.pl', -cookie=>[$cookie]);
	my $max = 4;
	foreach (@{$dbh->selectcol_arrayref('SELECT ::sid FROM ::logins WHERE id=? ORDER BY time DESC', undef, $uid)}) {
		if ($max-- <= 0) {
			$dbh->do('DELETE FROM ::logins WHERE sid=?', undef, $_);
		}
	}
	$dbh->do('INSERT INTO ::logins (sid, id) VALUES(?, ?)', undef, $sid, $uid);
}

sub crypt_password
{
	my $pass = shift;
	my $seed = shift;
	return unix_md5_crypt(encode_utf8($pass.$seeds[4]), $seed);
}

sub gen_code
{
	my $code;
	my @chars = ('a'..'z','A'..'Z','0'..'9');
	for (0..$_[0]-1) {
		$code .= $chars[rand @chars];
	}
	return $code;
}

sub connect_db
{
	my ($host, $port, $user, $pass, $db) = get_mysql_pass();
	my $dbh = DBI->connect("DBI:mysql:$db:$host:$port", $user, $pass, { mysql_enable_utf8 => 1, RootClass => 'Forum::SubDBI' }) 
		or die "Could not connect to database: $DBI::errstr";
	$dbh->do("set character set utf8");
	$dbh->do("set names utf8");
	return $dbh;
}

sub get_remote_hash
{
	my $ip = remote_addr();
	return md5_base64(encode_utf8($seeds[0].$ip));
}

sub crypt_idnick_hash
{
#	return $b;
	my $a = shift;
	my $b = shift;
	return unix_md5_crypt(encode_utf8($a.$seeds[5].$b));
}

sub check_idnick_hash
{
#	return $b == $check;
	my $a = shift;
	my $b = shift;
	my $check = shift;
	return unix_md5_crypt(encode_utf8($a.$seeds[5].$b), $check) eq $check;
}

sub get_idnick_hash
{
	my $a = shift;
	my $b = shift;
	return md5_base64(encode_utf8($a.$seeds[1].$b));
}

sub gen_crc
{
	my ($sid, $action) = @_;
	return crc32(encode_utf8($sid.$seeds[2].$action));
}

sub check_code
{
	return substr(md5_hex(encode_utf8($_[0].$seeds[3].remote_addr())), 0, 15);
}

sub link_to_pers
{
	my $nick = shift;
	if (defined $nick) {
		if ($nick =~ /\*/) {
			return '<i><span class="li">'.encode_entities($nick).'</span></i>';
		} else {
			my $converter = Text::Iconv->new("UTF-8", "CP1251");
			my $urinick = $converter->convert($nick);
			$urinick =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
			return '<a class="li" href="http://'.settings('hwm_url').'/pl_info.php?nick='.$urinick.'"><nobr>'.encode_entities($nick).'</nobr></a>';
		}
	} else {
		return '<i>(removed)</i>';
	}
}

sub get_login
{
	my $dbh = shift;
	my $res = undef;
	my %cookies = fetch CGI::Cookie;
	my $sid = $seeds[6];
	if (exists $cookies{'sid'}) {
		$sid = $cookies{'sid'}->value;
		if (cSPACE()) {
		use Data::Dumper;warn Dumper $sid;
			$res = $dbh->selectrow_arrayref('SELECT nick, id FROM ::users WHERE sid=? LIMIT 1', undef, $sid);
		use Data::Dumper;warn Dumper $res;
		} else {
			$res = $dbh->selectrow_arrayref('SELECT nick, id FROM ::logins INNER JOIN ::users USING(`id`) WHERE sid=? LIMIT 1', undef, $sid);
		}
	}
	if (!ref($res)) {
		$res = $dbh->selectrow_arrayref('SELECT nick, id FROM ::users WHERE id=0 LIMIT 1');
	}
	if (!ref($res)) {
		$res = ['anonymous', 0, 0];
	}
	my $acl = $dbh->selectall_arrayref('(SELECT fid, type, actions, role FROM ::groups JOIN ::aclist USING(`gid`) WHERE uid=? AND accepted=1) UNION (SELECT fid, type, actions, "" FROM ::aclist WHERE gid=0)', undef, $res->[1]);
	if (allowed_change_group($res->[1]) && defined param('CG')) {
		my $cg = param('CG');
		if ($cg =~ /^(\d+,)*\d+$/) {
			$acl = $dbh->selectall_arrayref('SELECT fid, type, actions, role FROM ::groups JOIN ::aclist USING(`gid`) WHERE gid IN (0,'.$cg.')', undef);
		} else {
			die();
		}
	}
	if (!ref $acl) {
		$acl = [];
	}
	if ($res->[1]) {
		$SETTINGS = $dbh->selectall_hashref('SELECT name,value FROM ::settings WHERE uid=?', ['name'], undef, $res->[1]);
	}
	$SETTINGS = {} if (!ref $SETTINGS);
	return (
		id => $res->[1],
		nick => $res->[0],
		sid => $sid,
		acl => parse_acl($acl),
	);
}

sub parse_acl
{
	my $acl = shift;
	my %result = ();
	foreach (@{$acl}) {
		my ($fid, $type, $list, $role) = @$_;
		my @list = split(',', $list);
		$result{$fid} = {} if (!ref $result{$fid});
		foreach (@list) {
			if ($_ eq 'modifset') {
				if ($role =~ /mod/) {
					$_ = 'moderate';
				} else {
					next;
				}
			}
			if ($result{$fid}->{$_} ne 'deny') {
				$result{$fid}->{$_} = $type;
			}
		}
	}
	return \%result;
}

sub check_limits
{
	my ($dbh, $remote, $type, $params) = @_;
	wipe_limits($dbh);
	# magic
	if ($remote !~ /^\d{1,9}$/) {
		$remote = crc32($remote);
		if ($remote > 2147483645) {
			$remote -= 2*2147483645;
		}
	}
	my ($min, $hour, $day) = @$params;
	my @arr = $dbh->selectrow_array('SELECT COUNT(*) FROM ::limits WHERE type=? AND remote=? AND time > NOW()-INTERVAL 1 MINUTE', undef, $type, $remote);
	return 0 if ($arr[0] >= $min);
	my @arr = $dbh->selectrow_array('SELECT COUNT(*) FROM ::limits WHERE type=? AND remote=? AND time > NOW()-INTERVAL 1 HOUR', undef, $type, $remote);
	return 0 if ($arr[0] >= $hour);
	my @arr = $dbh->selectrow_array('SELECT COUNT(*) FROM ::limits WHERE type=? AND remote=? AND time > NOW()-INTERVAL 1 DAY', undef, $type, $remote);
	return 0 if ($arr[0] >= $day);
	$dbh->do('INSERT INTO ::limits (type, remote) VALUES(?, ?)', undef, $type, $remote);
	return 1;
}

sub wipe_limits
{
	my $dbh = shift;
	$dbh->do("DELETE FROM `::limits` WHERE `time` < NOW()-INTERVAL 1 DAY");
}

sub make_pages_div
{
	return '' if ($_[0] <= 1);
	return '<div class="pages">'.make_pages_line(@_).'</div>';
}

sub make_pages_line
{
	my $max = shift;
	return '' if ($max <= 1);
	my $curr = shift;
	my $url = shift;
	my @pages = ();
	push @pages, pages_getrange($curr, $max);
	my @result = map {
		if (ref $_) {	
			'...'
		} elsif ($_ == $curr) {
			'<b>'.$_.'</b>'
		} else {
			my $url2 = $url;
			if ($_ > 1) {
				$url2 =~ s/PAGE_NUMBER/&page=$_/;
			} else {
				$url2 =~ s/PAGE_NUMBER//;
			}
			'<a href="'.$url2.'">'.$_.'</a>'
		}
	} @pages;
	return 'Страницы: '.join(' ', @result);
}

sub pages_getrange
{
	my $curr = shift;
	my $max = shift;
	my $delw = 1;
	my %saw = ();
	my @result;
	if ($curr <= 5) {
		@result = (1..8, $max-1, $max);
	} elsif ($curr > $max-4) {
		@result = (1..2, ($curr-3)..($curr+3), $max-6..$max);
	} else {
		@result = (1..2, ($curr-3)..($curr+3), $max);
	}
	my @result = sort {$a <=> $b} grep {
		($_ >= 1) && ($_ <= $max) && (!$saw{$_}++)
	} @result;

	my $prev = 0;
	my @range = ();
	my $dots = 0;
	foreach (@result) {
		if ($prev != $_ - 1) {
			if ($prev < $_-$delw-1) {
				push @range, [$prev+1..$_-1];
				$dots++;
			} else {
				push @range, ($prev+1..$_-1);
			}
		}
		push @range, $_;
		$prev = $_;
	}
	return @range;
}

sub get_page
{
	my $pcount = shift;
	my $page = param('page');
	if ($page eq 'last') {
		$page = ceil($pcount/20);
	} else {
		$page = int($page);
		if (!$page) {
			$page = 1;
		}
	}
	return $page;
}

sub check_doublepost
{
	my $dbh = shift;
	my $login = shift;
	my $msg = shift;
	my $tid = shift;
	$msg =~ s/^\s+|\s+$//g;
	my ($lastmsg, $lasttid);
	if (cSPACE()) {
		($lastmsg, $lasttid) = $dbh->selectrow_array('SELECT lastmsg, lasttid FROM ::users WHERE id=?', undef, $login->{id});
	} else {
		($lastmsg, $lasttid) = $dbh->selectrow_array('SELECT lastmsg, lasttid FROM ::logins WHERE sid=?', undef, $login->{sid});
	}
	my $thismsg = crc32($msg);
	if ($thismsg > 2147483645) {
		$thismsg -= 2*2147483645;
	}
	if ($tid == $lasttid && $thismsg == $lastmsg) {
		return 1;
	}
	$dbh->do('UPDATE ::logins SET lastmsg=?, lasttid=? WHERE sid=?', undef, $thismsg, $tid, $login->{sid});
	return 0;
}

sub return_smth
{
	my $url = shift;
	my $jsresponse = shift;
	if (param('js')) {
		print header(
			-type => 'text/plain',
			-charset => 'UTF-8',
		);
		print $jsresponse;
	} else {
		print redirect($url);
	}
}

1;

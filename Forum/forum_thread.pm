package Forum::forum_thread;
use strict;
use utf8;
use DBI;
use POSIX;
use CGI qw/-utf8 :standard/;
use Forum::Func;
use Forum::Adds;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub main {

if (!defined param('id')) {
	print redirect('forum.pl');
	exit;
}
my $fid = int(param('id'));

our $dbh = connect_db();
my %login = get_login($dbh);

my $forum = $dbh->selectrow_hashref('SELECT f.name,f.topics,f.msgs,f.catid,l.lasttid FROM ::forums as f LEFT JOIN ::lastfread as l ON l.fid=f.fid AND uid=? WHERE f.fid=? LIMIT 1', undef, $login{id}, $fid);
if (!ref $forum || !allowed_to('view', $fid, $login{acl})) {
	print redirect('forum.pl');
	$dbh->disconnect();
	exit;
}

print header(
	-type => 'text/html',
	-charset => 'UTF-8',
);
print_start_html($forum->{name});

print '<table width="100%"><tr><td width="50%"><div class="path"><a href="forum.pl">Форумы</a> &rarr; <a href="forum_thread.pl?id='.$fid.'">'.encode_entities($forum->{name}).'</a></div></td><td width="50%">';
my $pcount = $dbh->selectrow_array('SELECT COUNT(*) FROM ::threads WHERE fid=?', undef, $fid);
my $page = get_page($pcount);
my $nav_pages = make_pages_div(ceil($pcount/30), $page, 'forum_thread.pl?id='.$fid.'PAGE_NUMBER');
print $nav_pages;
print "</td></tr></table>";

print '<table class="mt">
	<tr class="toptr">
		<th width="40%">Тема</th>
		<th>Дата</th>
		<th style="text-align:center" width="30">#</th>
		<th>Автор</th>
		<th>Последнее сообщение</th>
	</tr>';

my $num = 0;
my $query = 'SELECT t.tid, `topic`, UNIX_TIMESTAMP(`start`), `msgs`, us1.nick, UNIX_TIMESTAMP(m.date), us2.nick, attr, attached, poll, l.num,';
if (cHWM()) {
	$query .= ' pl1.clan, pl1.lvl, pl1.fact, pl2.clan, pl2.lvl, pl2.fact';
} else {
	$query .= ' NULL, NULL, NULL, NULL, NULL, NULL';
}
$query .= ' FROM ((((::threads as t LEFT JOIN (::msgs as m LEFT JOIN ::users as us2 ON m.author=us2.id) ON t.last=m.id) LEFT JOIN ::users as us1 ON t.author=us1.id) LEFT JOIN ::lastread as l ON l.tid=t.tid AND l.uid=?)';
if (cHWM()) {
	$query .= ' LEFT JOIN ::plinfo as pl1 ON us1.id=pl1.uid) LEFT JOIN ::plinfo as pl2 ON us2.id=pl2.uid';
} else {
	$query .= ' )';
} 
$query .= ' WHERE t.fid=? ORDER BY attached DESC, m.date DESC LIMIT ?,30';
foreach (@{$dbh->selectall_arrayref($query, undef, $login{id}, $fid, ($page-1)*30)}) {
	my ($tid, $topic, $start, $msgs, $author, $lastdate, $lastauthor, $attr, $attached, $poll, $lastread, $clan, $lvl, $fact, $clan1, $lvl1, $fact1) = @$_;
	my $class = $num++ % 2 ? 'm1' : 'm2';
	my $msgclass = 'm_none';
	if ($lastread == $msgs) {
		$msgclass = 'm_nonew';
	} elsif (defined $lastread) {
		$msgclass = 'm_new';
	} elsif ($tid <= $forum->{lasttid}) {
		$msgclass = 'm_nonew';
	}

	print '<tr class="'.$class.'">';
	print '<td class="br">';
	print '<span title="Опубликовано" class="ts_published">@</span>' if ($attr =~ /published/);
	print '<span title="Опрос" class="ts_poll">%</span>' if ($poll);
	print '<span title="Закрыто" class="ts_closed">#</span>' if ($attr =~ /closed/ || $attr =~ /readonly/);
	print '<span title="Прикреплено" class="ts_attached">&</span>' if ($attached);
	print '<span title="Важно" class="ts_important">!</span>' if ($attr =~ /important/);
	print ' <a class="'.$msgclass.'" href="forum_messages.pl?id='.$tid.'">'.encode_entities($topic).'</a></td>';
	print '<td class="br">'.strftime("%d.%m, %H:%M", localtime $start).'</td>';
	print '<td class="br">'.$msgs.'</td>';

	print '<td class="br">';
		print '<a href="http://'.settings('hwm_url').'/clan_info.php?id='.$clan.'"><img width="20" border="0" align="absmiddle" height="15" alt="#'.$clan.'" src="http://im.heroeswm.ru/i_clans/l_'.$clan.'.gif"/></a> ' if ($clan && settings('pn_clan') eq 'yes');
		print link_to_pers($author);
		print " [$lvl]" if ($lvl && settings('pn_lvl') eq 'yes');
		print ' <img width="15" border="0" align="absmiddle" height="15" src="http://im.heroeswm.ru/i/r'.$fact.'.gif"/>' if ($fact && settings('pn_fact') eq 'yes');
	print '</td>';

	print '<td><a href="forum_messages.pl?id='.$tid.'&page=last">'.strftime("%d.%m, %H:%M", localtime $lastdate).'</a>, ';
		print '<a href="http://'.settings('hwm_url').'/clan_info.php?id='.$clan1.'"><img width="20" border="0" align="absmiddle" height="15" alt="#'.$clan1.'" src="http://im.heroeswm.ru/i_clans/l_'.$clan1.'.gif"/></a> ' if ($clan1 && settings('pn_clan') eq 'yes');
		print link_to_pers($lastauthor);
		print " [$lvl1]" if ($lvl1 && settings('pn_lvl') eq 'yes');
		print ' <img width="15" border="0" align="absmiddle" height="15" src="http://im.heroeswm.ru/i/r'.$fact1.'.gif"/>' if ($fact1 && settings('pn_fact') eq 'yes');
	print '</td>';
	print '</tr>';
}

if (!allowed_to('edit', $fid, $login{acl})) {
	print '<tr class="footertr"><td colspan=5></td></tr>';
}
print '</table>';
my @bans = get_bans($dbh, $login{id}, $forum->{catid}, $fid, 0);
print '<table width="100%"><tr><td width="33%" align="left" valign="top">';
if (!@bans && allowed_to('edit', $fid, $login{acl})) {
	print '<div class="newt" style="padding-top:5px;"><a href="new_topic.pl?id='.$fid.'">Создать новую тему</a></div>';
	if (allowed_to('poll', $fid, $login{acl})) {
		print '<div class="newt"><a href="new_topic.pl?poll&id='.$fid.'">Создать новый опрос</a></div>';
	}
}
print "</td><td width=\"33%\" align=\"center\">$nav_pages</td>";
print '<td width="33%" align="right" valign="top">';
if ($login{id}) {
	print '<div class="newt" style="padding-top:5px;"><a href="allread.pl?id='.$fid.'&chk='.gen_crc($login{sid}, 'allread'.$fid).'">Отметить как прочитанное</a></div>';
}
print '</td></tr></table>';
if (@bans) {
	print '<b>';
	print join '<br>', map {
		"Вы забанены смотрителем ".link_to_pers($_->[1])." до ".$_->[2]." (".$_->[0].")"
	} @bans;
	print '</b>';
}

if ($login{id}) {
	$dbh->do("INSERT INTO lastfread (uid, fid, topics, msgs) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE topics=?, msgs=?", undef, $login{id}, $fid, $forum->{topics}, $forum->{msgs}, $forum->{topics}, $forum->{msgs});
}

$dbh->disconnect();

print end_html();

}

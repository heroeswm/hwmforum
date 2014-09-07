package Forum::msg_history;
use strict;
use utf8;
use DBI;
use POSIX;
use CGI qw/-utf8 :standard/;
use Forum::Func;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub main
{
my $msgid = int(param('id'));
if ($msgid == 0) {
	print redirect('forum.pl');
	exit;
}

our $dbh = connect_db();
my %login = get_login($dbh);

my $forum = $dbh->selectrow_hashref('SELECT forums.name,threads.fid,threads.topic,threads.tid,service FROM (forums JOIN threads USING(fid)) JOIN msgs USING(tid) WHERE msgs.id=? LIMIT 1', undef, $msgid);
if (!ref $forum || !allowed_to('edit', $forum->{fid}, $login{acl})) {
	print redirect('forum.pl');
	$dbh->disconnect();
	exit;
}

print header(
	-type => 'text/html',
	-charset => 'UTF-8',
);
print_start_html('"'.$forum->{topic}.'"');

print '<div class="path"><a href="forum.pl">Форумы</a> &rarr; <a href="forum_thread.pl?id='.$forum->{fid}.'">'.encode_entities($forum->{name}).'</a> &rarr; <a href="forum_messages.pl?id='.$forum->{tid}.'">'.encode_entities($forum->{topic}).'</a></div>';
	
print '<table class="mt">
	<tr class="toptr">
		<th width="20%">Автор</th>';
print '<th width="80%" colspan="2">'.encode_entities($forum->{topic}).'</th>';
print '</tr>';

my $mnum = 0;
my $lastiss = 1;

my ($author, $clan, $lvl, $fact) = 
	$dbh->selectrow_array('SELECT u1.nick, plinfo.clan, plinfo.lvl, plinfo.fact FROM (msgs LEFT JOIN users as u1 ON msgs.author=u1.id) LEFT JOIN plinfo ON u1.id=plinfo.uid WHERE msgs.id=?', undef, $msgid);

#my @messages = @{$dbh->selectall_arrayref('SELECT content,UNIX_TIMESTAMP(date),ver FROM msgtext WHERE msgid=? AND date > DATE_SUB(NOW(), INTERVAL 1 DAY) ORDER BY ver ASC', undef, $msgid)};
my @messages = @{$dbh->selectall_arrayref('SELECT content,UNIX_TIMESTAMP(msgtext.date),ver FROM msgtext LEFT JOIN delmsg USING(`msgid`) WHERE msgid=? AND (delmsg.`date` IS NULL OR delmsg.date > DATE_SUB(NOW(), INTERVAL 1 DAY)) ORDER BY ver ASC', undef, $msgid)};
foreach (@messages) {
	my ($text, $date, $ver) = @$_;
	$mnum++;
	
	$text = encode_text($text, $forum->{service}, \%login);
		print '<tr class="m3">';
		print '<td rowspan="2" class="br'.(!$lastiss?' tb':'').'">';
		print '<a href="http://'.settings('hwm_url').'/clan_info.php?id='.$clan.'"><img width="20" border="0" align="absmiddle" height="15" alt="#'.$clan.'" src="http://im.heroeswm.ru/i_clans/l_'.$clan.'.gif"/></a> ' if ($clan && settings('pn_clan') eq 'yes');
		print '<b>'.link_to_pers($author).'</b>';
		print " [$lvl]" if ($lvl && settings('pn_lvl') eq 'yes');
		print ' <img width="15" border="0" align="absmiddle" height="15" src="http://im.heroeswm.ru/i/r'.$fact.'.gif"/>' if ($fact && settings('pn_fact') eq 'yes');
		print '<br/>';
		print '</td>';
		print '<td class="m3top'.(!$lastiss?' tb':'').'"><div class="msgnum">&nbsp;'.$ver.'&nbsp;</div> <span class="date">'.strftime("%F %T", localtime $date).'</span></td>';
		print '<td class="m3top'.(!$lastiss?' tb':'').'" align="right">';
		print '</td>';
		print '</tr>';
		print '<tr class="m2text">';
		print '<td colspan="2">'.$text.'</td>';
		print '</tr>';
		$lastiss = 0;
}

print '</table>';
$dbh->disconnect();

print end_html();
}

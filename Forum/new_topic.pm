package Forum::new_topic;
use strict;
use utf8;
use DBI;
use POSIX;
use CGI qw/-utf8 :standard/;
use Forum::Adds qw(is_premium_mod_default);
use Forum::Func;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub main
{
my $fid = int(param('id'));
if ($fid == 0) {
	print redirect('forum.pl');
	exit;
}

our $dbh = connect_db();
my %login = get_login($dbh);

my $forum = $dbh->selectrow_arrayref('SELECT name,catid FROM forums WHERE fid=? LIMIT 1', undef, $fid);
if (!ref $forum || !allowed_to('edit', $fid, $login{acl})) {
	print redirect('forum.pl');
	$dbh->disconnect();
	exit;
}
my @forum = @$forum;
my @bans = get_bans($dbh, $login{id}, $forum->[1], $fid, 0);
my $poll = (defined(param('poll')) || defined(param('choice1'))) && allowed_to('poll', $fid, $login{acl});

my $failreason = '';
if (param('chk') == gen_crc($login{sid}, 'newtopic'.$fid)) {
	my $uid = $login{id};
	my $msg = param('msg');
	$msg =~ s/^\s+|\s+$//g;
	my $topic = param('topic');
	$topic =~ s/^\s+|\s+$//g;
	if (!($msg && $topic)) {
	} elsif (@bans) {
		$failreason = 'Вы забанены.';
	} elsif (!check_limits($dbh, $login{id}, 'newtopic', [2, 15, 50])) {
		$failreason = 'Вы создаёте слишком много топиков, подождите немного.';
	} elsif (check_doublepost($dbh, \%login, $msg, -1)) {
		$failreason = 'Ваше последнее сообщение было таким же. Вероятно, даблпост.';
	} else {
		my @choices = ();
		if ($poll) {
			my $i=1;
			while(defined(param("choice$i"))) {
				my $choice = param("choice$i");
				$choice =~ s/^\s+|\s+$//g;
				push @choices, $choice if ($choice ne '');
				$i++;
			}
		}
		my $type = param('type') == 2 ? 2 : 1;
		$type = 0 if (@choices == 0);
		my $attrs = '';
		if (is_premium_mod_default($fid)) {
			$attrs = 'premium';
		}
		$dbh->do('INSERT INTO threads (fid,topic,msgs,author,poll,attr) VALUES (?, ?, ?, ?, ?, ?)', undef, $fid, $topic, 1, $uid, $type, $attrs);
		my $newid = $dbh->last_insert_id(undef, undef, undef, undef);
		$dbh->do('UPDATE forums SET topics=topics+1, msgs=msgs+1, last=? WHERE fid=?', undef, $newid, $fid);
		$dbh->do('INSERT INTO msgtext (msgid, content) VALUES (0, ?)', undef, $msg);
		my $cid = $dbh->last_insert_id(undef, undef, undef, undef);
		$dbh->do('INSERT INTO msgs (tid,cid,author,num) VALUES (?, ?, ?, ?)', undef, $newid, $cid, $uid, 1);
		my $msgid = $dbh->last_insert_id(undef, undef, undef, undef);
		$dbh->do('UPDATE msgtext SET msgid=? WHERE cid=?', undef, $msgid, $cid);
		my $i = 1;
		if (@choices) {
			$dbh->do("INSERT INTO poll_vars (tid, id, `desc`) VALUES " . join(",", map {
				" (".$dbh->quote($newid).', '.$dbh->quote($i++).', '.$dbh->quote($_).")"
			} @choices));
		}
		$dbh->do('UPDATE threads SET last=? WHERE tid=?', undef, $msgid, $newid);
		if ($login{id}) {
			$dbh->do("UPDATE lastfread SET topics=topics+1, msgs=msgs+1 WHERE uid=? AND fid=?", undef, $login{id}, $fid);
		}
		print redirect('forum_messages.pl?id='.$newid);
		$dbh->disconnect();
		exit;
	}
}
$dbh->disconnect();

print header(
	-type => 'text/html',
	-charset => 'UTF-8',
);
print_start_html('Новая тема');

print '<script language="javascript">
window.hwmforum = {
	tid: -1,
	bbpanel: "'.settings('bbpanel').'",
	token: '.gen_crc($login{sid}, 'dosmth-1').'
};</script>';

print '<div class="path"><a href="forum.pl">Форумы</a> &rarr; <a href="forum_thread.pl?id='.$fid.'">'.encode_entities($forum[0]).'</a></div>';

print '<div align="center"><form method="post" action="new_topic.pl" id="postform">';
print '<input type="hidden" name="id" value="'.$fid.'"/>';
print '<input type="hidden" name="chk" value="'.gen_crc($login{sid}, 'newtopic'.$fid).'"/>';
print '<table class="newmsg"><tr><th colspan=2>'.($poll?'Новый опрос':'Новая тема').'</th></tr>';
if ($failreason) {
	print '<tr><td colspan=2 class="failreason">Ошибка: '.$failreason.'</td></tr>';
}
print '<tr><td>Автор:</td><td><div style="width:100%"><div id="edit_author"><b>'.link_to_pers($login{nick}).'</b></div><div id="edit_panel"></div></div></td></tr>';
print '<tr><td>Тема:</td><td><input type="text" name="topic" maxlength=120/></td></tr>';
print '<tr><td>Сообщение:</td><td><textarea name="msg" id="msg" cols=70 rows=12></textarea></td></tr>';
if ($poll) {
	my $vars = abs((param('vars')?param('vars'):5));
	print '<tr><td id="answers_text" rowspan='.$vars.'>Ответы:</td>';
	print '<td class="pollvar"><input type="text" name="choice1" maxlength=120/></td></tr>';
	for (2..$vars) {
		print '<tr><td class="pollvar"><input type="text" name="choice'.$_.'" maxlength=120/></td></tr>';
	}
	print '<tr><td align="center" colspan=2><input type="radio" name="type" value="1" checked>один вариант выбора</input> <input type="radio" name="type" value="2">несколько вариантов выбора</input> <a id="newtopic_add" href="new_topic.pl?id='.$fid.'&poll&vars='.($vars+1).'">добавить вариант</a></td></tr>';
}
print '</table>';
print '<br><input type="submit" id="btn" value="Создать (Ctrl+Enter)"/></form></div>';

print end_html();
}

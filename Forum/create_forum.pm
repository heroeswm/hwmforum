package Forum::create_forum;
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
our $dbh = connect_db();
my %login = get_login($dbh);
if (!$login{id}) {
	return_smth('forum.pl');
	$dbh->disconnect();
	exit;
}

my $failreason = '';
my $CREATED = 0;
my $CREATED_gid = 0;
if (param('chk') == gen_crc($login{sid}, 'newforum')) {
	my $uid = $login{id};
	my $name = param('name');
	$name =~ s/^\s+|\s+$//g;
	my $desc = param('desc');
	$desc =~ s/^\s+|\s+$//g;
	if (!$name) {
		$failreason = 'Ошибка: пустое имя форума';
	} elsif (!check_limits($dbh, $login{id}, 'newforum', [1, 2, 2])) {
		$failreason = 'Вы создаёте слишком много форумов...';
	} elsif (${$dbh->selectcol_arrayref('SELECT COUNT(*) FROM ::forums WHERE name=?', undef, $name)}[0]) {
		$failreason = 'Форум с таким названием уже существует';
	} else {
		$dbh->do('INSERT INTO ::forums (catid,name,`desc`,weight) VALUES (?, ?, ?, ?)', undef, 5, $name, $desc, time());
		my $fid = $dbh->last_insert_id(undef, undef, undef, undef);
		$dbh->do('INSERT INTO ::groupdesc (`desc`) VALUES (?)', undef, $name);
		my $gid = $dbh->last_insert_id(undef, undef, undef, undef);
		$dbh->do('INSERT INTO ::groups (uid, gid, role) VALUES (?, ?, ?)', undef, $login{id}, $gid, "adm,mod,verb");
		$dbh->do('INSERT INTO ::aclist (gid, fid, type, actions) VALUES (?, ?, ?, ?)', undef, $gid, $fid, "allow", "view,edit,modifset,poll");
		$CREATED = $fid;
		$CREATED_gid = $gid;
	}
}
$dbh->disconnect();

print header(
	-type => 'text/html',
	-charset => 'UTF-8',
);
print_start_html('Новый форум');

print '<div class="path"><a href="forum.pl">Форумы</a> &rarr; <a href="">Новый форум</a></div>';

if ($CREATED) {
	print '<div align="center">';
	print '<table class="newmsg"><tr><th colspan=2>Создание нового форума</th></tr>';
	print '<tr><td>Поздравляем, вы создали форум <a href="forum_thread.pl?id='.$CREATED.'">'.encode_entities(param('name')).'</a>.</td></tr>';
	print '<tr><td>&nbsp;</td></tr>';
	print '<tr><td>Приглашать туда новых игроков можно <a href="group_adm.pl?id='.$CREATED_gid.'">здесь</a> (меню доступно в <a href="settings.pl">настройках</a>).</td></tr>';
	print '</table>';
	print '</div>';
} else {
	print '<div align="center"><form method="post" action="create_forum.pl">';
	print '<input type="hidden" name="chk" value="'.gen_crc($login{sid}, 'newforum').'"/>';
	print '<table class="newmsg"><tr><th colspan=2>Создание нового форума</th></tr>';
	if ($failreason) {
		print '<tr><td colspan=2 class="failreason">Ошибка: '.$failreason.'</td></tr>';
	} else {
		print '<tr><td colspan=2 style="padding-left: 30px;">
			Здесь вы можете создать свой подфорум. Он будет виден только тем, кого вы пригласите.<br>Это может быть использовано, например, для закрытых клановых форумов.<br>Вы можете составлять правила и назначать модераторов своего для подфорума по своему усмотрению.<br>Использование нецензурных выражений в названии форума строго запрещено.
		</td></tr>';
	}
	print '<tr><td>Название:</td><td><input type="text" name="name" value="'.encode_entities(param('name')).'" maxlength=63/></td></tr>';
	print '<tr><td>Описание:</td><td><input type="text" name="desc" value="'.encode_entities(param('desc')).'" maxlength=255/></td></tr>';
	print '</table>';
	print '<br><input type="submit" id="btn" value="Создать"/></form></div>';
}
print end_html();
}

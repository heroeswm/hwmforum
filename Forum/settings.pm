package Forum::settings;
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

sub xselect
{
	my $value = shift;
	my $hash = shift;
	my $sel = settings($value, shift());
	my $res = '<select name="'.$value.'">';
	while (@$hash) {
		my $key = shift @$hash;
		my $value = shift @$hash;
		$res .= '<option value="'.$key.'"'.($key eq $sel?' selected':'').'>'.$value.'</option>';
	}
	$res .= '</select>';
	return $res;
}

if (param('chk') == gen_crc($login{sid}, 'dosmth'.param('tid'))) {
	if (param('k') eq 'bbpanel') {
		$dbh->do('INSERT INTO settings (uid, name, value) VALUES(?, ?, ?) ON DUPLICATE KEY UPDATE value=?', undef, $login{id}, param('k'), param('v'), param('v'));
	}
	return_smth('settings.pl', 'ok');
	$dbh->disconnect();
	exit;
} elsif (param('chk') == gen_crc($login{sid}, 'settings')) {
	if (param('exitgroup')) {
		$dbh->do('DELETE FROM groups WHERE uid=? AND gid=?', undef, $login{id}, int param('exitgroup'));
	} elsif (param('acceptgroup')) {
		$dbh->do('UPDATE groups SET accepted=1 WHERE uid=? AND gid=?', undef, $login{id}, int param('acceptgroup'));
	} else {
		foreach ('pn_clan', 'pn_lvl', 'pn_fact', 'pn_avatar', 'show_author') {
			if (settings($_, 'def') ne param($_)) {
				$dbh->do('DELETE FROM settings WHERE uid=? AND name=?', undef, $login{id}, $_);
				$dbh->do('INSERT INTO settings (uid, name, value) VALUES(?, ?, ?)', undef, $login{id}, $_, param($_)) if (param($_) ne 'def');
			}
		}
		foreach ('hwm_url') {
			if (settings($_) ne param($_)) {
				$dbh->do('DELETE FROM settings WHERE uid=? AND name=?', undef, $login{id}, $_);
				$dbh->do('INSERT INTO settings (uid, name, value) VALUES(?, ?, ?)', undef, $login{id}, $_, param($_)) if (param($_) ne settings_def($_));
			}
		}
	}
	return_smth('settings.pl');
	$dbh->disconnect();
	exit;
}

print header(
	-type => 'text/html',
	-charset => 'UTF-8',
);
print_start_html('Настройки');

print '<div class="path"><a href="forum.pl">Форумы</a> &rarr; <a href="settings.pl">Настройки</a></div>';

print '<form method="post" action="settings.pl">';
print '<input type="hidden" name="chk" value="'.gen_crc($login{sid}, 'settings').'"/>';
print '<div align="center"><table class="mt" style="width:70%">
	<tr class="toptr">
		<th colspan="3" width="100%">Настройки</th>
	</tr>';

print '<tr class="m2">';
print '<td class="br" rowspan="4" width="33%">Показывать рядом с ником:</td>';
print '<td class="br" width="33%">значок клана</td>';
print '<td width="33%">'.xselect('pn_clan', [def => 'по умолчанию', 'yes' => 'да', 'no' => 'нет'], 'def').'</td>';
print '</tr>';
print '<tr class="m1">';
print '<td class="br">уровень игрока</td>';
print '<td width="33%">'.xselect('pn_lvl', [def => 'по умолчанию', 'yes' => 'да', 'no' => 'нет'], 'def').'</td>';
print '</tr>';
print '<tr class="m2">';
print '<td class="br">фракцию игрока</td>';
print '<td width="33%">'.xselect('pn_fact', [def => 'по умолчанию', 'yes' => 'да', 'no' => 'нет'], 'def').'</td>';
print '</tr>';
print '<tr class="m1">';
print '<td class="br">аватар игрока</td>';
print '<td width="33%">'.xselect('pn_avatar', [def => 'по умолчанию', 'yes' => 'да', 'no' => 'нет'], 'def').'</td>';
print '</tr>';
print '<tr class="m2">';
print '<td class="br">Показывать на главной странице:</td>';
print '<td colspan="2" align="center">'.xselect('show_author', [def => 'по умолчанию', 'first' => 'автора топика', 'last' => 'автора последнего сообщения'], 'def').'</td>';
print '</tr>';
print '<tr class="m1">';
print '<td class="br">Адрес сервера ГВД:</td>';
print '<td align="center" colspan=2>http://<input size="30" name="hwm_url" value="'.settings('hwm_url', 'www.heroeswm.ru').'">/</td>';
print '</tr>';
print '<tr class="toptr">
		<th width="100%" colspan="3"></th>
	</tr>';
print '</table><br/>';
print '<input type="submit" value="Сохранить настройки" /></div></form>';

print '<br/><div align="center"><table class="mt" style="width:70%">
	<tr class="toptr">
		<th width="100%" colspan="2">Членство в группах</th>
	</tr>';

my $num = 0;
foreach (@{$dbh->selectall_arrayref('SELECT groups.gid, role, accepted, `desc` FROM groups JOIN groupdesc USING(gid) WHERE uid=? ORDER BY gid ASC', undef, $login{id})}) {
	my ($gid, $role, $acc, $gdesc) = @$_;
	my $class = $num++ % 2 ? 'm1' : 'm2';
	print '<tr class="'.$class.'">';
	print '<td class="br">'.$gdesc.($acc?'':' (<b>приглашение</b>)').'</td>';
	print '<td align="center">';
	if (!$acc) {
		print '<a href="settings.pl?acceptgroup='.$gid.'&chk='.gen_crc($login{sid}, 'settings').'">Принять</a>';
		print ' / ';
		print '<a href="settings.pl?exitgroup='.$gid.'&chk='.gen_crc($login{sid}, 'settings').'">Отклонить</a>';
	} else {
		if (param('exitgroup') == $gid && $role !~ /adm/) {
			print '<form method="post" action="settings.pl">';
			print 'Выйти из группы: ';
			print '<input type="hidden" name="exitgroup" value="'.int(param('exitgroup')).'"/>';
			print '<input type="hidden" name="chk" value="'.gen_crc($login{sid}, 'settings').'"/>';
			print '<input type="submit" value="ok"/>';
				
			print '</form>';
		} elsif ($role =~ /adm/) {
			print '<a href="group_adm.pl?id='.$gid.'">Редактировать</a>';
		} elsif ($gid != 1) {
			if ($role =~ /verb/) {
				print '<a href="group_adm.pl?id='.$gid.'">Редактировать</a> / ';
			}
			print '<a href="settings.pl?exitgroup='.$gid.'">Выйти</a>';
		}
	}
	print '</td>';
	print '</tr>';
}
print '<tr class="toptr">
		<th width="100%" colspan="2"></th>
	</tr>';
print '<tr class="m2"><td colspan="2" align="center"><a href="create_forum.pl">Создать новый подфорум</a></td></tr>';
print '<tr class="toptr">
		<th width="100%" colspan="2"></th>
	</tr>';
print '</table><br/>';

$dbh->disconnect();

print end_html();
}

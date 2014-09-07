package Forum::register;
use strict;
use utf8;
use DBI;
use CGI qw/-utf8 :standard/;
use CGI::Cookie;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Forum::Func;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub try_register
{
	my $chk = shift;
	my $nick = param('nick');
	$nick =~ s/^\s+|\s+$//g;
	return "Не указан ник" if (!$nick);
	my $pass = param('pass');
	return "Не указан пароль" if (!$pass);
	my $pass2 = param('pass2');
	return "Не указано подтверждение пароля" if (!$pass2);
	if ($pass ne $pass2) {
		return "Введённые пароли не совпадают";
	}
	my $remote = get_remote_hash();
	my $dbh = connect_db();
	return "Слишком много попыток регистрации, попробуйте позже" if (!check_limits($dbh, $remote, 'reg', [3, 15, 50]));
	return "Слишком много попыток регистрации, попробуйте позже" if (!check_limits($dbh, 0, 'regall', [10, 100, 300]));

	my ($realnick, $id, $checked) = get_pers_hwm($nick, $chk);
	$nick = $realnick;
	if (not defined $id) {
		$dbh->disconnect();
		return "Ошибка доступа к серверу ГВД";
	} elsif ($id == 0) {
		$dbh->disconnect();
		return "Персонаж с ником <b>".link_to_pers($nick)."</b> в ГВД не существует";
	} elsif (!$checked) {
		$dbh->disconnect();
		return "Вы должны вставить проверочный код в инфу персонажа";
	}

	my $uid = 0;
	my $exists = $dbh->selectrow_arrayref('SELECT accs FROM accsonid WHERE id=?', undef, get_idnick_hash($id, $nick));
	if (ref $exists && $exists->[0]) {
		my $samenick = $dbh->selectrow_arrayref('SELECT id, gameid FROM users WHERE nick=? LIMIT 1', undef, $nick);
		if (ref($samenick) && check_idnick_hash($id, $nick, $samenick->[1])) {
			$uid = $samenick->[0];
			$dbh->do('UPDATE users SET password=? WHERE id=?', undef, crypt_password($pass), $samenick->[0]);
		} else {
			$dbh->disconnect();
			return "Вы уже зарегистрированы на этом форуме. Если вы забыли свой пароль, обратитесь к администратору форума";
		}
	} else {
		$dbh->do('INSERT INTO users (gameid, password, nick) VALUES(?, ?, ?)', undef, crypt_idnick_hash($id, $nick), crypt_password($pass), $nick);
		$uid = $dbh->last_insert_id(undef, undef, undef, undef);
		$dbh->do('INSERT INTO groups (uid, gid) VALUES(?, 1)', undef, $uid);
		$dbh->do('INSERT INTO accsonid (id, accs) VALUES(?, 1)', undef, get_idnick_hash($id, $nick));
	}
	make_login($dbh, $uid);
	$dbh->disconnect();
	return '';
}

sub get_chkcode 
{
	my $code = param('chk');
	my %cookies = fetch CGI::Cookie;
	if (exists $cookies{'ts'}) {
		if (!$code) {
			$code = $cookies{'ts'}->value;
		} elsif ($code && $code != $cookies{'ts'}->value) {
			return undef;
		}
	}
	if (!$code || ($code && $code < time()-60*60*2)) {
		return undef;
	}
	return $code;
}

sub main
{
my $code = get_chkcode();
my $failreason = undef;
if (param('nick') || param('pass') || param('pass2')) {
	if (defined($code)) {
		$failreason = try_register($code);
	}
	if ($failreason eq '') {
		exit;
	}
}
if (not defined $code) {
	$code = time();
}

my $cookie = new CGI::Cookie(-name=>'ts', -value=>$code, -expires=>'+2h');
	
print header(
	-type => 'text/html',
	-charset => 'UTF-8',
	-cookie => [$cookie],
);
print_start_html('Регистрация');

print '<table align="center">';
print '<form action="register.pl" method="POST">';
if (defined($failreason) && $failreason) {
	print '<tr><td colspan=2 class="failreason">Ошибка: '.$failreason.'</td></tr>';
}
print '<tr><td>Ваш игровой ник:</td><td><input name="nick" size="20" type="text" value="'.encode_entities(param('nick')).'"/></td></tr>';
print '<tr><td>Пароль на этом форуме:</td><td><input name="pass" size="20" type="password"/></td></tr>';
print '<tr><td>Подтверждение пароля:</td><td><input name="pass2" size="20" type="password"/></td></tr>';
print '<tr><td>Проверочный код:</td><td><input name="chk" type="hidden" value="'.encode_entities($code).'"><input size="20" name="code" type="text" readonly value="'.encode_entities(check_code($code)).'"/></td></tr>';
print '<tr><td align="center" colspan=2><input class="button" type="submit" value="Зарегистрироваться"/></td></tr>';
print '</form></table>';
print '<hr><br>
<table><tr><td width="30%">&nbsp;</td><td width="40%">Для тех, кто не в курсе: <br>
<ul>
<li>Проверочный код нужно вставить в инфу персонажа, чтоб подтвердить, что вы и указанный вами персонаж в ГВД - это одно лицо. После регистрации код можно убирать.
<li>Пароли нигде не сохраняются, однако использовать игровой пароль не рекомендуется по понятным причинам.
</ul>
</td><td width="30%">&nbsp;</td></tr>';

print end_html();
}

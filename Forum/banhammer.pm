package Forum::banhammer;
use strict;
use utf8;
use DBI;
use CGI qw/-utf8 :standard/;
use POSIX;
use Forum::Func;
use base 'Exporter';

our @EXPORT_OK = qw(main);

sub main
{
print header(
	-type => 'text/html',
	-charset => 'UTF-8',
);
print_start_html('Банхаммер');

print '<div class="path"><a href="forum.pl">Форумы</a> &rarr; <a href="banhammer.pl">БАК</a> (<span style="color: #999999; text-decoration: line-through;">Большой Адронный Коллайдер</span> Большая Админская Кнопка)</div>';
#print '<div class="desc desc_logo">Секретный раздел форума.</div>';
print '<div class="bh_div">';
if (param('ban')) {
	print '<div class="bh_result">';
	if (rand() < 0.5) {
		print 'Вы подняли банхаммер и сделали выстрел, заставив птиц на соседнем дереве упасть вниз. От смеха. Потому что вы - нуб, а банхаммер - оружие настоящих модераторов!'
	} else {
		print 'Вы выстрелили из банхаммера и случайно забанили себя на два дня. Потому что вы - нуб, а банхаммер - оружие настоящих модераторов!'
	}
	print '</div>';
} else {
	print '<form method="POST"><input type="submit" name="ban" value="BAN"/></form>';
}
print '</div>';

print end_html();
}
